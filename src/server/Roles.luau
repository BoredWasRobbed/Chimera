-- Who plays what. Until match flow arrives (milestone 3) the first player in the server is the Chimera
-- and everyone else is a merc. The Chimera has no character: it lives in the cameras.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Chimera = require(script.Parent.Chimera)
local MercMovement = require(script.Parent.MercMovement)
local Perception = require(script.Parent.Perception)

local Roles = {}

local chimeraPlayer: Player? = nil

function Roles.chimera(): Player?
	return chimeraPlayer
end

local function setupCharacter(player: Player, character: Model)
	local humanoid = character:WaitForChild("Humanoid", 10) :: Humanoid?
	if not humanoid then
		return
	end
	humanoid.WalkSpeed = Config.Merc.WalkSpeed
	MercMovement.resetStamina(player)
	humanoid.Died:Connect(function()
		task.delay(Config.Merc.RespawnSeconds, function()
			if player.Parent and player:GetAttribute("Role") == "Merc" and player.Character == character then
				player:LoadCharacter()
			end
		end)
	end)
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
		MercMovement.removeMerc(player)
	end
	Perception.remove(player)

	player:SetAttribute("Role", role)
	if role == "Chimera" then
		chimeraPlayer = player
		if player.Character then
			player.Character:Destroy()
			player.Character = nil
		end
		Perception.addChimera(player)
		Chimera.addPlayer(player)
	else
		MercMovement.addMerc(player)
		Perception.addMerc(player)
		player:LoadCharacter()
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
		MercMovement.removeMerc(player)
		Perception.remove(player)
	end)
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayerAdded, player)
	end
end

return Roles
