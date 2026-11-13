-- The Chimera's server-side state: facility mode (one camera at a time, 0.5 s hops between linked
-- cameras), energy, Interface actions, and taking and leaving shells. A Chimera is an "agent", driven by
-- a player or by a test bot; both go through the same rules except where noted.
--
-- Only the Chimera's own client hears about any of this (ChimeraState). Mercs get the red light on the
-- camera it's watching and the tells of its actions, and nothing else.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Net = require(ReplicatedStorage.Shared.Net)
local Cues = require(script.Parent.Cues)
local Docks = require(script.Parent.Docks)
local Doors = require(script.Parent.Doors)
local Lights = require(script.Parent.Lights)
local MapData = require(script.Parent.MapData)
local Shells = require(script.Parent.Shells)
local Sight = require(script.Parent.Sight)
local Terminals = require(script.Parent.Terminals)

export type Mode = "facility" | "hopping" | "shell"

export type Hold = { kind: string, targetId: string?, cameraId: string?, startedAt: number, endsAt: number }

export type Agent = {
	key: string,
	player: Player?,
	mode: Mode,
	cameraId: string,
	hopTarget: string?,
	hopEndsAt: number,
	energy: number,
	shell: Shells.Shell?,
	hold: Hold?,
	noDrain: boolean,
	tokens: number,
	lastSync: number,
}

local Chimera = {}

local C = Config.Chimera
local REC_ON = Color3.fromRGB(255, 25, 25)
local REC_OFF = Color3.fromRGB(35, 35, 38)

local agents: { [string]: Agent } = {}
local byPlayer: { [Player]: Agent } = {}
local watchers: { [string]: number } = {}
local stateRemote: RemoteEvent

local INSTANT = { Blackout = true, LockDoor = true }
local HOLDS = { TakeShell = true, CorruptTerminal = true }

local function send(agent: Agent, message: { [string]: any })
	if agent.player then
		stateRemote:FireClient(agent.player, message)
	end
end

local function toast(agent: Agent, text: string)
	send(agent, { type = "toast", text = text })
end

local function energyRate(agent: Agent): number
	if agent.mode == "shell" then
		return if agent.noDrain then 0 else -Config.Shell.Drain
	end
	return if agent.energy >= C.EnergyMax then 0 else C.EnergyRegen
end

local function syncEnergy(agent: Agent)
	agent.lastSync = os.clock()
	send(agent, { type = "energy", value = agent.energy, rate = energyRate(agent) })
end

-- The red light: on while any agent watches through that camera. It's the one thing about facility
-- mode that mercs receive.
local function watch(cameraId: string, on: boolean)
	watchers[cameraId] = math.max(0, (watchers[cameraId] or 0) + (if on then 1 else -1))
	local cam = MapData.cameras[cameraId]
	local rec = cam and cam.recLight
	if not rec then
		return
	end
	local lit = watchers[cameraId] > 0
	rec.Color = if lit then REC_ON else REC_OFF
	rec.Material = if lit then Enum.Material.Neon else Enum.Material.SmoothPlastic
	local light = rec:FindFirstChildOfClass("PointLight")
	if light then
		light.Enabled = lit
	end
end

local function targetOf(kind: string, id: string): ({ Vector3 }?, Instance?)
	if kind == "Blackout" then
		local room = MapData.rooms[id]
		return if room then MapData.lightPoints(room) else nil, nil
	elseif kind == "LockDoor" then
		local door = MapData.doors[id]
		return if door then MapData.doorPoints(door) else nil, if door then door.model else nil
	elseif kind == "CorruptTerminal" then
		local terminal = MapData.terminals[id]
		return if terminal then MapData.terminalPoints(terminal) else nil, if terminal then terminal.model else nil
	elseif kind == "TakeShell" then
		local dock = MapData.docks[id]
		return if dock then MapData.dockPoints(dock) else nil, if dock then dock.model else nil
	end
	return nil, nil
end

-- Can this agent see the target right now, from its camera or its shell?
local function canSee(agent: Agent, kind: string, id: string): boolean
	local points, target = targetOf(kind, id)
	if not points or #points == 0 then
		return false
	end
	if agent.mode == "shell" then
		return agent.shell ~= nil and Sight.shellSees(agent.shell.state.pos, points, target)
	elseif agent.mode == "facility" then
		local cam = MapData.cameras[agent.cameraId]
		return cam ~= nil and Sight.cameraSees(cam, points, target)
	end
	return false
end

-- The camera the Chimera returns to when it leaves a shell: the nearest one in the shell's room,
-- or the nearest anywhere if the shell wasn't in a room.
local function nearestCamera(feet: Vector3): string
	local chest = feet + Vector3.new(0, 3, 0)
	local room = MapData.roomAt(chest)
	local best, bestDistance = nil, math.huge
	local bestInRoom, bestInRoomDistance = nil, math.huge
	for id, cam in MapData.cameras do
		local distance = (cam.origin - chest).Magnitude
		if distance < bestDistance then
			best, bestDistance = id, distance
		end
		if room and cam.room == room and distance < bestInRoomDistance then
			bestInRoom, bestInRoomDistance = id, distance
		end
	end
	return bestInRoom or best or C.StartCamera
end

local function cancelHold(agent: Agent, reason: string?)
	local hold = agent.hold
	if not hold then
		return
	end
	agent.hold = nil
	if hold.kind == "TakeShell" and hold.targetId then
		Docks.setBooting(hold.targetId, false)
	end
	send(agent, { type = "holdEnd", kind = hold.kind, ok = false, reason = reason })
end

local function enterShell(agent: Agent, dockId: string)
	local dock = MapData.docks[dockId]
	if not dock or not Docks.take(dockId) then
		return false
	end
	if agent.mode == "facility" then
		watch(agent.cameraId, false)
	end
	local shell = Shells.spawn(agent, agent.player, dock.spawn, dockId)
	agent.shell = shell
	agent.mode = "shell"
	local p = shell.state.pos
	send(agent, { type = "shellTaken", shellId = shell.id, nonce = shell.nonce, x = p.X, y = p.Y, z = p.Z, yaw = shell.yaw })
	syncEnergy(agent)
	return true
end

-- The shell collapses and is recycled; the Chimera returns to the nearest camera.
local function leaveShell(agent: Agent, reason: string)
	local shell = agent.shell
	if not shell then
		return
	end
	cancelHold(agent, reason)
	local feet = shell.state.pos
	agent.shell = nil
	agent.cameraId = nearestCamera(feet)
	agent.mode = "facility"
	watch(agent.cameraId, true)
	Shells.remove(shell, "collapse")
	Cues.emit("ShellCollapse", feet + Vector3.new(0, 2, 0), Config.Shell.CollapseRange)
	send(agent, { type = "shellLeft", cameraId = agent.cameraId, reason = reason })
	syncEnergy(agent)
end

local function beginHop(agent: Agent, targetId: any)
	if agent.mode ~= "facility" then
		return toast(agent, if agent.mode == "hopping" then "Already relinking" else "Leave the shell first")
	end
	local cam = MapData.cameras[agent.cameraId]
	if type(targetId) ~= "string" or not cam or not table.find(cam.links, targetId) or not MapData.cameras[targetId] then
		return toast(agent, "That camera isn't linked to this one")
	end
	cancelHold(agent, "hop")
	watch(agent.cameraId, false)
	agent.mode = "hopping"
	agent.hopTarget = targetId
	agent.hopEndsAt = os.clock() + C.HopSeconds
	send(agent, { type = "hopStart", from = agent.cameraId, to = targetId, seconds = C.HopSeconds })
end

local function finishHop(agent: Agent)
	agent.cameraId = agent.hopTarget or agent.cameraId
	agent.hopTarget = nil
	agent.mode = "facility"
	watch(agent.cameraId, true)
	send(agent, { type = "hopDone", cameraId = agent.cameraId })
end

local function checkAction(agent: Agent, kind: string, id: string): string?
	local settings = Config.Interface[kind]
	if not settings then
		return "Unknown action"
	end
	if agent.mode == "hopping" then
		return "Relinking"
	end
	if kind == "TakeShell" then
		if agent.mode ~= "facility" then
			return "Shells can only be taken from a camera"
		end
		local state = Docks.state(id)
		if state == nil then
			return "Unknown dock"
		elseif state == "empty" then
			return "That dock is empty"
		end
	elseif kind == "CorruptTerminal" then
		if Terminals.isLocked(id) then
			return "That terminal is locked"
		end
	elseif kind == "LockDoor" then
		if Doors.isLocked(id) then
			return "Already locked"
		end
	elseif kind == "Blackout" then
		if Lights.isDark(id) then
			return "Already dark"
		end
	end
	if agent.energy < settings.Cost then
		return "Not enough energy"
	end
	if not canSee(agent, kind, id) then
		return "Can't see that from here"
	end
	return nil
end

local function instantAction(agent: Agent, kind: string, id: string)
	local problem = checkAction(agent, kind, id)
	if problem then
		return toast(agent, problem)
	end
	local ok, err
	if kind == "Blackout" then
		ok, err = Lights.blackout(id)
	else
		ok, err = Doors.lock(id)
	end
	if not ok then
		return toast(agent, err or "That didn't work")
	end
	agent.energy -= Config.Interface[kind].Cost
	syncEnergy(agent)
	send(agent, { type = "acted", kind = kind, id = id })
end

local function beginHold(agent: Agent, kind: string, id: string)
	cancelHold(agent, "replaced")
	local problem = checkAction(agent, kind, id)
	if problem then
		toast(agent, problem)
		return send(agent, { type = "holdEnd", kind = kind, ok = false, reason = problem })
	end
	local now = os.clock()
	local seconds = Config.Interface[kind].HoldSeconds
	agent.hold = {
		kind = kind,
		targetId = id,
		cameraId = if agent.mode == "facility" then agent.cameraId else nil,
		startedAt = now,
		endsAt = now + seconds,
	}
	if kind == "TakeShell" then
		-- The tell: the dormant shell's eyes light red and its servos whine.
		Docks.setBooting(id, true)
		local dock = MapData.docks[id]
		Cues.emit("ServoWhine", (dock.spawn * CFrame.new(0, 3, 0)).Position, Config.Shell.WhineRange)
	end
	send(agent, { type = "holdStart", kind = kind, id = id, seconds = seconds })
end

local function beginLeave(agent: Agent)
	if agent.mode ~= "shell" then
		return
	end
	cancelHold(agent, "replaced")
	local now = os.clock()
	agent.hold = { kind = "Leave", startedAt = now, endsAt = now + Config.Shell.LeaveHoldSeconds }
	send(agent, { type = "holdStart", kind = "Leave", seconds = Config.Shell.LeaveHoldSeconds })
end

local function completeHold(agent: Agent, hold: Hold)
	agent.hold = nil
	if hold.kind == "Leave" then
		send(agent, { type = "holdEnd", kind = "Leave", ok = true })
		leaveShell(agent, "left")
		return
	end
	local id = hold.targetId :: string
	local problem = checkAction(agent, hold.kind, id)
	if hold.kind == "TakeShell" then
		if not problem and agent.cameraId ~= hold.cameraId then
			problem = "Camera changed"
		end
		if problem then
			Docks.setBooting(id, false)
		end
	end
	if problem then
		toast(agent, problem)
		return send(agent, { type = "holdEnd", kind = hold.kind, ok = false, reason = problem })
	end
	if hold.kind == "TakeShell" then
		agent.energy -= Config.Interface.TakeShell.Cost
		send(agent, { type = "holdEnd", kind = hold.kind, ok = true })
		if not enterShell(agent, id) then
			agent.energy += Config.Interface.TakeShell.Cost
			toast(agent, "That dock is empty")
		end
	else
		local ok, err = Terminals.corrupt(id)
		if ok then
			agent.energy -= Config.Interface.CorruptTerminal.Cost
			send(agent, { type = "holdEnd", kind = hold.kind, ok = true })
			syncEnergy(agent)
		else
			toast(agent, err or "That didn't work")
			send(agent, { type = "holdEnd", kind = hold.kind, ok = false, reason = err })
		end
	end
end

-- Cheap checks every tick while a hold runs; the full check (sight included) happens on completion.
local function holdStillValid(agent: Agent, hold: Hold): string?
	if hold.kind == "Leave" then
		return if agent.mode == "shell" then nil else "Not in a shell"
	elseif hold.kind == "TakeShell" then
		if agent.mode ~= "facility" or agent.cameraId ~= hold.cameraId then
			return "Camera changed"
		end
		if Docks.state(hold.targetId :: string) ~= "booting" then
			return "That dock is empty"
		end
	elseif hold.kind == "CorruptTerminal" then
		if agent.mode == "hopping" then
			return "Relinking"
		end
	end
	return nil
end

local function snapshot(agent: Agent)
	local shell = agent.shell
	local message: { [string]: any } = {
		type = "snapshot",
		mode = agent.mode,
		cameraId = agent.cameraId,
		energy = agent.energy,
		rate = energyRate(agent),
	}
	if shell then
		local p = shell.state.pos
		message.shell = { shellId = shell.id, nonce = shell.nonce, x = p.X, y = p.Y, z = p.Z, yaw = shell.yaw }
	end
	send(agent, message)
end

local function newAgent(key: string, player: Player?): Agent
	local start = if MapData.cameras[C.StartCamera] then C.StartCamera else next(MapData.cameras)
	local agent: Agent = {
		key = key,
		player = player,
		mode = "facility",
		cameraId = start :: string,
		hopTarget = nil,
		hopEndsAt = 0,
		energy = C.EnergyStart,
		shell = nil,
		hold = nil,
		noDrain = false,
		tokens = C.ActionRateLimit,
		lastSync = 0,
	}
	agents[key] = agent
	watch(agent.cameraId, true)
	return agent
end

local function removeAgent(agent: Agent)
	if agent.shell then
		local shell = agent.shell
		agent.shell = nil
		Shells.remove(shell, "collapse")
	end
	cancelHold(agent, "removed")
	if agent.mode == "facility" then
		watch(agent.cameraId, false)
	end
	agent.mode = "facility"
	agents[agent.key] = nil
	if agent.player then
		byPlayer[agent.player] = nil
	end
end

local function onAction(player: Player, kind: any, payload: any)
	local agent = byPlayer[player]
	if not agent or type(kind) ~= "string" then
		return
	end
	if agent.tokens < 1 then
		return
	end
	agent.tokens -= 1
	if kind == "hop" then
		beginHop(agent, payload)
	elseif kind == "interface" or kind == "holdBegin" then
		if type(payload) ~= "table" or type(payload.kind) ~= "string" or type(payload.id) ~= "string" then
			return
		end
		if kind == "interface" and INSTANT[payload.kind] then
			instantAction(agent, payload.kind, payload.id)
		elseif kind == "holdBegin" and HOLDS[payload.kind] then
			beginHold(agent, payload.kind, payload.id)
		end
	elseif kind == "holdCancel" then
		if agent.hold and agent.hold.kind ~= "Leave" then
			cancelHold(agent, "released")
		end
	elseif kind == "leaveBegin" then
		beginLeave(agent)
	elseif kind == "leaveCancel" then
		if agent.hold and agent.hold.kind == "Leave" then
			cancelHold(agent, "released")
		end
	elseif kind == "sync" then
		snapshot(agent)
	end
end

function Chimera.init()
	stateRemote = Net.get("ChimeraState")
	Net.get("ChimeraAction").OnServerEvent:Connect(onAction)
	Shells.onFell(function(shell)
		local agent = shell.owner
		if agent and agents[agent.key] == agent and agent.shell == shell then
			leaveShell(agent, "fell")
		end
	end)
end

function Chimera.addPlayer(player: Player): Agent
	local existing = byPlayer[player]
	if existing then
		removeAgent(existing)
	end
	local agent = newAgent(`player:{player.UserId}`, player)
	byPlayer[player] = agent
	snapshot(agent)
	return agent
end

function Chimera.removePlayer(player: Player)
	local agent = byPlayer[player]
	if agent then
		removeAgent(agent)
	end
end

function Chimera.agentOf(player: Player): Agent?
	return byPlayer[player]
end

function Chimera.agents(): { [string]: Agent }
	return agents
end

-- Where the Chimera hears from: its shell's eyes, or the camera it's in.
function Chimera.listenerOf(player: Player): Vector3?
	local agent = byPlayer[player]
	if not agent then
		return nil
	end
	if agent.shell then
		return agent.shell.state.pos + Vector3.new(0, Config.Shell.EyeHeight, 0)
	end
	local cam = MapData.cameras[agent.hopTarget or agent.cameraId]
	return cam and cam.origin
end

-- Test bots (Studio only, see Debug): an agent with no player that takes a shell straight from a dock.
function Chimera.addBot(key: string): Agent
	local existing = agents[key]
	if existing then
		removeAgent(existing)
	end
	local agent = newAgent(key, nil)
	agent.noDrain = true
	return agent
end

function Chimera.removeBot(key: string)
	local agent = agents[key]
	if agent and not agent.player then
		removeAgent(agent)
	end
end

function Chimera.botTakeShell(agent: Agent, dockId: string): Shells.Shell?
	if agent.mode == "shell" then
		return agent.shell
	end
	if enterShell(agent, dockId) then
		return agent.shell
	end
	return nil
end

function Chimera.setEnergy(agent: Agent, value: number)
	agent.energy = math.clamp(value, 0, C.EnergyMax)
	syncEnergy(agent)
end

function Chimera.tick(dt: number)
	local now = os.clock()
	for _, agent in agents do
		agent.tokens = math.min(C.ActionRateLimit * 2, agent.tokens + C.ActionRateLimit * dt)

		if agent.mode == "hopping" and now >= agent.hopEndsAt then
			finishHop(agent)
		end

		if agent.mode == "shell" then
			if not agent.noDrain then
				agent.energy -= Config.Shell.Drain * dt
			end
			if agent.energy <= 0 then
				agent.energy = 0
				leaveShell(agent, "energy")
			end
		else
			agent.energy = math.min(C.EnergyMax, agent.energy + C.EnergyRegen * dt)
		end

		local hold = agent.hold
		if hold then
			local problem = holdStillValid(agent, hold)
			if problem then
				cancelHold(agent, problem)
			elseif now >= hold.endsAt then
				completeHold(agent, hold)
			end
		end

		if now - agent.lastSync >= 1 then
			syncEnergy(agent)
		end
	end
end

return Chimera
