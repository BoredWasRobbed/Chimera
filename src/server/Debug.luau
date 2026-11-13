-- Studio-only test tools. Nothing here runs in a live server.
--   Debug remote (the in-game DEV panel): switch role, spawn a patrolling test shell, cycle its
--   visibility state, show the perception overlay, lock a door as if the Chimera had.
--   ServerScriptService.ChimeraTestHook (BindableFunction): JSON state and commands for automated checks.
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")

local Net = require(ReplicatedStorage.Shared.Net)
local Chimera = require(script.Parent.Chimera)
local Docks = require(script.Parent.Docks)
local Doors = require(script.Parent.Doors)
local Lights = require(script.Parent.Lights)
local MapData = require(script.Parent.MapData)
local Perception = require(script.Parent.Perception)
local Roles = require(script.Parent.Roles)
local Shells = require(script.Parent.Shells)

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

local function botBrain(shell, _dt)
	local pos = shell.state.pos
	if botPaused or #botTarget == 0 then
		return { mx = 0, mz = 0, jump = false, yaw = shell.yaw }
	end
	local target = botTarget[botIndex]
	local flat = Vector3.new(target.X - pos.X, 0, target.Z - pos.Z)
	if flat.Magnitude < 1.5 then
		if #botTarget == 1 then
			return { mx = 0, mz = 0, jump = false, yaw = shell.yaw }
		end
		botIndex = botIndex % #botTarget + 1
		target = botTarget[botIndex]
		flat = Vector3.new(target.X - pos.X, 0, target.Z - pos.Z)
	end
	if flat.Magnitude < 1e-3 then
		return { mx = 0, mz = 0, jump = false, yaw = shell.yaw }
	end
	local dir = flat.Unit
	return { mx = dir.X, mz = dir.Z, jump = false, yaw = math.atan2(-dir.X, -dir.Z) }
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
		shell.visibility = VISIBILITY_ORDER[shell.visibility] or "Cloaked"
		table.insert(changed, `{shell.id}={shell.visibility}`)
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

local function vec(v: Vector3): { number }
	return { math.floor(v.X * 100) / 100, math.floor(v.Y * 100) / 100, math.floor(v.Z * 100) / 100 }
end

local function state(): { [string]: any }
	local out = { agents = {}, shells = {}, docks = Docks.all(), perception = {}, players = {}, doorsLocked = {}, dark = {} }
	for key, agent in Chimera.agents() do
		out.agents[key] = {
			mode = agent.mode,
			cameraId = agent.cameraId,
			hopTarget = agent.hopTarget,
			energy = math.floor(agent.energy * 10) / 10,
			hold = agent.hold and { kind = agent.hold.kind, targetId = agent.hold.targetId },
			shell = agent.shell and agent.shell.id,
		}
	end
	for id, shell in Shells.all() do
		out.shells[id] = {
			pos = vec(shell.state.pos),
			vel = vec(shell.state.vel),
			grounded = shell.state.grounded,
			visibility = shell.visibility,
			lastSeq = shell.lastSeq,
			queued = #shell.buffer,
			debt = shell.debt,
			owner = if shell.player then shell.player.Name else "bot",
		}
	end
	for _, player in Players:GetPlayers() do
		local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
		local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
		out.players[player.Name] = {
			role = player:GetAttribute("Role"),
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
	end
	for id in MapData.rooms do
		if Lights.isDark(id) then
			table.insert(out.dark, id)
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
	elseif command == "bot" then
		if args[1] == "remove" then
			Chimera.removeBot(BOT_KEY)
			return { ok = true }
		end
		local ok, message = spawnBot(args[1])
		return { ok = ok, message = message }
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
	elseif command == "visibility" then
		for _, shell in Shells.all() do
			shell.visibility = args[1]
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
	elseif command == "lockDoor" then
		local ok, err = Doors.lock(args[1])
		return { ok = ok, error = err }
	elseif command == "overwatch" then
		local player = Players:FindFirstChild(args[1])
		if player then
			Perception.setOverwatch(player :: Player, args[2])
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
		elseif command == "cycleVisibility" then
			message = cycleVisibility()
		elseif command == "overlay" then
			Perception.setDebug(player, value == true)
			message = if value == true then "perception overlay on" else "perception overlay off"
		elseif command == "lockDoor" and type(value) == "string" then
			local ok, err = Doors.lock(value)
			message = if ok then `{value} locked` else `{value}: {err}`
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
