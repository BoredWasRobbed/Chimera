-- Overload (the default Sabotage module, from a camera or a shell): arms a steam pipe or power conduit
-- as a trap, up to 2 at once. A merc who walks up to an armed trap sets it off:
--   Steam: a 4 s cloud that blinds and deals 10 a second.
--   Conduit: 30 damage and a slow.
-- Neither takes a merc below 1 HP (traps can't down anyone). Arming hisses, which mercs nearby hear.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local FacilityMap = require(ReplicatedStorage.Shared.FacilityMap)
local Net = require(ReplicatedStorage.Shared.Net)
local Cues = require(script.Parent.Cues)
local Health = require(script.Parent.Health)

local O = Config.Modules.Overload

type Cloud = { pos: Vector3, endsAt: number, nextTick: number }

local Traps = {}

local traps: { [string]: FacilityMap.TrapInfo } = {}
local armed: { [string]: string } = {} -- trap id -> agent key
local clouds: { Cloud } = {}
local combat: RemoteEvent
local events: RemoteEvent
local onChanged: (string) -> () = function() end

function Traps.get(id: string): FacilityMap.TrapInfo?
	return traps[id]
end

function Traps.armedBy(agentKey: string): number
	local n = 0
	for _, key in armed do
		if key == agentKey then
			n += 1
		end
	end
	return n
end

function Traps.isArmed(id: string): boolean
	return armed[id] ~= nil
end

function Traps.points(id: string): { Vector3 }
	local trap = traps[id]
	return if trap then { trap.target.Position } else {}
end

function Traps.arm(agentKey: string, id: string): (boolean, string?)
	local trap = traps[id]
	if not trap then
		return false, "No such trap"
	end
	if armed[id] then
		return false, "Already armed"
	end
	if Traps.armedBy(agentKey) >= O.MaxTraps then
		return false, `Only {O.MaxTraps} traps at once`
	end
	armed[id] = agentKey
	Cues.emit("TrapArmed", trap.target.Position, 25)
	onChanged(agentKey)
	return true
end

function Traps.disarmAll(agentKey: string)
	for id, key in armed do
		if key == agentKey then
			armed[id] = nil
		end
	end
end

local function slowMerc(body: Health.Body, scale: number, seconds: number)
	body.model:SetAttribute("SlowScale", scale)
	body.model:SetAttribute("SlowUntil", workspace:GetServerTimeNow() + seconds)
end

local function fire(id: string)
	local trap = traps[id]
	local owner = armed[id]
	armed[id] = nil
	if owner then
		onChanged(owner)
	end
	if trap.kind == "Conduit" then
		for _, body in Health.near(trap.floor + Vector3.new(0, 3, 0), O.TriggerRadius + 2, false) do
			Health.damage(body.model, O.ConduitDamage, { canDown = false })
			slowMerc(body, O.ConduitSlowScale, O.ConduitSlowSeconds)
		end
		Cues.emit("ConduitShock", trap.target.Position, 60)
		combat:FireAllClients("spark", trap.target.Position)
	else
		table.insert(clouds, { pos = trap.floor, endsAt = os.clock() + O.SteamSeconds, nextTick = 0 })
		Cues.emit("SteamBurst", trap.target.Position, 60)
		combat:FireAllClients("steam", trap.floor, O.SteamRadius, O.SteamSeconds)
	end
end

function Traps.tick(_dt: number)
	for id in armed do
		local trap = traps[id]
		if #Health.near(trap.floor + Vector3.new(0, 3, 0), O.TriggerRadius, false) > 0 then
			fire(id)
		end
	end
	local now = os.clock()
	for i = #clouds, 1, -1 do
		local cloud = clouds[i]
		if now >= cloud.endsAt then
			table.remove(clouds, i)
		elseif now >= cloud.nextTick then
			cloud.nextTick = now + 0.5
			for _, body in Health.near(cloud.pos + Vector3.new(0, 3, 0), O.SteamRadius, false) do
				Health.damage(body.model, O.SteamDps * 0.5, { canDown = false })
				if body.player then
					events:FireClient(body.player, "blind", O.BlindSeconds)
				end
			end
		end
	end
end

-- changed(agentKey) runs whenever an agent's armed count changes, for its HUD.
function Traps.init(changed: (string) -> ())
	onChanged = changed
	combat = Net.get("Combat")
	events = Net.get("MercEvents")
	traps = FacilityMap.traps()
end

return Traps
