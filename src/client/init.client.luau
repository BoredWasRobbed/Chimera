-- Client entry point. Rojo syncs src/client to StarterPlayer.StarterPlayerScripts.Client.
-- ModuleScripts added to src/client become children of this script.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local version = require(ReplicatedStorage.Shared.Version)
local ChimeraClient = require(script.ChimeraClient)
local CuePlayer = require(script.CuePlayer)
local DebugPanel = require(script.DebugPanel)
local DockViews = require(script.DockViews)
local FacilityView = require(script.FacilityView)
local Hud = require(script.Hud)
local MercClient = require(script.MercClient)
local ShellControl = require(script.ShellControl)
local ShellViews = require(script.ShellViews)

local player = Players.LocalPlayer

workspace:WaitForChild("Map")
workspace:WaitForChild("Facility")

-- Everything this client draws on its own (shells, dormant shells, cue markers) lives here, outside
-- the Map folder, so it never blocks movement or sight checks.
local clientFolder = Instance.new("Folder")
clientFolder.Name = "ClientFX"
clientFolder.Parent = workspace

Hud.init()
CuePlayer.init(clientFolder)
DockViews.init(clientFolder)
ShellViews.init(clientFolder)
MercClient.init()
ChimeraClient.init(clientFolder)

local function applyRole()
	local role = player:GetAttribute("Role")
	if role == "Chimera" then
		MercClient.stop()
		ChimeraClient.start()
	elseif role == "Merc" then
		ChimeraClient.stop()
		MercClient.start()
	end
end
player:GetAttributeChangedSignal("Role"):Connect(applyRole)
applyRole()

if RunService:IsStudio() then
	DebugPanel.init(function()
		return {
			role = player:GetAttribute("Role"),
			chimera = ChimeraClient.describe(),
			merc = MercClient.describe(),
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
	})
end

print(`[Chimera] client running {version}`)
