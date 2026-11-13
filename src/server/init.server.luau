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
local Docks = require(script.Docks)
local Doors = require(script.Doors)
local MercMovement = require(script.MercMovement)
local Perception = require(script.Perception)
local Roles = require(script.Roles)
local Shells = require(script.Shells)
local Terminals = require(script.Terminals)

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
Chimera.init()
Perception.init()
MercMovement.init()
MapData.validate(Sight.cameraSees)
Roles.init()
Debug.init()

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
		Chimera.tick(DT)
		Shells.tick(DT)
		if ticks % PERCEPTION_EVERY == 0 then
			Perception.tick()
		end
	end
end)

print(`[Chimera] server running {version}`)
