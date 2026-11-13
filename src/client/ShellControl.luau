-- Driving a shell from the Chimera's client. The server owns the shell's position; this client runs the
-- same ShellMotor on its own inputs so the body responds instantly, sends every input to the server,
-- and when the server's authoritative state for an input disagrees with the prediction, rewinds to it
-- and replays the newer inputs, smoothing the visual difference away. Slows, staggers and roots reach
-- this client as the server's speed scale, which the prediction uses from then on.
-- It also finds what the shell's actions would hit: the Interface target under the crosshair, the
-- System Leap node nearest the crosshair, and a downed merc in reach to Assimilate.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Config = require(ReplicatedStorage.Shared.Config)
local FacilityMap = require(ReplicatedStorage.Shared.FacilityMap)
local Net = require(ReplicatedStorage.Shared.Net)
local ShellMotor = require(ReplicatedStorage.Shared.ShellMotor)
local ShellRig = require(ReplicatedStorage.Shared.ShellRig)
local Hud = require(script.Parent.Hud)
local TargetHighlight = require(script.Parent.TargetHighlight)

export type Target = { kind: string, id: string, instance: Instance }
export type LeapNode = { id: string, name: string, position: Vector3 }

type HistoryEntry = { input: ShellMotor.Input, state: ShellMotor.State }

type Active = {
	nonce: number,
	shellId: string,
	state: ShellMotor.State,
	prev: ShellMotor.State,
	seq: number,
	lastAck: number,
	history: { [number]: HistoryEntry },
	sent: { { any } },
	accumulator: number,
	correction: Vector3,
	yaw: number,
	pitch: number,
	phase: number,
	rig: Model,
	corrections: number,
	speedScale: number,
	action: { kind: string, startedAt: number, seconds: number }?,
	bodyHidden: boolean,
	bornAt: number?, -- server time the shell was taken: its panels lock into place from then (ShellRig)
}

local ShellControl = {}

local DT = ShellMotor.DT
local TWO_PI = 2 * math.pi
local MOUSE_SENSITIVITY = 0.3 -- degrees per pixel
local CAMERA_OFFSET = Vector3.new(1.8, 0.8, 9)

local active: Active? = nil
local inputRemote: UnreliableRemoteEvent
local folder: Folder
local cameraParams = RaycastParams.new()
local aimParams = RaycastParams.new()
local target: Target? = nil
local aimPoint: Vector3? = nil
local leapNodes: { LeapNode } = {}
local leapCandidate: LeapNode? = nil
local assimilateCandidate: Model? = nil
local obstacleAt = 0
local ui: { [string]: any } = {}
local testMove: { forward: number, right: number, jump: boolean }? = nil -- Studio tests drive the shell here

local function key(code: Enum.KeyCode): number
	return if UserInputService:IsKeyDown(code) then 1 else 0
end

local function sampleInput(a: Active): ShellMotor.Input
	local forward, right, jump = 0, 0, false
	if testMove then
		forward, right, jump = testMove.forward, testMove.right, testMove.jump
	elseif not UserInputService:GetFocusedTextBox() then
		forward = key(Enum.KeyCode.W) - key(Enum.KeyCode.S)
		right = key(Enum.KeyCode.D) - key(Enum.KeyCode.A)
		jump = UserInputService:IsKeyDown(Enum.KeyCode.Space)
	end
	local yaw = a.yaw % TWO_PI
	local fwd = Vector3.new(-math.sin(yaw), 0, -math.cos(yaw))
	local rightVec = Vector3.new(math.cos(yaw), 0, -math.sin(yaw))
	local move = fwd * forward + rightVec * right
	if move.Magnitude > 1 then
		move = move.Unit
	end
	return { mx = move.X, mz = move.Z, jump = jump, yaw = yaw, speedScale = a.speedScale }
end

-- Merc bodies (players' and Studio dummies') the shell can't walk through, as this client sees them.
local function refreshObstacles()
	local list = {}
	for _, other in Players:GetPlayers() do
		if other.Character and other:GetAttribute("Role") == "Merc" then
			table.insert(list, other.Character)
		end
	end
	for _, child in workspace:GetChildren() do
		if child:IsA("Model") and child:GetAttribute("MercTag") and not Players:GetPlayerFromCharacter(child) then
			table.insert(list, child)
		end
	end
	ShellMotor.setObstacles(list)
end

local function updateAim(camera: Camera, a: Active, feet: Vector3)
	target = nil
	local origin = camera.CFrame.Position
	local look = camera.CFrame.LookVector
	local result = workspace:Raycast(origin, look * (Config.Shell.SightRange + CAMERA_OFFSET.Magnitude), aimParams)
	aimPoint = if result then result.Position else nil
	if result then
		local kind, id = FacilityMap.targetOf(result.Instance)
		if kind and kind ~= "TakeShell" and type(id) == "string" then
			local adornee = if kind == "Blackout" then (result.Instance.Parent or result.Instance) else (result.Instance:FindFirstAncestorOfClass("Model") or result.Instance)
			target = { kind = kind, id = id, instance = adornee }
		end
	end
	TargetHighlight.set(if target then target.instance else nil)

	-- System Leap: the camera or terminal within range closest to the crosshair.
	leapCandidate = nil
	local bestDot = math.cos(math.rad(25))
	for _, node in leapNodes do
		local offset = node.position - origin
		if (node.position - feet).Magnitude <= Config.Modules.SystemLeap.Range and offset.Magnitude > 4 then
			local dot = look:Dot(offset.Unit)
			if dot > bestDot then
				bestDot = dot
				leapCandidate = node
			end
		end
	end

	-- Assimilate: the nearest downed merc in reach.
	assimilateCandidate = nil
	local chest = feet + Vector3.new(0, 3, 0)
	local bestDistance = Config.Health.AssimilateRange
	for _, model in workspace:GetChildren() do
		if model:IsA("Model") and model:GetAttribute("Downed") == true then
			local root = model:FindFirstChild("HumanoidRootPart") :: BasePart?
			local distance = root and (root.Position - chest).Magnitude
			if distance and distance <= bestDistance then
				bestDistance = distance
				assimilateCandidate = model
			end
		end
	end
end

local function render(dt: number)
	local a = active
	if not a then
		return
	end
	UserInputService.MouseBehavior = Enum.MouseBehavior.LockCenter
	local delta = UserInputService:GetMouseDelta()
	a.yaw -= math.rad(delta.X * MOUSE_SENSITIVITY)
	a.pitch = math.clamp(a.pitch - math.rad(delta.Y * MOUSE_SENSITIVITY), -1.2, 1.0)

	local now = os.clock()
	if now - obstacleAt > 0.5 then
		obstacleAt = now
		refreshObstacles()
	end

	-- Fixed-step prediction, one input per tick, exactly like the server consumes them.
	a.accumulator += dt
	local steps = 0
	while a.accumulator >= DT and steps < 4 do
		a.accumulator -= DT
		steps += 1
		local input = sampleInput(a)
		a.seq += 1
		a.prev = a.state
		a.state = ShellMotor.step(a.state, input, DT)
		a.history[a.seq] = { input = input, state = a.state }
		a.history[a.seq - 120] = nil
		table.insert(a.sent, { a.seq, input.mx, input.mz, input.jump, input.yaw })
		if #a.sent > 3 then
			table.remove(a.sent, 1)
		end
		inputRemote:FireServer(a.nonce, a.sent)
	end
	if a.accumulator >= DT then
		a.accumulator = 0
	end

	local alpha = a.accumulator / DT
	local feet = a.prev.pos:Lerp(a.state.pos, alpha) + a.correction
	a.correction *= math.exp(-dt * 12)
	local speed = Vector3.new(a.state.vel.X, 0, a.state.vel.Z).Magnitude
	a.phase += dt * speed * 0.55
	local action = nil
	if a.action then
		local progress = (now - a.action.startedAt) / a.action.seconds
		if progress >= 1 then
			a.action = nil
		else
			action = { kind = a.action.kind, progress = progress }
		end
	end
	ShellRig.setAssembly(a.rig, if a.bornAt then workspace:GetServerTimeNow() - a.bornAt else nil)
	ShellRig.pose(a.rig, CFrame.new(feet) * CFrame.Angles(0, a.yaw, 0), a.phase, math.clamp(speed / Config.Shell.WalkSpeed, 0, 1), now, action)

	local camera = workspace.CurrentCamera
	local pivot = feet + Vector3.new(0, 4.4, 0)
	local rotation = CFrame.Angles(0, a.yaw, 0) * CFrame.Angles(a.pitch, 0, 0)
	local desired = (CFrame.new(pivot) * rotation * CFrame.new(CAMERA_OFFSET)).Position
	local offset = desired - pivot
	local hit = workspace:Raycast(pivot, offset, cameraParams)
	local cameraPosition = if hit then pivot + offset.Unit * math.max(0.4, hit.Distance - 0.5) else desired
	camera.CameraType = Enum.CameraType.Scriptable
	camera.FieldOfView = 70
	camera.CFrame = CFrame.new(cameraPosition) * rotation
	-- With a wall right behind, the camera ends up inside the body: hide it rather than fill the view.
	local hideBody = (cameraPosition - pivot).Magnitude < 3
	if hideBody ~= a.bodyHidden then
		a.bodyHidden = hideBody
		for _, part in a.rig:GetChildren() do
			if part:IsA("BasePart") then
				part.LocalTransparencyModifier = if hideBody then 1 else 0
			end
		end
	end
	updateAim(camera, a, feet)
end

local function onAuth(nonce: any, ackSeq: any, x: any, y: any, z: any, vx: any, vy: any, vz: any, grounded: any, speedScale: any)
	local a = active
	if not a or nonce ~= a.nonce or type(ackSeq) ~= "number" then
		return
	end
	if type(speedScale) == "number" then
		a.speedScale = speedScale
	end
	if ackSeq <= a.lastAck then
		return
	end
	a.lastAck = ackSeq
	for seq in a.history do
		if seq < ackSeq then
			a.history[seq] = nil
		end
	end
	local entry = a.history[ackSeq]
	if not entry then
		return
	end
	local server: ShellMotor.State = { pos = Vector3.new(x, y, z), vel = Vector3.new(vx, vy, vz), grounded = grounded == true }
	if (entry.state.pos - server.pos).Magnitude < 0.01 and (entry.state.vel - server.vel).Magnitude < 0.05 and entry.state.grounded == server.grounded then
		return
	end
	-- Rewind to the server's state and replay every input it hasn't processed yet.
	a.corrections += 1
	local s = server
	entry.state = s
	for seq = ackSeq + 1, a.seq do
		local later = a.history[seq]
		if later then
			later.input.speedScale = a.speedScale
			s = ShellMotor.step(s, later.input, DT)
			later.state = s
		end
	end
	local shift = a.state.pos - s.pos
	if shift.Magnitude > 6 then
		a.correction = Vector3.zero
		a.prev = s
	else
		a.correction += shift
		a.prev = { pos = a.prev.pos - shift, vel = a.prev.vel, grounded = a.prev.grounded }
	end
	a.state = s
end

function ShellControl.init(clientFolder: Folder, doorTargets: Folder)
	folder = clientFolder
	inputRemote = Net.get("ShellInput")
	Net.get("ShellAuth").OnClientEvent:Connect(onAuth)
	local map, facility = FacilityMap.folders()
	cameraParams.FilterType = Enum.RaycastFilterType.Include
	cameraParams.FilterDescendantsInstances = { map }
	aimParams.FilterType = Enum.RaycastFilterType.Include
	local include = { map, facility:WaitForChild("Lights"), doorTargets }
	local traps = facility:FindFirstChild("Traps")
	if traps then
		table.insert(include, traps)
	end
	aimParams.FilterDescendantsInstances = include
	for id, cam in FacilityMap.cameras() do
		table.insert(leapNodes, { id = id, name = cam.displayName, position = cam.origin })
	end
	for id, terminal in FacilityMap.terminals() do
		local console = terminal.model.PrimaryPart
		if console then
			table.insert(leapNodes, { id = id, name = terminal.displayName, position = console.Position })
		end
	end
end

function ShellControl.start(info: { [string]: any })
	ShellControl.stop()
	local feet = Vector3.new(info.x, info.y, info.z)
	-- The body starts unformed and locks itself together over the first moments (see render).
	local rig = ShellRig.build("OwnShell", true)
	ShellRig.setLook(rig, "owner")
	rig.Parent = folder
	local state = ShellMotor.new(feet)
	active = {
		nonce = info.nonce,
		shellId = info.shellId,
		state = state,
		prev = state,
		seq = 0,
		lastAck = 0,
		history = {},
		sent = {},
		accumulator = 0,
		correction = Vector3.zero,
		yaw = info.yaw or 0,
		pitch = -0.15,
		phase = 0,
		rig = rig,
		corrections = 0,
		speedScale = 1,
		action = nil,
		bodyHidden = false,
		bornAt = tonumber(info.bornAt),
	}
	refreshObstacles()
	local gui = Hud.gui()
	ui.crosshair = Hud.frame(gui, {
		Name = "Crosshair",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(6, 6),
		BackgroundColor3 = Hud.WHITE,
		BackgroundTransparency = 0.2,
	})
	ui.hints = Hud.hints({
		"WASD move   Space jump   Mouse look",
		"LMB Energy Claws   E Interface / hold E Assimilate",
		"R System Leap   F Static Decoy (aim at the floor)",
		"Hold Q  leave the shell (1 s)",
	})
	UserInputService.MouseIconEnabled = false
	RunService:BindToRenderStep("ChimeraShell", Enum.RenderPriority.Camera.Value + 1, render)
end

function ShellControl.stop()
	if not active then
		return
	end
	RunService:UnbindFromRenderStep("ChimeraShell")
	active.rig:Destroy()
	active = nil
	target = nil
	aimPoint = nil
	leapCandidate = nil
	assimilateCandidate = nil
	TargetHighlight.set(nil)
	for _, key in { "crosshair", "hints" } do
		if ui[key] then
			ui[key]:Destroy()
			ui[key] = nil
		end
	end
	UserInputService.MouseBehavior = Enum.MouseBehavior.Default
	UserInputService.MouseIconEnabled = true
end

function ShellControl.isActive(): boolean
	return active ~= nil
end

function ShellControl.target(): Target?
	return target
end

function ShellControl.aimPoint(): Vector3?
	return aimPoint
end

function ShellControl.leapCandidate(): LeapNode?
	return leapCandidate
end

function ShellControl.assimilateCandidate(): Model?
	return assimilateCandidate
end

-- Play a body action locally (a claw swipe now; assimilation or a leap channel as the server confirms).
function ShellControl.playAction(kind: string, seconds: number)
	if active then
		active.action = { kind = kind, startedAt = os.clock(), seconds = seconds }
	end
end

function ShellControl.stopAction()
	if active then
		active.action = nil
	end
end

function ShellControl.promptAnchor(): Vector2
	local viewport = workspace.CurrentCamera.ViewportSize
	return Vector2.new(viewport.X / 2 + 16, viewport.Y / 2 + 16)
end

function ShellControl.describe(): { [string]: any }?
	local a = active
	if not a then
		return nil
	end
	local p = a.state.pos
	return {
		shellId = a.shellId,
		seq = a.seq,
		lastAck = a.lastAck,
		corrections = a.corrections,
		speedScale = a.speedScale,
		pos = { math.floor(p.X * 100) / 100, math.floor(p.Y * 100) / 100, math.floor(p.Z * 100) / 100 },
		yaw = a.yaw,
		target = target and { kind = target.kind, id = target.id },
		leap = leapCandidate and leapCandidate.id,
		assimilate = assimilateCandidate and assimilateCandidate.Name,
		body = ShellRig.describe(a.rig),
	}
end

-- For tests: face a direction and walk without the keyboard. Pass nil to hand control back.
function ShellControl.setTestInput(yaw: number?, forward: number?, right: number?, jump: boolean?)
	if active and yaw then
		active.yaw = yaw
	end
	if forward == nil and right == nil and not jump then
		testMove = nil
	else
		testMove = { forward = forward or 0, right = right or 0, jump = jump == true }
	end
end

-- For tests: point the camera (pitch and yaw) at a world point.
function ShellControl.testLookAt(point: Vector3)
	local a = active
	if not a then
		return
	end
	local eye = a.state.pos + Vector3.new(0, 4.4, 0)
	local d = (point - eye).Unit
	a.yaw = math.atan2(-d.X, -d.Z)
	a.pitch = math.asin(math.clamp(d.Y, -1, 1))
end

return ShellControl
