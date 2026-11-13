-- Perception-gated replication. Any client can read whatever the server sends it, so a merc's client only
-- ever receives a shell's position while that merc can perceive the shell:
--   Cloaked   within 45 studs with line of sight
--   Exposed   line of sight at any range (up to ExposedRange)
--   Revealed  every living merc
--   Overwatch the camera an eliminated merc watches can see it (hook for milestone 2)
-- Dock contents are gated the same way: a merc learns that a dock emptied (or is booting) only when they
-- can see the dock or are standing near it. The Chimera's own client gets every dock change at once.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)
local Net = require(ReplicatedStorage.Shared.Net)
local Docks = require(script.Parent.Docks)
local MapData = require(script.Parent.MapData)
local SecurityCameras = require(script.Parent.SecurityCameras)
local Shells = require(script.Parent.Shells)
local Sight = require(script.Parent.Sight)

type ShellView = { visible: boolean, lostAt: number?, reason: string }
type MercView = {
	shells: { [string]: ShellView },
	docks: { [string]: string },
	overwatchCamera: string?,
	debug: boolean,
}

local Perception = {}

local P = Config.Perception

local views: { [Player]: MercView } = {}
local chimeras: { [Player]: boolean } = {}
local shellRemote: RemoteEvent
local dockRemote: RemoteEvent
local debugRemote: RemoteEvent?

local function shellPoints(shell: Shells.Shell, from: Vector3): { Vector3 }
	local feet = shell.state.pos
	local chest = feet + Vector3.new(0, 3, 0)
	local flat = Vector3.new(chest.X - from.X, 0, chest.Z - from.Z)
	local side = if flat.Magnitude > 0.01
		then Vector3.new(-flat.Z, 0, flat.X).Unit * P.SidePadding
		else Vector3.new(P.SidePadding, 0, 0)
	local v = shell.state.vel
	return {
		chest,
		feet + Vector3.new(0, 4.6, 0),
		feet + Vector3.new(0, 1, 0),
		chest + side,
		chest - side,
		chest + Vector3.new(v.X, 0, v.Z) * P.LeadSeconds,
	}
end

-- Does this merc perceive this shell right now? The reason string feeds the Studio debug overlay.
local function evaluate(view: MercView, eye: Vector3?, eyeLead: Vector3?, shell: Shells.Shell, wasVisible: boolean): (boolean, string)
	if shell.visibility == "Revealed" then
		return true, "revealed"
	end
	if view.overwatchCamera then
		local cam = MapData.cameras[view.overwatchCamera]
		if SecurityCameras.isBroken(view.overwatchCamera) then
			return false, "overwatch: camera shot out"
		end
		if cam and Sight.cameraSees(cam, shellPoints(shell, cam.origin), nil) then
			return true, "overwatch camera"
		end
		return false, "overwatch: not on camera"
	end
	if not eye or not eyeLead then
		return false, "no body"
	end
	local chest = shell.state.pos + Vector3.new(0, 3, 0)
	local distance = (chest - eye).Magnitude
	local range = if shell.visibility == "Exposed" then P.ExposedRange else P.CloakedRange
	if wasVisible then
		range += P.RangeHysteresis
	end
	if distance > range then
		return false, string.format("out of range (%.1f)", distance)
	end
	local points = shellPoints(shell, eye)
	if Sight.anyClear(eye, points) or Sight.anyClear(eyeLead, points) then
		return true, string.format("line of sight (%.1f)", distance)
	end
	return false, string.format("blocked (%.1f)", distance)
end

local function seesDock(eye: Vector3, eyeLead: Vector3, dock): boolean
	local center = (dock.spawn * CFrame.new(0, 3, 0)).Position
	local distance = (center - eye).Magnitude
	if distance <= P.DockNearRange then
		return true
	end
	if distance > P.DockSightRange then
		return false
	end
	local points = MapData.dockPoints(dock)
	return Sight.anyClear(eye, points, dock.model) or Sight.anyClear(eyeLead, points, dock.model)
end

-- { kind, id, time, x, y, z, yaw, speed, visibility, epoch, action, actionProgress }
local function pack(kind: string, shell: Shells.Shell, serverTime: number): { any }
	local p = shell.state.pos
	local v = shell.state.vel
	local action, progress = nil, 0
	if shell.anim then
		action = shell.anim.kind
		progress = math.clamp((os.clock() - shell.anim.startedAt) / shell.anim.seconds, 0, 1)
	end
	return { kind, shell.id, serverTime, p.X, p.Y, p.Z, shell.yaw, math.sqrt(v.X * v.X + v.Z * v.Z), shell.visibility, shell.epoch, action, progress }
end

function Perception.addMerc(player: Player)
	chimeras[player] = nil
	local known = {}
	for id in MapData.docks do
		known[id] = "stocked"
	end
	views[player] = { shells = {}, docks = known, overwatchCamera = nil, debug = false }
	-- A merc starts out believing every dock is stocked, and learns otherwise only by looking.
	local snapshot = {}
	for id, state in known do
		table.insert(snapshot, { id, state })
	end
	dockRemote:FireClient(player, snapshot)
end

function Perception.addChimera(player: Player)
	views[player] = nil
	chimeras[player] = true
	local snapshot = {}
	for id, state in Docks.all() do
		table.insert(snapshot, { id, state })
	end
	dockRemote:FireClient(player, snapshot)
end

function Perception.remove(player: Player)
	local view = views[player]
	if view then
		local batch = {}
		for id, shellView in view.shells do
			if shellView.visible then
				table.insert(batch, { "hide", id })
			end
		end
		if #batch > 0 and player.Parent then
			shellRemote:FireClient(player, batch)
		end
	end
	views[player] = nil
	chimeras[player] = nil
end

function Perception.setOverwatch(player: Player, cameraId: string?)
	local view = views[player]
	if view then
		view.overwatchCamera = cameraId
	end
end

function Perception.setDebug(player: Player, on: boolean)
	local view = views[player]
	if view then
		view.debug = on
	end
end

-- For tests and the debug overlay: what this merc currently perceives.
function Perception.describe(player: Player): { [string]: any }?
	local view = views[player]
	if not view then
		return nil
	end
	local shells = {}
	for id, shellView in view.shells do
		shells[id] = { visible = shellView.visible, reason = shellView.reason }
	end
	return { shells = shells, docks = table.clone(view.docks), overwatchCamera = view.overwatchCamera }
end

function Perception.tick()
	local now = os.clock()
	local serverTime = workspace:GetServerTimeNow()
	local shells = Shells.all()
	for player, view in views do
		local character = player.Character
		local head = character and character:FindFirstChild("Head") :: BasePart?
		local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		local eye, eyeLead = nil, nil
		if head and root and humanoid and humanoid.Health > 0 then
			eye = head.Position
			local v = root.AssemblyLinearVelocity
			eyeLead = eye + Vector3.new(v.X, 0, v.Z) * P.LeadSeconds
		end

		local batch = {}
		for id, shell in shells do
			local shellView = view.shells[id]
			if not shellView then
				shellView = { visible = false, lostAt = nil, reason = "" }
				view.shells[id] = shellView
			end
			local sees, reason = evaluate(view, eye, eyeLead, shell, shellView.visible)
			shellView.reason = reason
			if sees then
				shellView.lostAt = nil
				table.insert(batch, pack(if shellView.visible then "update" else "show", shell, serverTime))
				shellView.visible = true
			elseif shellView.visible then
				shellView.lostAt = shellView.lostAt or now
				if now - (shellView.lostAt :: number) >= P.LostGraceSeconds then
					shellView.visible = false
					shellView.lostAt = nil
					table.insert(batch, { "hide", id })
				else
					table.insert(batch, pack("update", shell, serverTime))
				end
			end
		end
		if #batch > 0 then
			shellRemote:FireClient(player, batch)
		end

		if eye and eyeLead then
			local dockBatch = {}
			for id, dock in MapData.docks do
				local truth = Docks.state(id)
				if truth and view.docks[id] ~= truth and seesDock(eye, eyeLead, dock) then
					view.docks[id] = truth
					table.insert(dockBatch, { id, truth })
				end
			end
			if #dockBatch > 0 then
				dockRemote:FireClient(player, dockBatch)
			end
		end

		if view.debug and debugRemote then
			local summary = {}
			for id, shellView in view.shells do
				summary[id] = { shellView.visible, shellView.reason }
			end
			debugRemote:FireClient(player, "perception", summary)
		end
	end
end

function Perception.init()
	shellRemote = Net.get("ShellView")
	dockRemote = Net.get("DockView")
	if RunService:IsStudio() then
		debugRemote = Net.get("Debug")
	end

	Shells.onRemoved(function(shell, reason)
		local p = shell.state.pos
		for player, view in views do
			local shellView = view.shells[shell.id]
			if shellView and shellView.visible then
				if reason == "collapse" or reason == "destroyed" then
					shellRemote:FireClient(player, { { "collapse", shell.id, workspace:GetServerTimeNow(), p.X, p.Y, p.Z, shell.yaw, reason == "destroyed" } })
				else
					shellRemote:FireClient(player, { { "hide", shell.id } })
				end
			end
			view.shells[shell.id] = nil
		end
	end)

	Docks.onChanged(function(id, state)
		for player in chimeras do
			dockRemote:FireClient(player, { { id, state } })
		end
	end)
end

return Perception
