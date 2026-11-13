-- The Chimera's server-side state: facility mode (one camera at a time, 0.5 s hops between linked
-- cameras), energy, Interface actions, and taking and leaving shells. A Chimera is an "agent", driven by
-- a player or by a test bot; both go through the same rules except where noted. Shell combat lives in
-- ShellCombat; Static Decoy and Overload, which also work from a camera, in Decoys and Traps.
--
-- Only the Chimera's own client hears about any of this (ChimeraState). Mercs get the red light on the
-- camera it's watching and the tells of its actions, and nothing else.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Net = require(ReplicatedStorage.Shared.Net)
local Cues = require(script.Parent.Cues)
local Decoys = require(script.Parent.Decoys)
local Docks = require(script.Parent.Docks)
local Doors = require(script.Parent.Doors)
local Lights = require(script.Parent.Lights)
local MapData = require(script.Parent.MapData)
local MatchEvents = require(script.Parent.MatchEvents)
local MatchState = require(script.Parent.MatchState)
local SecurityCameras = require(script.Parent.SecurityCameras)
local ShellCombat = require(script.Parent.ShellCombat)
local Shells = require(script.Parent.Shells)
local Sight = require(script.Parent.Sight)
local Terminals = require(script.Parent.Terminals)
local Traps = require(script.Parent.Traps)

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
	takeBlockedUntil: number, -- after a shell is destroyed with the Chimera inside
	decoyReadyAt: number,
	lastAlertAt: number,
	locked: boolean, -- in a finale the Chimera can't leave its body
}

local Chimera = {}

local C = Config.Chimera
local REC_ON = Color3.fromRGB(255, 25, 25)
local REC_OFF = Color3.fromRGB(35, 35, 38)

local agents: { [string]: Agent } = {}
local byPlayer: { [Player]: Agent } = {}
local watchers: { [string]: number } = {}
local stateRemote: RemoteEvent
local bodyLostListeners: { (Agent, string) -> () } = {}

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

-- In either finale a body doesn't drain energy, so the Chimera can fight for the full two minutes.
local function drains(agent: Agent): boolean
	return not agent.noDrain and MatchState.finale == nil
end

local function energyRate(agent: Agent): number
	if agent.mode == "shell" then
		return if drains(agent) then -Config.Shell.Drain else 0
	end
	return if agent.energy >= C.EnergyMax then 0 else C.EnergyRegen * MatchState.regenScale()
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
	elseif kind == "Overload" then
		return Traps.points(id), nil
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

-- force: boot a shell at this dock whatever its state (a finale's body); a stocked dock still gives up
-- its dormant shell.
local function enterShell(agent: Agent, dockId: string, force: boolean?)
	local dock = MapData.docks[dockId]
	if not dock then
		return false
	end
	if not Docks.take(dockId) and not force then
		return false
	end
	if agent.mode == "facility" then
		watch(agent.cameraId, false)
	elseif agent.mode == "hopping" then
		agent.cameraId = agent.hopTarget or agent.cameraId
		agent.hopTarget = nil
	end
	local shell = Shells.spawn(agent, agent.player, dock.spawn, dockId)
	agent.shell = shell
	agent.mode = "shell"
	local p = shell.state.pos
	send(agent, { type = "shellTaken", shellId = shell.id, nonce = shell.nonce, x = p.X, y = p.Y, z = p.Z, yaw = shell.yaw })
	syncEnergy(agent)
	ShellCombat.statusOf(shell)
	return true
end

local function serverTime(clockTime: number): number
	return workspace:GetServerTimeNow() + (clockTime - os.clock())
end

-- Module cooldowns and counts for the Chimera's HUD.
local function sendModules(agent: Agent)
	send(agent, {
		type = "modules",
		decoyReadyAt = serverTime(agent.decoyReadyAt),
		trapsArmed = Traps.armedBy(agent.key),
		trapsMax = Config.Modules.Overload.MaxTraps,
		takeBlockedUntil = serverTime(agent.takeBlockedUntil),
	})
end

-- reason "left"/"energy"/"fell": the shell collapses and is recycled. "destroyed": mercs shot it to
-- pieces, which also blocks taking another shell for 20 s. Either way the Chimera returns to the
-- nearest camera.
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
	if reason == "destroyed" then
		Shells.remove(shell, "destroyed")
		agent.takeBlockedUntil = os.clock() + Config.Combat.DestroyedTakeBlock
		sendModules(agent)
	else
		Shells.remove(shell, "collapse")
		Cues.emit("ShellCollapse", feet + Vector3.new(0, 2, 0), Config.Shell.CollapseRange)
	end
	send(agent, { type = "shellLeft", cameraId = agent.cameraId, reason = reason })
	syncEnergy(agent)
	for _, listener in bodyLostListeners do
		task.spawn(listener, agent, reason)
	end
end

local function beginHop(agent: Agent, targetId: any)
	if agent.mode ~= "facility" then
		return toast(agent, if agent.mode == "hopping" then "Already relinking" else "Leave the shell first")
	end
	local cam = MapData.cameras[agent.cameraId]
	if type(targetId) ~= "string" or not cam or not table.find(cam.links, targetId) or not MapData.cameras[targetId] then
		return toast(agent, "That camera isn't linked to this one")
	end
	if SecurityCameras.isBroken(targetId) then
		return toast(agent, "That camera is offline")
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
	if not MatchState.interfaceOnline() then
		return "Still booting: Interface comes online when the race starts"
	end
	if kind == "TakeShell" then
		if agent.mode ~= "facility" then
			return "Shells can only be taken from a camera"
		end
		local blocked = agent.takeBlockedUntil - os.clock()
		if blocked > 0 then
			return string.format("Shell printing locked for %d s", math.ceil(blocked))
		end
		local state = Docks.state(id)
		if state == nil then
			return "Unknown dock"
		elseif state == "empty" then
			return "That dock is empty"
		elseif state == "offline" then
			return "That dock is shut down"
		end
	elseif kind == "CorruptTerminal" then
		if Terminals.isDone(id) then
			return "That terminal is already rebooted"
		end
		if Terminals.isLocked(id) then
			return "That terminal is locked"
		end
	elseif kind == "LockDoor" then
		if Doors.isWelded(id) then
			return "That door is welded shut"
		end
		if Doors.isLocked(id) then
			return "Already locked"
		end
	elseif kind == "Blackout" then
		if MatchState.finale == "Purge" and id == MatchState.coreRoom then
			return "The Core is floodlit"
		end
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
	if agent.locked then
		toast(agent, if MatchState.finale == "Purge" then "Lockdown: you're locked into this body" else "No leaving during the finale")
		return send(agent, { type = "holdEnd", kind = "Leave", ok = false, reason = "locked" })
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
	sendModules(agent)
	if shell then
		ShellCombat.statusOf(shell)
	end
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
		takeBlockedUntil = 0,
		decoyReadyAt = 0,
		lastAlertAt = 0,
		locked = false,
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
	Traps.disarmAll(agent.key)
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

-- Overload (Sabotage): arm a steam pipe or conduit the Chimera can see, from a camera or a shell.
local function armTrap(agent: Agent, id: string)
	if agent.mode == "hopping" then
		return toast(agent, "Relinking")
	end
	if not MatchState.interfaceOnline() then
		return toast(agent, "Still booting: Interface comes online when the race starts")
	end
	if not Traps.get(id) then
		return toast(agent, "No such trap")
	end
	if not canSee(agent, "Overload", id) then
		return toast(agent, "Can't see that from here")
	end
	local ok, err = Traps.arm(agent.key, id)
	if not ok then
		return toast(agent, err or "That didn't work")
	end
	send(agent, { type = "acted", kind = "Overload", id = id })
end

-- Static Decoy (Utility): a fake merc walking from the aimed floor point, from a camera or a shell.
local function castDecoy(agent: Agent, point: any)
	local now = os.clock()
	if not MatchState.interfaceOnline() then
		return toast(agent, "Still booting: modules come online when the race starts")
	end
	if now < agent.decoyReadyAt then
		return toast(agent, string.format("Static Decoy ready in %d s", math.ceil(agent.decoyReadyAt - now)))
	end
	local origin, range
	if agent.mode == "shell" and agent.shell then
		origin, range = agent.shell.state.pos + Vector3.new(0, Config.Shell.EyeHeight, 0), Config.Shell.SightRange
	elseif agent.mode == "facility" then
		local cam = MapData.cameras[agent.cameraId]
		origin, range = cam and cam.origin, Config.Interface.CameraRange
	end
	if not origin then
		return toast(agent, "Relinking")
	end
	local ok, err = Decoys.cast(origin, point, range)
	if not ok then
		return toast(agent, err or "That didn't work")
	end
	agent.decoyReadyAt = now + Config.Modules.StaticDecoy.Cooldown * MatchState.cooldownScale()
	sendModules(agent)
end

-- A merc shot out the camera the Chimera was in (or hopping to): throw it to a working linked camera
-- with 2 s of static.
local function workingCameraNear(id: string, exclude: string?): string?
	local cam = MapData.cameras[id]
	if cam then
		for _, link in cam.links do
			if link ~= exclude and not SecurityCameras.isBroken(link) then
				return link
			end
		end
	end
	local best, bestDistance = nil, math.huge
	for otherId, other in MapData.cameras do
		if otherId ~= exclude and otherId ~= id and not SecurityCameras.isBroken(otherId) then
			local d = if cam then (other.origin - cam.origin).Magnitude else 0
			if d < bestDistance then
				best, bestDistance = otherId, d
			end
		end
	end
	return best
end

local function onCameraBroken(id: string)
	for _, agent in agents do
		if agent.mode == "facility" and agent.cameraId == id then
			local target = workingCameraNear(id, id)
			if target then
				cancelHold(agent, "camera lost")
				watch(id, false)
				agent.mode = "hopping"
				agent.hopTarget = target
				agent.hopEndsAt = os.clock() + Config.Combat.ForcedHopSeconds
				send(agent, { type = "hopStart", from = id, to = target, seconds = Config.Combat.ForcedHopSeconds, forced = true })
				toast(agent, "Camera shot out")
			end
		elseif agent.mode == "hopping" and agent.hopTarget == id then
			local target = workingCameraNear(agent.cameraId, id) or agent.cameraId
			agent.hopTarget = target
			send(agent, { type = "hopStart", from = agent.cameraId, to = target, seconds = math.max(0.1, agent.hopEndsAt - os.clock()), forced = true })
		end
	end
end

-- Alerts when a dormant shell is hit, at most once a second per agent.
local function onDormantHit(dockId: string, destroyed: boolean)
	local dock = MapData.docks[dockId]
	for _, agent in agents do
		local now = os.clock()
		if destroyed or now - agent.lastAlertAt >= 1 then
			agent.lastAlertAt = now
			send(agent, {
				type = "alert",
				text = if destroyed then `Dormant shell destroyed: {dock and dock.displayName or dockId}` else `Dormant shell under fire: {dock and dock.displayName or dockId}`,
				dockId = dockId,
			})
		end
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
		if kind == "interface" and payload.kind == "Overload" then
			armTrap(agent, payload.id)
		elseif kind == "interface" and INSTANT[payload.kind] then
			instantAction(agent, payload.kind, payload.id)
		elseif kind == "holdBegin" and HOLDS[payload.kind] then
			beginHold(agent, payload.kind, payload.id)
		end
	elseif kind == "attack" then
		local result = ShellCombat.attack(agent)
		if result then
			send(agent, { type = "clawHit", result = result })
		end
	elseif kind == "assimilateBegin" then
		ShellCombat.beginAssimilate(agent)
	elseif kind == "assimilateCancel" then
		ShellCombat.cancelAssimilate(agent)
	elseif kind == "leap" then
		ShellCombat.beginLeap(agent, payload)
	elseif kind == "decoy" then
		castDecoy(agent, payload)
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
	ShellCombat.init(send, function(shell, by)
		local agent = shell.owner
		if agent and agents[agent.key] == agent and agent.shell == shell then
			MatchEvents.fire("ShellDestroyed", { agent = agent, by = by })
			leaveShell(agent, "destroyed")
		end
	end)
	SecurityCameras.onBroken(onCameraBroken)
	Docks.onHit(onDormantHit)
end

-- Traps call this when an agent's armed count changes.
function Chimera.modulesChanged(agentKey: string)
	local agent = agents[agentKey]
	if agent then
		sendModules(agent)
	end
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

-- Finales: put the Chimera in a body at this dock now (see enterShell's force).
function Chimera.forceBody(agent: Agent, dockId: string): Shells.Shell?
	if agents[agent.key] ~= agent then
		return nil
	end
	if agent.shell then
		return agent.shell
	end
	cancelHold(agent, "boot")
	if not enterShell(agent, dockId, true) then
		return nil
	end
	local dock = MapData.docks[dockId]
	Cues.emit("ServoWhine", (dock.spawn * CFrame.new(0, 3, 0)).Position, Config.Shell.WhineRange)
	return agent.shell
end

-- In a finale the Chimera can't leave its body.
function Chimera.setLocked(agent: Agent, locked: boolean)
	agent.locked = locked
end

-- listener(agent, reason) runs whenever an agent loses its shell: "left", "energy", "fell" or "destroyed".
function Chimera.onBodyLost(listener: (Agent, string) -> ())
	table.insert(bodyLostListeners, listener)
end

function Chimera.notify(agent: Agent, message: { [string]: any })
	send(agent, message)
end

-- An alert on every Chimera's HUD (a reboot started, Lockdown...).
function Chimera.alertAll(text: string, extra: { [string]: any }?)
	for _, agent in agents do
		local message: { [string]: any } = { type = "alert", text = text }
		for key, value in extra or {} do
			message[key] = value
		end
		send(agent, message)
	end
end

-- A new round: no Chimera agents (players' or test bots') are left.
function Chimera.clear()
	for _, agent in agents do
		removeAgent(agent)
	end
end

function Chimera.tick(dt: number)
	local now = os.clock()
	for _, agent in agents do
		agent.tokens = math.min(C.ActionRateLimit * 2, agent.tokens + C.ActionRateLimit * dt)

		if agent.mode == "hopping" and now >= agent.hopEndsAt then
			finishHop(agent)
		end

		if agent.mode == "shell" then
			if drains(agent) then
				agent.energy -= Config.Shell.Drain * dt
			end
			if agent.energy <= 0 then
				agent.energy = 0
				leaveShell(agent, "energy")
			end
		else
			agent.energy = math.min(C.EnergyMax, agent.energy + C.EnergyRegen * MatchState.regenScale() * dt)
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
