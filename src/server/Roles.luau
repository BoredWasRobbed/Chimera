-- Who plays what. Until match flow arrives (milestone 3) the first player in the server is the Chimera
-- and everyone else is a merc. The Chimera has no character: it lives in the cameras. Mercs get the
-- first slice class with room under its cap (Assault 2, Technician 2, Medic 1, Scout 1). An eliminated
-- merc (assimilated or bled out) loses their body and watches through the cameras; full Overwatch is
-- milestone 3.
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
local Weapons = require(script.Parent.Weapons)

local Roles = {}

local chimeraPlayer: Player? = nil

function Roles.chimera(): Player?
	return chimeraPlayer
end

local function pickClass(player: Player): string
	local counts = {}
	for _, other in Players:GetPlayers() do
		local class = other ~= player and other:GetAttribute("Role") == "Merc" and other:GetAttribute("Class")
		if class then
			counts[class] = (counts[class] or 0) + 1
		end
	end
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
	MercMovement.removeMerc(player)
	Flashlights.removeMerc(player)
	Weapons.remove(player)
	Gear.remove(player)
	Detection.forget(player)
end

function Roles.setRole(player: Player, role: "Chimera" | "Merc")
	local current = player:GetAttribute("Role")
	if current == role then
		return
	end
	if current == "Chimera" then
		Chimera.removePlayer(player)
		if chimeraPlayer == player then
			chimeraPlayer = nil
		end
	elseif current == "Merc" then
		clearMerc(player)
	end
	Perception.remove(player)
	player:SetAttribute("Eliminated", nil)

	player:SetAttribute("Role", role)
	if role == "Chimera" then
		chimeraPlayer = player
		player:SetAttribute("Class", nil)
		if player.Character then
			player.Character:Destroy()
			player.Character = nil
		end
		Perception.addChimera(player)
		Chimera.addPlayer(player)
	else
		player:SetAttribute("Class", pickClass(player))
		MercMovement.addMerc(player)
		Flashlights.addMerc(player)
		Perception.addMerc(player)
		player:LoadCharacter()
	end
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
	player:SetAttribute("Eliminated", true)
	task.delay(1.5, function()
		if player.Character == body.model then
			body.model:Destroy()
			player.Character = nil
		end
	end)
end

-- An eliminated merc picks the camera they watch; perception follows that camera.
function Roles.spectate(player: Player, cameraId: any)
	if player:GetAttribute("Eliminated") and type(cameraId) == "string" then
		Perception.setOverwatch(player, cameraId)
	end
end

local function onPlayerAdded(player: Player)
	player.CharacterAdded:Connect(function(character)
		setupCharacter(player, character)
	end)
	Roles.setRole(player, if chimeraPlayer == nil then "Chimera" else "Merc")
end

function Roles.init()
	Players.CharacterAutoLoads = false
	Players.PlayerAdded:Connect(onPlayerAdded)
	Players.PlayerRemoving:Connect(function(player)
		if player:GetAttribute("Role") == "Chimera" then
			Chimera.removePlayer(player)
			if chimeraPlayer == player then
				chimeraPlayer = nil
			end
		end
		clearMerc(player)
		Perception.remove(player)
	end)
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayerAdded, player)
	end
end

return Roles
