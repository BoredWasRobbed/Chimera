-- Studio-only test tools. Nothing here runs in a live server.
--   Debug remote (the in-game DEV panel): switch role, a test shell that patrols or hunts, its
--   visibility state, the perception overlay, dummy mercs, class, "down me", respawn, door locks.
--   ServerScriptService.ChimeraTestHook (BindableFunction): JSON state and commands for automated checks.
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")

local Config = require(ReplicatedStorage.Shared.Config)
local Net = require(ReplicatedStorage.Shared.Net)
local Chimera = require(script.Parent.Chimera)
local Decoys = require(script.Parent.Decoys)
local Docks = require(script.Parent.Docks)
local Doors = require(script.Parent.Doors)
local Health = require(script.Parent.Health)
local Lights = require(script.Parent.Lights)
local MapData = require(script.Parent.MapData)
local Perception = require(script.Parent.Perception)
local Roles = require(script.Parent.Roles)
local SecurityCameras = require(script.Parent.SecurityCameras)
local ShellCombat = require(script.Parent.ShellCombat)
local Shells = require(script.Parent.Shells)
local Traps = require(script.Parent.Traps)
local Weapons = require(script.Parent.Weapons)

local Debug = {}

local BOT_KEY = "bot:test"
local VISIBILITY_ORDER = { Cloaked = "Exposed", Exposed = "Revealed", Revealed = "Cloaked" }
local DEFAULT_PATROL = {
	Vector3.new(26, 0, 26),
	Vector3.new(-26, 0, 26),
	Vector3.new(-26, 0, -26),
	Vector3.new(26, 0, -26),
}

local botTarget: { Vector3 } = DEFAULT_PATROL
local botIndex = 1
local botPaused = false
local botHunts = false
local dummyCount = 0

local function still(shell)
	return { mx = 0, mz = 0, jump = false, yaw = shell.yaw }
end

local function toward(shell, target: Vector3)
	local pos = shell.state.pos
	local flat = Vector3.new(target.X - pos.X, 0, target.Z - pos.Z)
	if flat.Magnitude < 1e-3 then
		return still(shell)
	end
	local dir = flat.Unit
	return { mx = dir.X, mz = dir.Z, jump = false, yaw = math.atan2(-dir.X, -dir.Z) }
end

-- Hunting: chase the nearest standing merc within 40 studs and claw it; finish downed ones.
local function hunt(shell): any
	local agent = shell.owner
	local chest = shell.state.pos + Vector3.new(0, 3, 0)
	local downed = Health.near(chest, Config.Health.AssimilateRange - 1, true)[1]
	if downed and not shell.assimilating then
		ShellCombat.beginAssimilate(agent)
	end
	if shell.assimilating then
		return still(shell)
	end
	local target = Health.near(chest, 40, false)[1]
	if not target then
		return nil
	end
	local offset = target.root.Position - chest
	local flat = Vector3.new(offset.X, 0, offset.Z)
	if flat.Magnitude <= Config.Modules.EnergyClaws.Range - 1.5 then
		ShellCombat.attack(agent)
		local input = still(shell)
		input.yaw = math.atan2(-flat.X, -flat.Z)
		return input
	end
	return toward(shell, target.root.Position)
end

local function botBrain(shell, _dt)
	if botHunts then
		local input = hunt(shell)
		if input then
			return input
		end
	end
	local pos = shell.state.pos
	if botPaused or #botTarget == 0 then
		return still(shell)
	end
	local target = botTarget[botIndex]
	local flat = Vector3.new(target.X - pos.X, 0, target.Z - pos.Z)
	if flat.Magnitude < 1.5 then
		if #botTarget == 1 then
			return still(shell)
		end
		botIndex = botIndex % #botTarget + 1
		target = botTarget[botIndex]
	end
	return toward(shell, target)
end

local function botShell()
	local agent = Chimera.agents()[BOT_KEY]
	return agent and agent.shell
end

local function spawnBot(dockId: string?): (boolean, string)
	local dock = dockId or "DOCK_CORE_SW"
	if not MapData.docks[dock] then
		return false, `no dock {dock}`
	end
	if Docks.state(dock) == "empty" then
		for id in MapData.docks do
			if Docks.state(id) ~= "empty" then
				dock = id
				break
			end
		end
	end
	local agent = Chimera.addBot(BOT_KEY)
	local shell = Chimera.botTakeShell(agent, dock)
	if not shell then
		Chimera.removeBot(BOT_KEY)
		return false, "no stocked dock"
	end
	shell.brain = botBrain
	botIndex = 1
	return true, `test shell {shell.id} took {dock}`
end

local function toggleBot(): string
	if Chimera.agents()[BOT_KEY] then
		Chimera.removeBot(BOT_KEY)
		return "test shell removed"
	end
	local _, message = spawnBot(nil)
	return message
end

local function cycleVisibility(): string
	local changed = {}
	for _, shell in Shells.all() do
		local current = shell.forcedVisibility or "Cloaked"
		local nextState = VISIBILITY_ORDER[current]
		shell.forcedVisibility = if nextState == "Cloaked" then nil else nextState
		table.insert(changed, `{shell.id}={shell.forcedVisibility or "natural"}`)
	end
	return if #changed > 0 then table.concat(changed, ", ") else "no active shells"
end

local function switchRole(player: Player): string
	if player:GetAttribute("Role") == "Chimera" then
		Roles.setRole(player, "Merc")
		return "you are now a merc"
	end
	local current = Roles.chimera()
	if current and current ~= player then
		Roles.setRole(current, "Merc")
	end
	Roles.setRole(player, "Chimera")
	return "you are now the Chimera"
end

-- A dummy merc (100 HP, stands still) to down, assimilate or revive.
local function spawnDummy(position: Vector3): Model?
	local ok, model = pcall(function()
		return Players:CreateHumanoidModelFromDescription(Instance.new("HumanoidDescription"), Enum.HumanoidRigType.R6)
	end)
	if not ok or not model then
		return nil
	end
	dummyCount += 1
	model.Name = `Dummy{dummyCount}`
	for _, d in model:GetDescendants() do
		if d:IsA("BaseScript") then
			d:Destroy()
		end
	end
	model:PivotTo(CFrame.new(position + Vector3.new(0, 3, 0)))
	model.Parent = workspace
	Health.register(model, nil)
	return model
end

-- In front of whoever asked: their shell, their character, or the Core.
local function dummySpot(player: Player): Vector3
	local shell = Shells.ofPlayer(player)
	if shell then
		local forward = Vector3.new(-math.sin(shell.yaw), 0, -math.cos(shell.yaw))
		return shell.state.pos + forward * 5
	end
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if root then
		return root.Position - Vector3.new(0, 3, 0) + root.CFrame.LookVector * 6
	end
	return Vector3.new(20, 0, 20)
end

local function cycleClass(player: Player): string
	if player:GetAttribute("Role") ~= "Merc" then
		return "only mercs have a class"
	end
	local order = Config.Classes.Order
	local index = table.find(order, player:GetAttribute("Class")) or 0
	local class = order[index % #order + 1]
	Roles.setClass(player, class)
	return `class: {class}`
end

local function downMe(player: Player): string
	local body = Health.ofPlayer(player)
	if not body then
		return "no body"
	end
	Health.damage(body.model, 1000, { canDown = true, by = "debug" })
	return "downed"
end

local function vec(v: Vector3): { number }
	return { math.floor(v.X * 100) / 100, math.floor(v.Y * 100) / 100, math.floor(v.Z * 100) / 100 }
end

local function state(): { [string]: any }
	local out = { agents = {}, shells = {}, docks = Docks.all(), perception = {}, players = {}, bodies = {}, doorsLocked = {}, doorsWelded = {}, dark = {}, camerasBroken = {} }
	for key, agent in Chimera.agents() do
		out.agents[key] = {
			mode = agent.mode,
			cameraId = agent.cameraId,
			hopTarget = agent.hopTarget,
			energy = math.floor(agent.energy * 10) / 10,
			hold = agent.hold and { kind = agent.hold.kind, targetId = agent.hold.targetId },
			shell = agent.shell and agent.shell.id,
			takeBlocked = math.max(0, math.floor((agent.takeBlockedUntil - os.clock()) * 10) / 10),
			decoyIn = math.max(0, math.floor((agent.decoyReadyAt - os.clock()) * 10) / 10),
		}
	end
	for id, shell in Shells.all() do
		out.shells[id] = {
			pos = vec(shell.state.pos),
			vel = vec(shell.state.vel),
			grounded = shell.state.grounded,
			visibility = shell.visibility,
			hp = math.floor(shell.hp * 10) / 10,
			speedScale = shell.speedScale,
			assimilating = shell.assimilating ~= nil,
			leaping = shell.leap ~= nil,
			lastSeq = shell.lastSeq,
			queued = #shell.buffer,
			debt = shell.debt,
			owner = if shell.player then shell.player.Name else "bot",
		}
	end
	for model, body in Health.all() do
		out.bodies[model.Name] = { hp = math.floor(body.hp * 10) / 10, downed = body.downed, stim = body.stimAvailable, pos = vec(body.root.Position), bleedIn = if body.downed then math.floor((body.bleedEndsAt - os.clock()) * 10) / 10 else nil }
	end
	for _, player in Players:GetPlayers() do
		local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
		local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
		out.players[player.Name] = {
			role = player:GetAttribute("Role"),
			class = player:GetAttribute("Class"),
			eliminated = player:GetAttribute("Eliminated"),
			ammo = player:GetAttribute("Ammo"),
			battery = player:GetAttribute("Battery"),
			gear = player:GetAttribute("GearCount"),
			pos = root and vec(root.Position),
			walkSpeed = humanoid and humanoid.WalkSpeed,
			rigType = humanoid and humanoid.RigType.Name,
		}
		out.perception[player.Name] = Perception.describe(player)
	end
	for id in MapData.doors do
		if Doors.isLocked(id) then
			table.insert(out.doorsLocked, id)
		end
		if Doors.isWelded(id) then
			table.insert(out.doorsWelded, id)
		end
	end
	for id in MapData.rooms do
		if Lights.isDark(id) then
			table.insert(out.dark, id)
		end
	end
	for id in MapData.cameras do
		if SecurityCameras.isBroken(id) then
			table.insert(out.camerasBroken, id)
		end
	end
	return out
end

local function testCommand(command: string, ...): any
	local args = { ... }
	if command == "state" then
		return state()
	elseif command == "role" then
		local player = Players:FindFirstChild(args[1])
		if not player then
			return { error = "no such player" }
		end
		Roles.setRole(player :: Player, args[2])
		return { ok = true }
	elseif command == "class" then
		local player = Players:FindFirstChild(args[1])
		if player then
			Roles.setClass(player :: Player, args[2])
		end
		return { ok = player ~= nil }
	elseif command == "respawn" then
		local player = Players:FindFirstChild(args[1])
		if player then
			Roles.respawn(player :: Player)
		end
		return { ok = player ~= nil }
	elseif command == "bot" then
		if args[1] == "remove" then
			Chimera.removeBot(BOT_KEY)
			return { ok = true }
		end
		local ok, message = spawnBot(args[1])
		return { ok = ok, message = message }
	elseif command == "botHunt" then
		botHunts = args[1] == true
		return { ok = true }
	elseif command == "botPath" then
		local points = {}
		for _, p in args[1] or {} do
			table.insert(points, Vector3.new(p[1], 0, p[2]))
		end
		botTarget = if #points > 0 then points else DEFAULT_PATROL
		botIndex = 1
		return { ok = true }
	elseif command == "botPause" then
		botPaused = args[1] == true
		return { ok = true }
	elseif command == "botTeleport" then
		local shell = botShell()
		if not shell then
			return { error = "no test shell" }
		end
		shell.state = { pos = Vector3.new(args[1], args[2], args[3]), vel = Vector3.zero, grounded = false }
		return { ok = true }
	elseif command == "botAttack" then
		local agent = Chimera.agents()[BOT_KEY]
		return { result = agent and ShellCombat.attack(agent) }
	elseif command == "visibility" then
		for _, shell in Shells.all() do
			shell.forcedVisibility = if args[1] == "natural" then nil else args[1]
		end
		return { ok = true }
	elseif command == "damageShell" then
		for _, shell in Shells.all() do
			if args[2] == nil or shell.id == args[2] then
				ShellCombat.damage(shell, args[1], {})
			end
		end
		return { ok = true }
	elseif command == "energy" then
		local player = Players:FindFirstChild(args[1])
		local agent = player and Chimera.agentOf(player :: Player)
		if not agent then
			return { error = "not the Chimera" }
		end
		Chimera.setEnergy(agent, args[2])
		return { ok = true }
	elseif command == "overwatch" then
		local player = Players:FindFirstChild(args[1])
		if player then
			Perception.setOverwatch(player :: Player, args[2])
		end
		return { ok = true }
	elseif command == "lockDoor" then
		local ok, err = Doors.lock(args[1])
		return { ok = ok, error = err }
	elseif command == "dummy" then
		local model = spawnDummy(Vector3.new(args[1], args[2], args[3]))
		return { name = model and model.Name }
	elseif command == "damageBody" then
		local model = workspace:FindFirstChild(args[1]) or (Players:FindFirstChild(args[1]) and (Players:FindFirstChild(args[1]) :: Player).Character)
		return { result = model and Health.damage(model, args[2], { canDown = args[3] == true, by = "test" }) }
	elseif command == "fire" then
		-- Fire a player's weapon from their head along a direction (as if their client asked).
		local player = Players:FindFirstChild(args[1]) :: Player?
		local head = player and player.Character and player.Character:FindFirstChild("Head") :: BasePart?
		if not head then
			return { error = "no body" }
		end
		Weapons.fire(player :: Player, head.Position, Vector3.new(args[2], args[3], args[4]), workspace:GetServerTimeNow())
		return { ammo = (player :: Player):GetAttribute("Ammo") }
	elseif command == "resetDowns" then
		Health.resetDownCounts()
		return { ok = true }
	elseif command == "breakCamera" then
		return { ok = SecurityCameras.breakCamera(args[1]) }
	elseif command == "botLeap" then
		local agent = Chimera.agents()[BOT_KEY]
		return { ok = agent ~= nil and ShellCombat.beginLeap(agent, args[1]) }
	elseif command == "damageDock" then
		return { result = Docks.damage(args[1], args[2]) }
	elseif command == "decoy" then
		-- Cast as if from a viewpoint 6 studs behind and 4 above the point, so low ceilings don't block it.
		local ok, err = Decoys.cast(Vector3.new(args[1], args[2] + 4, args[3] + 6), Vector3.new(args[1], args[2], args[3]), 200)
		return { ok = ok, error = err }
	elseif command == "armTrap" then
		-- Armed by a stand-in agent, so a solo merc can walk into it.
		local ok, err = Traps.arm("test", args[1])
		return { ok = ok, error = err }
	elseif command == "staggerShell" then
		for _, shell in Shells.all() do
			ShellCombat.stagger(shell, args[1] or 0.5)
		end
		return { ok = true }
	end
	return { error = `unknown command {command}` }
end

function Debug.init()
	if not RunService:IsStudio() then
		return
	end
	local remote = Net.get("Debug")
	remote.OnServerEvent:Connect(function(player, command, value)
		local message
		if command == "switchRole" then
			message = switchRole(player)
		elseif command == "toggleBot" then
			message = toggleBot()
		elseif command == "botHunt" then
			botHunts = not botHunts
			message = if botHunts then "test shell hunts mercs" else "test shell patrols"
		elseif command == "cycleVisibility" then
			message = cycleVisibility()
		elseif command == "overlay" then
			Perception.setDebug(player, value == true)
			message = if value == true then "perception overlay on" else "perception overlay off"
		elseif command == "lockDoor" and type(value) == "string" then
			local ok, err = Doors.lock(value)
			message = if ok then `{value} locked` else `{value}: {err}`
		elseif command == "spawnDummy" then
			local model = spawnDummy(dummySpot(player))
			message = if model then `{model.Name} spawned` else "dummy failed"
		elseif command == "cycleClass" then
			message = cycleClass(player)
		elseif command == "downMe" then
			message = downMe(player)
		elseif command == "respawn" then
			Health.resetDownCounts()
			Roles.respawn(player)
			message = "respawned"
		end
		if message then
			remote:FireClient(player, "message", message)
		end
	end)

	local hook = Instance.new("BindableFunction")
	hook.Name = "ChimeraTestHook"
	hook.OnInvoke = function(command, ...)
		local ok, result = pcall(testCommand, command, ...)
		if not ok then
			result = { error = tostring(result) }
		end
		return HttpService:JSONEncode(result)
	end
	hook.Parent = ServerScriptService
end

return Debug
