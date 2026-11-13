-- Who plays what. Match decides; this module applies it. A player's Role attribute is one of:
--   Lobby      between rounds, or picked for the next one (the Team attribute says which side)
--   Chimera    no character: it lives in the cameras
--   Merc       a body with a class loadout (Assault 2, Technician 2, Medic 1, Scout 1)
--   Spectator  joined mid-match or was sent to the lobby for idling: watches the cameras until the next round
-- An eliminated merc (assimilated or bled out) keeps the Merc role with Eliminated set: their body is
-- removed and they play Overwatch through the cameras.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Chimera = require(script.Parent.Chimera)
local Detection = require(script.Parent.Detection)
local Flashlights = require(script.Parent.Flashlights)
local Gear = require(script.Parent.Gear)
local Health = require(script.Parent.Health)
local MercMovement = require(script.Parent.MercMovement)
local Perception = require(script.Parent.Perception)
local Terminals = require(script.Parent.Terminals)
local Weapons = require(script.Parent.Weapons)

export type Role = "Lobby" | "Chimera" | "Merc" | "Spectator"

local Roles = {}

local chimeraPlayer: Player? = nil

function Roles.chimera(): Player?
	return chimeraPlayer
end

-- How many mercs (playing, or picked as mercs for the next round) have each class.
function Roles.classCounts(exclude: Player?): { [string]: number }
	local counts = {}
	for _, other in Players:GetPlayers() do
		local isMerc = other:GetAttribute("Role") == "Merc" or other:GetAttribute("Team") == "Merc"
		local class = other ~= exclude and isMerc and other:GetAttribute("Class")
		if class then
			counts[class] = (counts[class] or 0) + 1
		end
	end
	return counts
end

-- The first slice class with room under its cap.
function Roles.pickClass(player: Player): string
	local counts = Roles.classCounts(player)
	for _, class in Config.Classes.Order do
		if (counts[class] or 0) < Config.Classes[class].Cap then
			return class
		end
	end
	return Config.Classes.Order[1]
end

local function setupCharacter(player: Player, character: Model)
	local humanoid = character:WaitForChild("Humanoid", 10) :: Humanoid?
	if not humanoid or player:GetAttribute("Role") ~= "Merc" then
		return
	end
	humanoid.WalkSpeed = Config.Merc.WalkSpeed
	character:WaitForChild("HumanoidRootPart", 10)
	Health.register(character, player)
	local class = player:GetAttribute("Class") or "Assault"
	Weapons.equip(player, class)
	Gear.equip(player, class)
	Flashlights.reset(player)
	MercMovement.resetStamina(player)
	humanoid.Died:Connect(function()
		task.delay(Config.Merc.RespawnSeconds, function()
			if player.Parent and player:GetAttribute("Role") == "Merc" and not player:GetAttribute("Eliminated") and player.Character == character then
				player:LoadCharacter()
			end
		end)
	end)
end

local function clearMerc(player: Player)
	Terminals.release(player)
	MercMovement.removeMerc(player)
	Flashlights.removeMerc(player)
	Weapons.remove(player)
	Gear.remove(player)
	Detection.forget(player)
end

-- Undo whatever the player's current role set up. Their body goes without scoring anything.
local function clearRole(player: Player)
	local current = player:GetAttribute("Role")
	if current == "Chimera" then
		Chimera.removePlayer(player)
	elseif current == "Merc" then
		clearMerc(player)
	end
	if chimeraPlayer == player then
		chimeraPlayer = nil
	end
	Perception.remove(player)
	player:SetAttribute("Eliminated", nil)
	if player.Character then
		player.Character:Destroy()
		player.Character = nil
	end
end

-- Set the role without bringing anyone into the facility yet.
function Roles.assign(player: Player, role: Role, class: string?)
	clearRole(player)
	player:SetAttribute("Role", role)
	if role == "Chimera" then
		chimeraPlayer = player
		player:SetAttribute("Class", nil)
	elseif role == "Merc" then
		player:SetAttribute("Class", if class and Config.Classes[class] then class else Roles.pickClass(player))
	else
		player:SetAttribute("Class", nil)
	end
	if role == "Spectator" then
		-- Spectators watch the cameras: perception treats them like Overwatch.
		Perception.addMerc(player)
	end
end

-- Bring an assigned player into the facility: the Chimera boots in the network, a merc gets a body at
-- the Insertion lift.
function Roles.deploy(player: Player)
	local role = player:GetAttribute("Role")
	if role == "Chimera" then
		Perception.addChimera(player)
		Chimera.addPlayer(player)
	elseif role == "Merc" then
		MercMovement.addMerc(player)
		Flashlights.addMerc(player)
		Perception.addMerc(player)
		task.spawn(function()
			player:LoadCharacter()
		end)
	end
end

function Roles.setRole(player: Player, role: Role, class: string?)
	Roles.assign(player, role, class)
	Roles.deploy(player)
end

-- Studio: switch a merc's class and give them a fresh body with its loadout.
function Roles.setClass(player: Player, class: string)
	if player:GetAttribute("Role") ~= "Merc" or not Config.Classes[class] then
		return
	end
	player:SetAttribute("Class", class)
	Roles.respawn(player)
end

-- Studio: bring an eliminated (or any) merc back with a fresh body.
function Roles.respawn(player: Player)
	if player:GetAttribute("Role") ~= "Merc" then
		return
	end
	player:SetAttribute("Eliminated", nil)
	Perception.setOverwatch(player, nil)
	player:LoadCharacter()
end

-- Health calls this when a merc is assimilated or bleeds out.
function Roles.eliminated(body: Health.Body, _reason: string)
	local player = body.player
	if not player then
		task.delay(1.5, function()
			body.model:Destroy()
		end)
		return
	end
	Terminals.release(player)
	player:SetAttribute("Eliminated", true)
	task.delay(1.5, function()
		if player.Character == body.model then
			body.model:Destroy()
			player.Character = nil
		end
	end)
end

-- An eliminated merc (Overwatch) or a spectator picks the camera they watch; perception follows it.
function Roles.spectate(player: Player, cameraId: any)
	if type(cameraId) ~= "string" then
		return
	end
	local role = player:GetAttribute("Role")
	if (role == "Merc" and player:GetAttribute("Eliminated")) or role == "Spectator" then
		Perception.setOverwatch(player, cameraId)
	end
end

function Roles.init()
	Players.CharacterAutoLoads = false
	local function hook(player: Player)
		player.CharacterAdded:Connect(function(character)
			setupCharacter(player, character)
		end)
	end
	Players.PlayerAdded:Connect(hook)
	for _, player in Players:GetPlayers() do
		hook(player)
	end
	Players.PlayerRemoving:Connect(function(player)
		if player:GetAttribute("Role") == "Chimera" then
			Chimera.removePlayer(player)
		end
		if chimeraPlayer == player then
			chimeraPlayer = nil
		end
		clearMerc(player)
		Perception.remove(player)
	end)
end

return Roles
