-- Driving a shell from the Chimera's client. The server owns the shell's position; this client runs the
-- same ShellMotor on its own inputs so the body responds instantly, sends every input to the server,
-- and when the server's authoritative state for an input disagrees with the prediction, rewinds to it
-- and replays the newer inputs, smoothing the visual difference away.
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
	return { mx = move.X, mz = move.Z, jump = jump, yaw = yaw }
end

local function updateAim(camera: Camera, a: Active)
	target = nil
	local origin = camera.CFrame.Position
	local direction = camera.CFrame.LookVector * (Config.Shell.SightRange + CAMERA_OFFSET.Magnitude)
	local result = workspace:Raycast(origin, direction, aimParams)
	if result then
		local kind, id = FacilityMap.targetOf(result.Instance)
		if kind and kind ~= "TakeShell" and type(id) == "string" then
			local adornee = if kind == "Blackout" then (result.Instance.Parent or result.Instance) else (result.Instance:FindFirstAncestorOfClass("Model") or result.Instance)
			target = { kind = kind, id = id, instance = adornee }
		end
	end
	TargetHighlight.set(if target then target.instance else nil)
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
	ShellRig.pose(a.rig, CFrame.new(feet) * CFrame.Angles(0, a.yaw, 0), a.phase, math.clamp(speed / Config.Shell.WalkSpeed, 0, 1), os.clock())

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
	updateAim(camera, a)
end

local function onAuth(nonce: any, ackSeq: any, x: any, y: any, z: any, vx: any, vy: any, vz: any, grounded: any)
	local a = active
	if not a or nonce ~= a.nonce or type(ackSeq) ~= "number" or ackSeq <= a.lastAck then
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
			s = ShellMotor.step(s, later.input, DT)
			later.state = s
		end
	end
	local shift = a.state.pos - s.pos
	if shift.Magnitude > 6 then
		a.correction = Vector3.zero
	else
		a.correction += shift
	end
	a.prev = { pos = a.prev.pos - shift, vel = a.prev.vel, grounded = a.prev.grounded }
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
	aimParams.FilterDescendantsInstances = { map, facility:WaitForChild("Lights"), doorTargets }
end

function ShellControl.start(info: { [string]: any })
	ShellControl.stop()
	local feet = Vector3.new(info.x, info.y, info.z)
	local rig = ShellRig.build("OwnShell")
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
	}
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
		"WASD  move   Space  jump   Mouse  look",
		"E  Interface on what you aim at",
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
		pos = { math.floor(p.X * 100) / 100, math.floor(p.Y * 100) / 100, math.floor(p.Z * 100) / 100 },
		yaw = a.yaw,
		target = target and { kind = target.kind, id = target.id },
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

return ShellControl
