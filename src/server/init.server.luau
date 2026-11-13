-- Server entry point. Rojo syncs src/server to ServerScriptService.Server.
-- ModuleScripts added to src/server become children of this script.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)
local Net = require(ReplicatedStorage.Shared.Net)
local ShellMotor = require(ReplicatedStorage.Shared.ShellMotor)
local version = require(ReplicatedStorage.Shared.Version)

Net.init()

local MapData = require(script.MapData)
local Sight = require(script.Sight)
MapData.init()
Sight.init()

local Chimera = require(script.Chimera)
local Cues = require(script.Cues)
local Debug = require(script.Debug)
local Decoys = require(script.Decoys)
local Detection = require(script.Detection)
local Docks = require(script.Docks)
local Doors = require(script.Doors)
local Flashlights = require(script.Flashlights)
local Gear = require(script.Gear)
local Health = require(script.Health)
local MercMovement = require(script.MercMovement)
local Perception = require(script.Perception)
local Roles = require(script.Roles)
local SecurityCameras = require(script.SecurityCameras)
local ShellCombat = require(script.ShellCombat)
local Shells = require(script.Shells)
local Terminals = require(script.Terminals)
local Traps = require(script.Traps)
local Weapons = require(script.Weapons)

local combat = Net.get("Combat")

Cues.init(function(player)
	if player:GetAttribute("Role") == "Chimera" then
		return Chimera.listenerOf(player)
	end
	local head = player.Character and player.Character:FindFirstChild("Head") :: BasePart?
	return head and head.Position
end)
Docks.init()
Doors.init(Shells.feetPositions)
Terminals.init()
Shells.init()
SecurityCameras.init()
Detection.init()
Flashlights.init(function(player, origin, aim)
	ShellCombat.flashAt(player, origin, aim)
	combat:FireAllClients("flash", player.UserId, origin)
end)
Decoys.init()
Traps.init(Chimera.modulesChanged)
Chimera.init()
Weapons.init()
Gear.init()
Health.init(Roles.eliminated)
Perception.init()
MercMovement.init()
MapData.validate(Sight.cameraSees)
Roles.init()
Debug.init()

-- Merc requests. Each handler validates its own inputs; this only routes and checks the role.
Net.get("MercAction").OnServerEvent:Connect(function(player, kind, a, b, c)
	if player:GetAttribute("Role") ~= "Merc" or type(kind) ~= "string" then
		return
	end
	if kind == "fire" then
		Weapons.fire(player, a, b, c)
	elseif kind == "reload" then
		Weapons.reload(player)
	elseif kind == "gear" then
		Gear.use(player, a, b)
	elseif kind == "aim" then
		Flashlights.setAim(player, a)
	elseif kind == "flashlight" then
		Flashlights.toggle(player, a)
	elseif kind == "flash" then
		Flashlights.flash(player)
	elseif kind == "stim" then
		Health.useStim(player)
	elseif kind == "spectate" then
		Roles.spectate(player, a)
	end
end)

-- Shells can't walk through merc bodies (players' and Studio dummies').
local obstacleKey = ""
local function refreshObstacles()
	local models = {}
	local names = {}
	for model in Health.all() do
		table.insert(models, model)
		table.insert(names, model:GetFullName())
	end
	table.sort(names)
	local key = table.concat(names, "|")
	if key ~= obstacleKey then
		obstacleKey = key
		Shells.setObstacles(models)
	end
end

-- Fixed-rate simulation: shells and the Chimera at Config.Shell.TickRate, perception at its own rate.
local DT = ShellMotor.DT
local PERCEPTION_EVERY = math.max(1, math.round(Config.Shell.TickRate / Config.Perception.TickRate))
local accumulator = 0
local ticks = 0
RunService.Heartbeat:Connect(function(dt)
	accumulator = math.min(accumulator + dt, DT * 8)
	while accumulator >= DT do
		accumulator -= DT
		ticks += 1
		if ticks % 15 == 0 then
			refreshObstacles()
		end
		Chimera.tick(DT)
		ShellCombat.update(DT)
		Shells.tick(DT)
		Health.tick(DT)
		Flashlights.tick(DT)
		Weapons.tick(DT)
		Gear.tick(DT)
		Traps.tick(DT)
		Decoys.tick(DT)
		Detection.tick(DT)
		if ticks % PERCEPTION_EVERY == 0 then
			Perception.tick()
		end
	end
end)

print(`[Chimera] server running {version}`)
