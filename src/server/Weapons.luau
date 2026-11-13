-- Merc weapons, owned by the server: fire rate, ammo, reloads, spread and every hit. A client asks to
-- fire with where it aimed from and the moment it saw; the server rate-limits the request, rolls the
-- spread itself, rewinds shells to that moment (at most LagCompensationMax) and decides what was hit.
-- Mercs can't hurt each other. Shots can hit the shell, dormant shells, light fixtures, cameras and
-- decoys.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Hitbox = require(ReplicatedStorage.Shared.Hitbox)
local Net = require(ReplicatedStorage.Shared.Net)
local Decoys = require(script.Parent.Decoys)
local Docks = require(script.Parent.Docks)
local Health = require(script.Parent.Health)
local Lights = require(script.Parent.Lights)
local MapData = require(script.Parent.MapData)
local SecurityCameras = require(script.Parent.SecurityCameras)
local ShellCombat = require(script.Parent.ShellCombat)
local Shells = require(script.Parent.Shells)

local C = Config.Combat

export type Hit = {
	kind: string, -- "none", "map", "shell", "dormant", "light", "camera", "decoy"
	distance: number,
	point: Vector3,
	instance: Instance?,
	shell: Shells.Shell?,
	dockId: string?,
}

type Loadout = {
	class: string,
	weaponId: string,
	weapon: { [string]: any },
	ammo: number,
	reloadEndsAt: number,
	lastShotAt: number,
	recent: { number },
	rng: Random,
}

local Weapons = {}

local loadouts: { [Player]: Loadout } = {}
local traceParams = RaycastParams.new()
traceParams.FilterType = Enum.RaycastFilterType.Include
traceParams.IgnoreWater = true
local combat: RemoteEvent
local events: RemoteEvent
local facility: Folder

local function serverTime(clockTime: number): number
	return workspace:GetServerTimeNow() + (clockTime - os.clock())
end

local function publish(player: Player, l: Loadout)
	player:SetAttribute("Weapon", l.weaponId)
	player:SetAttribute("Ammo", l.ammo)
	player:SetAttribute("Magazine", l.weapon.Magazine)
	player:SetAttribute("ReloadEndsAt", if l.reloadEndsAt > os.clock() then serverTime(l.reloadEndsAt) else 0)
end

function Weapons.equip(player: Player, class: string)
	local classInfo = Config.Classes[class] or Config.Classes.Assault
	local weapon = Config.Weapons[classInfo.Weapon]
	local l: Loadout = {
		class = class,
		weaponId = classInfo.Weapon,
		weapon = weapon,
		ammo = weapon.Magazine,
		reloadEndsAt = 0,
		lastShotAt = 0,
		recent = {},
		rng = Random.new(),
	}
	loadouts[player] = l
	publish(player, l)
end

function Weapons.remove(player: Player)
	loadouts[player] = nil
end

local function classify(result: RaycastResult): Hit
	local instance = result.Instance
	local hit: Hit = { kind = "map", distance = result.Distance, point = result.Position, instance = instance }
	if instance:IsDescendantOf(facility) then
		if instance.Name == "Fixture" then
			hit.kind = "light"
		elseif SecurityCameras.idOf(instance) then
			hit.kind = "camera"
		end
	elseif Decoys.isDecoy(instance:FindFirstAncestorOfClass("Model")) then
		hit.kind = "decoy"
		hit.instance = instance:FindFirstAncestorOfClass("Model")
	end
	return hit
end

-- The first thing a ray hits. Shells are tested where they were at server time `t`.
function Weapons.trace(origin: Vector3, direction: Vector3, range: number, t: number): Hit
	local best: Hit = { kind = "none", distance = range, point = origin + direction * range }
	local result = workspace:Raycast(origin, direction * range, traceParams)
	if result then
		best = classify(result)
	end
	for _, shell in Shells.all() do
		if not shell.dead then
			local lo, hi = Hitbox.bodyBox(Shells.positionAt(shell, t), C.ShellHitboxWidth, C.ShellHitboxHeight)
			local d = Hitbox.rayBox(origin, direction, lo, hi)
			if d and d < best.distance then
				best = { kind = "shell", distance = d, point = origin + direction * d, shell = shell }
			end
		end
	end
	for id, dock in MapData.docks do
		local state = Docks.state(id)
		if state == "stocked" or state == "booting" then
			local lo, hi = Hitbox.bodyBox(dock.spawn.Position, 2.4, 5.2)
			local d = Hitbox.rayBox(origin, direction, lo, hi)
			if d and d < best.distance then
				best = { kind = "dormant", distance = d, point = origin + direction * d, dockId = id }
			end
		end
	end
	return best
end

local function apply(player: Player, l: Loadout, hit: Hit)
	local w = l.weapon
	local damage = w.Damage
	if w.FalloffStart and hit.distance > w.FalloffStart then
		local alpha = math.clamp((hit.distance - w.FalloffStart) / (w.Range - w.FalloffStart), 0, 1)
		damage *= 1 + (w.FalloffMin - 1) * alpha
	end
	if hit.kind == "shell" and hit.shell then
		ShellCombat.damage(hit.shell, damage, { by = player, assault = l.class == "Assault" })
		return true
	elseif hit.kind == "dormant" and hit.dockId then
		Docks.damage(hit.dockId, damage)
		return true
	elseif hit.kind == "light" and hit.instance then
		Lights.breakFixture(hit.instance :: BasePart)
	elseif hit.kind == "camera" and hit.instance then
		local id = SecurityCameras.idOf(hit.instance)
		if id then
			SecurityCameras.breakCamera(id)
		end
	elseif hit.kind == "decoy" and hit.instance then
		Decoys.hit(hit.instance :: Model)
	end
	return false
end

-- origin: where the shot leaves (the merc's head). renderTime: the server time the client was drawing.
function Weapons.fire(player: Player, origin: any, direction: any, renderTime: any)
	local l = loadouts[player]
	local body = Health.ofPlayer(player)
	-- Downed mercs can't shoot, and neither can a merc rebooting a terminal.
	if not l or not body or body.downed or body.model:GetAttribute("Operating") then
		return
	end
	if not Hitbox.finiteVector(origin) or not Hitbox.finiteVector(direction) or direction.Magnitude < 0.5 then
		return
	end
	local head = body.model:FindFirstChild("Head") :: BasePart?
	if not head then
		return
	end
	if (origin - head.Position).Magnitude > C.MaxOriginError then
		origin = head.Position
	end
	local w = l.weapon
	local now = os.clock()
	if now < l.reloadEndsAt or l.ammo <= 0 then
		return
	end
	if now - l.lastShotAt < w.Interval * 0.8 then
		return
	end
	while #l.recent > 0 and now - l.recent[1] > 1 do
		table.remove(l.recent, 1)
	end
	if #l.recent >= math.ceil(1 / w.Interval) + 1 then
		return
	end
	l.lastShotAt = now
	table.insert(l.recent, now)
	l.ammo -= 1

	local serverNow = workspace:GetServerTimeNow()
	local t = if type(renderTime) == "number" and renderTime == renderTime then math.clamp(renderTime, serverNow - C.LagCompensationMax, serverNow) else serverNow
	local aim = direction.Unit
	local ends = {}
	local landed = false
	for _ = 1, w.Pellets do
		local hit = Weapons.trace(origin, Hitbox.spread(aim, w.Spread, l.rng), w.Range, t)
		landed = apply(player, l, hit) or landed
		table.insert(ends, hit.point)
	end
	if landed then
		events:FireClient(player, "hitMarker")
	end
	combat:FireAllClients("shot", player.UserId, origin, ends, l.weaponId)
	if l.ammo <= 0 then
		Weapons.reload(player)
	else
		publish(player, l)
	end
end

function Weapons.reload(player: Player)
	local l = loadouts[player]
	if not l or l.reloadEndsAt > os.clock() or l.ammo >= l.weapon.Magazine then
		return
	end
	l.reloadEndsAt = os.clock() + l.weapon.Reload
	publish(player, l)
end

function Weapons.tick(_dt: number)
	local now = os.clock()
	for player, l in loadouts do
		if l.reloadEndsAt > 0 and now >= l.reloadEndsAt then
			l.reloadEndsAt = 0
			l.ammo = l.weapon.Magazine
			publish(player, l)
		end
	end
end

function Weapons.init()
	combat = Net.get("Combat")
	events = Net.get("MercEvents")
	local map, fac = workspace:WaitForChild("Map"), workspace:WaitForChild("Facility")
	facility = fac :: Folder
	traceParams.FilterDescendantsInstances = {
		map,
		fac:WaitForChild("Lights"),
		fac:WaitForChild("Cameras"),
		Decoys.folder(),
	}
end

return Weapons
