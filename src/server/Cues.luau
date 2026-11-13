-- Tells: the sounds the Chimera's actions make. A sound played on the server reaches every client, which
-- would tell an ESP script where the Chimera is, so each cue goes only to players within earshot.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Net = require(ReplicatedStorage.Shared.Net)

local Cues = {}

local remote: RemoteEvent
local listenerOf: (Player) -> Vector3? = function()
	return nil
end

-- getListener returns where a player hears from: a merc's head, or the Chimera's camera or shell.
function Cues.init(getListener: (Player) -> Vector3?)
	remote = Net.get("Cue")
	listenerOf = getListener
end

function Cues.emit(name: string, position: Vector3, range: number)
	for _, player in Players:GetPlayers() do
		local at = listenerOf(player)
		if at and (at - position).Magnitude <= range then
			remote:FireClient(player, name, position)
		end
	end
end

return Cues
