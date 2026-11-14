-- Client entry point. Rojo syncs src/client to StarterPlayer.StarterPlayerScripts.Client.
-- ModuleScripts added to src/client become children of this script.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local StarterGui = game:GetService("StarterGui")

local version = require(ReplicatedStorage.Shared.Version)
local Ambience = require(script.Ambience)
local ChimeraClient = require(script.ChimeraClient)
local CuePlayer = require(script.CuePlayer)
local DebugPanel = require(script.DebugPanel)
local DetectionHud = require(script.DetectionHud)
local DockViews = require(script.DockViews)
local Effects = require(script.Effects)
local FacilityScreens = require(script.FacilityScreens)
local FacilityView = require(script.FacilityView)
local Flashlights = require(script.Flashlights)
local Hud = require(script.Hud)
local MatchHud = require(script.MatchHud)
local MercClient = require(script.MercClient)
local MercCombat = require(script.MercCombat)
local NameTags = require(script.NameTags)
local PingClient = require(script.PingClient)
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
MatchHud.init()
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
PingClient.init()
Spectate.init()
ChimeraClient.init(clientFolder)
-- The map kit's live screens and lights: decoration only, so a fault there never stops the client.
task.spawn(function()
	local ok, err = pcall(FacilityScreens.init)
	if not ok then
		warn(`[Chimera] facility screens failed to start: {err}`)
	end
end)
-- The building's mood (failing lights, lightning, rain on the glass): decoration only too.
task.spawn(function()
	local ok, err = pcall(Ambience.init)
	if not ok then
		warn(`[Chimera] ambience failed to start: {err}`)
	end
end)

local function stopMercBody()
	PingClient.stopWheel()
	MercCombat.stop()
	MercClient.stop()
	NameTags.stop()
end

-- Watching the cameras: Overwatch (an eliminated merc) or a spectator. Restart so the mode is right.
local function watchCameras()
	Spectate.stop()
	Spectate.start()
end

-- Role: Lobby (MatchHud circles the Core), Chimera, Merc (eliminated: Overwatch) or Spectator.
local function applyRole()
	local role = player:GetAttribute("Role")
	if role == "Chimera" then
		stopMercBody()
		Spectate.stop()
		ChimeraClient.start()
	elseif role == "Merc" then
		ChimeraClient.stop()
		if player:GetAttribute("Eliminated") then
			stopMercBody()
			watchCameras()
		else
			Spectate.stop()
			MercClient.start()
			MercCombat.start()
			NameTags.start()
			PingClient.startWheel()
		end
	elseif role == "Spectator" then
		ChimeraClient.stop()
		stopMercBody()
		watchCameras()
	else
		ChimeraClient.stop()
		stopMercBody()
		Spectate.stop()
	end
end
player:GetAttributeChangedSignal("Role"):Connect(applyRole)
player:GetAttributeChangedSignal("Eliminated"):Connect(applyRole)
applyRole()

if RunService:IsStudio() then
	DebugPanel.init(function()
		return {
			role = player:GetAttribute("Role"),
			team = player:GetAttribute("Team"),
			class = player:GetAttribute("Class"),
			eliminated = player:GetAttribute("Eliminated"),
			match = MatchHud.describe(),
			pings = PingClient.describe(),
			chimera = ChimeraClient.describe(),
			merc = MercClient.describe(),
			combat = MercCombat.describe(),
			detection = DetectionHud.describe(),
			spectate = Spectate.describe(),
			shellsSeen = ShellViews.describe(),
			docksKnown = DockViews.all(),
			cuesHeard = CuePlayer.recent(5),
			screens = FacilityScreens.describe(),
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
		ping = function(kind: string)
			PingClient.testPing(kind)
			return PingClient.describe()
		end,
		watch = function(cameraId: string)
			Spectate.testCamera(cameraId)
			return Spectate.describe()
		end,
	})
end

print(`[Chimera] client running {version}`)
