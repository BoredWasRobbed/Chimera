-- Merc detection, computed on the server so clients only ever get a signal strength and a coarse
-- direction, never a position:
--   Motion tracker: a moving shell within 40 studs, never a still one. Strength in quarters, direction
--   in eighths relative to where the merc faces. Held, it draws a blip; holstered, it only pings.
--   Heartbeat: an occupied shell within 10 studs (Scout 15), moving or still. Dormant shells have none.
-- Also delivers System Leap trails to Scouts.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Net = require(ReplicatedStorage.Shared.Net)
local Health = require(script.Parent.Health)
local Shells = require(script.Parent.Shells)

local D = Config.Detection

local Detection = {}

local events: RemoteEvent
local lastTracker: { [Player]: string } = {}
local lastHeartbeat: { [Player]: number } = {}
local trackerAccumulator = 0
local heartbeatAccumulator = 0

local function facingYaw(body): number
	local look = body.root.CFrame.LookVector
	return math.atan2(-look.X, -look.Z)
end

local function updateTrackers()
	for _, player in Players:GetPlayers() do
		local body = Health.ofPlayer(player)
		if not body or body.downed or player:GetAttribute("Role") ~= "Merc" then
			continue
		end
		local origin = body.root.Position
		local best, bestDistance = nil, math.huge
		for _, shell in Shells.all() do
			local v = shell.state.vel
			local moving = Vector3.new(v.X, 0, v.Z).Magnitude >= D.TrackerMinSpeed
			local distance = (shell.state.pos - origin).Magnitude
			if not shell.dead and moving and distance <= D.TrackerRange and distance < bestDistance then
				best, bestDistance = shell, distance
			end
		end
		local strength, sector = 0, 0
		if best then
			strength = math.clamp(math.ceil((1 - bestDistance / D.TrackerRange) * 4), 1, 4)
			local offset = best.state.pos - origin
			local bearing = math.atan2(-offset.X, -offset.Z) - facingYaw(body)
			sector = math.floor(((bearing % (2 * math.pi)) / (2 * math.pi)) * 8 + 0.5) % 8
		end
		local key = `{strength}:{sector}`
		if key ~= lastTracker[player] or strength > 0 then
			lastTracker[player] = key
			events:FireClient(player, "tracker", strength, sector)
		end
	end
end

local function updateHeartbeats()
	for _, player in Players:GetPlayers() do
		local body = Health.ofPlayer(player)
		if not body or player:GetAttribute("Role") ~= "Merc" then
			continue
		end
		local range = if player:GetAttribute("Class") == "Scout" then D.ScoutHeartbeatRange else D.HeartbeatRange
		local nearest = math.huge
		for _, shell in Shells.all() do
			if not shell.dead then
				nearest = math.min(nearest, (shell.state.pos - body.root.Position).Magnitude)
			end
		end
		local intensity = if nearest <= range then math.clamp(math.ceil((1 - nearest / range) * 3), 1, 3) else 0
		if intensity ~= lastHeartbeat[player] or intensity > 0 then
			lastHeartbeat[player] = intensity
			events:FireClient(player, "heartbeat", intensity)
		end
	end
end

-- Scouts near either end of a traversal see its path for 4 s.
function Detection.sendTrail(from: Vector3, to: Vector3)
	local L = Config.Modules.SystemLeap
	for _, player in Players:GetPlayers() do
		local body = Health.ofPlayer(player)
		if body and player:GetAttribute("Class") == "Scout" then
			local p = body.root.Position
			if (p - from).Magnitude <= L.TrailRange or (p - to).Magnitude <= L.TrailRange then
				events:FireClient(player, "trail", from, to, L.TrailSeconds)
			end
		end
	end
end

function Detection.tick(dt: number)
	trackerAccumulator += dt
	heartbeatAccumulator += dt
	if trackerAccumulator >= D.TrackerInterval then
		trackerAccumulator = 0
		updateTrackers()
	end
	if heartbeatAccumulator >= D.HeartbeatInterval then
		heartbeatAccumulator = 0
		updateHeartbeats()
	end
end

function Detection.forget(player: Player)
	lastTracker[player] = nil
	lastHeartbeat[player] = nil
end

function Detection.init()
	events = Net.get("MercEvents")
end

return Detection
