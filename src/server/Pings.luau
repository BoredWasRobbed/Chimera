-- Pings carry everything critical, because many players can't or won't use voice.
--   Mercs: tap the ping button to mark where you aim; hold for the wheel (Chimera here, Going here,
--   Terminal, Need revive, Low battery, Watch this door). Every ping shows the sender's name and plays a
--   radio voice line (the voice flag). Downed mercs can ping too.
--   Overwatch (eliminated mercs, through a camera): Ping marks a spot for living mercs (3 charges, one
--   back every 20 s); Tag outlines an Exposed or Revealed shell on their camera for 3 s (30 s cooldown).
--   Corrupt Data (a later Sabotage module) sends one fake ping in a teammate's name with no voice line,
--   which is the tell: Pings.fake.
-- Pings reach every merc in the match, living or on Overwatch, and never the Chimera.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Hitbox = require(ReplicatedStorage.Shared.Hitbox)
local Net = require(ReplicatedStorage.Shared.Net)
local Health = require(script.Parent.Health)
local MapData = require(script.Parent.MapData)
local MatchState = require(script.Parent.MatchState)
local Perception = require(script.Parent.Perception)
local ShellCombat = require(script.Parent.ShellCombat)
local Shells = require(script.Parent.Shells)

local Pings = {}

local P = Config.Pings

local feed: RemoteEvent
local recent: { [Player]: { number } } = {}
local charges: { [Player]: number } = {}
local rechargeAt: { [Player]: number } = {}
local tagReadyAt: { [Player]: number } = {}
local tickAccumulator = 0

local function serverTime(clockTime: number): number
	return workspace:GetServerTimeNow() + (clockTime - os.clock())
end

local function live(): boolean
	local phase = MatchState.phase
	return phase == "Deployment" or phase == "Race" or phase == "Finale"
end

local function broadcast(ping: { [string]: any })
	ping.t = workspace:GetServerTimeNow()
	for _, player in Players:GetPlayers() do
		if player:GetAttribute("Role") == "Merc" then
			feed:FireClient(player, "ping", ping)
		end
	end
end

local function rateOk(player: Player): boolean
	local now = os.clock()
	local list = recent[player] or {}
	recent[player] = list
	while #list > 0 and now - list[1] > P.RateWindow do
		table.remove(list, 1)
	end
	if #list >= P.RateCount then
		return false
	end
	table.insert(list, now)
	return true
end

-- A living (or downed) merc's ping. kind: "Ping" (a tap) or one of the wheel's entries.
function Pings.merc(player: Player, kind: any, point: any)
	if player:GetAttribute("Role") ~= "Merc" or player:GetAttribute("Eliminated") or not live() then
		return
	end
	if type(kind) ~= "string" or (kind ~= "Ping" and not table.find(P.Wheel, kind)) then
		return
	end
	local body = Health.ofPlayer(player)
	if not body or not rateOk(player) then
		return
	end
	local at: Vector3
	if P.OnSelf[kind] then
		at = body.root.Position
	elseif Hitbox.finiteVector(point) and (point - body.root.Position).Magnitude <= P.MaxDistance then
		at = point
	else
		return
	end
	broadcast({ kind = kind, x = at.X, y = at.Y, z = at.Z, from = player.Name, userId = player.UserId, voice = true })
end

-- Corrupt Data: a fake ping in a teammate's name. It has no voice line, which is the tell.
function Pings.fake(kind: string, point: Vector3, asPlayer: Player?)
	broadcast({ kind = kind, x = point.X, y = point.Y, z = point.Z, from = if asPlayer then asPlayer.Name else "Merc", userId = if asPlayer then asPlayer.UserId else 0, voice = false })
end

local function isOverwatch(player: Player): boolean
	return player:GetAttribute("Role") == "Merc" and player:GetAttribute("Eliminated") == true
end

local function publishOverwatch(player: Player)
	player:SetAttribute("PingCharges", charges[player])
	player:SetAttribute("PingRechargeAt", if rechargeAt[player] then serverTime(rechargeAt[player] :: number) else 0)
	player:SetAttribute("TagReadyAt", if tagReadyAt[player] then serverTime(tagReadyAt[player] :: number) else 0)
end

local function ensureCharges(player: Player)
	if charges[player] == nil then
		charges[player] = P.OverwatchCharges
		rechargeAt[player] = nil
		publishOverwatch(player)
	end
end

-- Overwatch Ping: mark a spot (seen from the camera they watch) for the living mercs.
function Pings.overwatchPing(player: Player, point: any)
	if not isOverwatch(player) or not live() or not Hitbox.finiteVector(point) then
		return
	end
	local cameraId = Perception.overwatchCamera(player)
	local cam = cameraId and MapData.cameras[cameraId]
	if not cam or (point - cam.origin).Magnitude > Config.Interface.CameraRange then
		return
	end
	ensureCharges(player)
	if charges[player] <= 0 then
		feed:FireClient(player, "notice", "No ping charges left")
		return
	end
	charges[player] -= 1
	if not rechargeAt[player] then
		rechargeAt[player] = os.clock() + P.OverwatchRecharge
	end
	publishOverwatch(player)
	broadcast({ kind = "Overwatch", x = point.X, y = point.Y, z = point.Z, from = player.Name, userId = player.UserId, voice = true })
end

-- Overwatch Tag: outline the Chimera for the living mercs, if it's Exposed or Revealed on this camera.
function Pings.tag(player: Player)
	if not isOverwatch(player) or not live() then
		return
	end
	local now = os.clock()
	if (tagReadyAt[player] or 0) > now then
		feed:FireClient(player, "notice", string.format("Tag ready in %d s", math.ceil(tagReadyAt[player] - now)))
		return
	end
	local cameraId = Perception.overwatchCamera(player)
	if not cameraId then
		return
	end
	local tagged = false
	for _, shell in Shells.all() do
		if not shell.dead and (shell.visibility == "Exposed" or shell.visibility == "Revealed") and Perception.cameraSeesShell(cameraId, shell) then
			ShellCombat.tag(shell, P.TagSeconds)
			tagged = true
		end
	end
	if not tagged then
		feed:FireClient(player, "notice", "Nothing to tag: the Chimera must be Exposed or Revealed on your camera")
		return
	end
	tagReadyAt[player] = now + P.TagCooldown
	publishOverwatch(player)
	for _, other in Players:GetPlayers() do
		if other:GetAttribute("Role") == "Merc" then
			feed:FireClient(other, "notice", `Overwatch: {player.Name} tagged the Chimera`)
		end
	end
end

-- Overwatch ping charges come back one every 20 s.
function Pings.tick(dt: number)
	tickAccumulator += dt
	if tickAccumulator < 0.25 then
		return
	end
	tickAccumulator = 0
	local now = os.clock()
	for _, player in Players:GetPlayers() do
		if isOverwatch(player) then
			ensureCharges(player)
			local at = rechargeAt[player]
			if at and now >= at then
				charges[player] = math.min(P.OverwatchCharges, charges[player] + 1)
				rechargeAt[player] = if charges[player] < P.OverwatchCharges then now + P.OverwatchRecharge else nil
				publishOverwatch(player)
			end
		end
	end
end

-- A new round: full charges and no cooldowns.
function Pings.reset()
	for _, player in Players:GetPlayers() do
		player:SetAttribute("PingCharges", nil)
		player:SetAttribute("PingRechargeAt", nil)
		player:SetAttribute("TagReadyAt", nil)
	end
	table.clear(charges)
	table.clear(rechargeAt)
	table.clear(tagReadyAt)
	table.clear(recent)
end

function Pings.init()
	feed = Net.get("MatchFeed")
	Players.PlayerRemoving:Connect(function(player)
		recent[player] = nil
		charges[player] = nil
		rechargeAt[player] = nil
		tagReadyAt[player] = nil
	end)
end

return Pings
