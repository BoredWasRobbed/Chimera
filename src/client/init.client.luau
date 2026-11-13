-- Client entry point. Rojo syncs src/client to StarterPlayer.StarterPlayerScripts.Client.
-- ModuleScripts added to src/client become children of this script.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local StarterGui = game:GetService("StarterGui")

local version = require(ReplicatedStorage.Shared.Version)
local ChimeraClient = require(script.ChimeraClient)
local CuePlayer = require(script.CuePlayer)
local DebugPanel = require(script.DebugPanel)
local DetectionHud = require(script.DetectionHud)
local DockViews = require(script.DockViews)
local Effects = require(script.Effects)
local FacilityView = require(script.FacilityView)
local Flashlights = require(script.Flashlights)
local Hud = require(script.Hud)
local MercClient = require(script.MercClient)
local MercCombat = require(script.MercCombat)
local NameTags = require(script.NameTags)
local ShellControl = require(script.ShellControl)
local ShellViews = require(script.ShellViews)
local Spectate = require(script.Spectate)

local player = Players.LocalPlayer

workspace:WaitForChild("Map")
workspace:WaitForChild("Facility")

-- Health is ours (HP attribute), not the Humanoid's, so the default health bar would only mislead.
pcall(function()
	StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Health, false)
end)

-- Everything this client draws on its own (shells, dormant shells, effects, cue markers) lives here,
-- outside the Map folder, so it never blocks movement or sight checks.
local clientFolder = Instance.new("Folder")
clientFolder.Name = "ClientFX"
clientFolder.Parent = workspace

Hud.init()
CuePlayer.init(clientFolder)
DockViews.init(clientFolder)
Effects.init(clientFolder)
ShellViews.init(clientFolder, function(position)
	Effects.explosion(position, 6)
end)
Flashlights.init(clientFolder)
DetectionHud.init()
MercClient.init()
MercCombat.init(clientFolder)
Spectate.init()
ChimeraClient.init(clientFolder)

local function stopMerc()
	MercCombat.stop()
	MercClient.stop()
	NameTags.stop()
	Spectate.stop()
end

local function applyRole()
	local role = player:GetAttribute("Role")
	if role == "Chimera" then
		stopMerc()
		ChimeraClient.start()
	elseif role == "Merc" then
		ChimeraClient.stop()
		if player:GetAttribute("Eliminated") then
			MercCombat.stop()
			MercClient.stop()
			NameTags.stop()
			Spectate.start()
		else
			Spectate.stop()
			MercClient.start()
			MercCombat.start()
			NameTags.start()
		end
	end
end
player:GetAttributeChangedSignal("Role"):Connect(applyRole)
player:GetAttributeChangedSignal("Eliminated"):Connect(applyRole)
applyRole()

if RunService:IsStudio() then
	DebugPanel.init(function()
		return {
			role = player:GetAttribute("Role"),
			class = player:GetAttribute("Class"),
			eliminated = player:GetAttribute("Eliminated"),
			chimera = ChimeraClient.describe(),
			merc = MercClient.describe(),
			combat = MercCombat.describe(),
			detection = DetectionHud.describe(),
			spectate = Spectate.describe(),
			shellsSeen = ShellViews.describe(),
			docksKnown = DockViews.all(),
			cuesHeard = CuePlayer.recent(5),
		}
	end, {
		key = function(keyName: string, down: boolean)
			ChimeraClient.testKey(keyName, down)
			return ChimeraClient.describe()
		end,
		hop = function(id: string)
			ChimeraClient.testHop(id)
			return { ok = true }
		end,
		lookAt = function(x: number?, y: number?, z: number?)
			FacilityView.lookAt(if x then Vector3.new(x, y, z) else nil)
			return { ok = true }
		end,
		drive = function(yaw: number?, forward: number?, right: number?, jump: boolean?)
			ShellControl.setTestInput(yaw, forward, right, jump)
			return { ok = true }
		end,
		shellLookAt = function(x: number, y: number, z: number)
			ShellControl.testLookAt(Vector3.new(x, y, z))
			return { ok = true }
		end,
		mercLookAt = function(x: number, y: number, z: number)
			MercCombat.testLookAt(Vector3.new(x, y, z))
			return { ok = true }
		end,
		mercFireAt = function(x: number, y: number, z: number)
			MercCombat.testFireAt(Vector3.new(x, y, z))
			return MercCombat.describe()
		end,
		tracker = function(held: boolean)
			DetectionHud.setHeld(held)
			return DetectionHud.describe()
		end,
	})
end

print(`[Chimera] client running {version}`)
