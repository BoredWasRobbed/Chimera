-- Class gear, owned by the server:
--   Assault     Frag Grenade x2: heavy damage, staggers the shell for 1 s.
--   Technician  Trip Mine x2: when a shell passes, a loud alarm and a 40% slow for 2 s.
--   Medic       Nano-Regen Station: heals 8 HP a second in a small field for 30 s; 60 s cooldown.
--   Scout       Sensor Dart x2: sticks to a surface; outlines a shell for every merc for 3 s if it
--               passes within 8 studs.
-- Placed gear is ordinary replicated parts in Workspace.Gear: mercs' kit isn't secret.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Hitbox = require(ReplicatedStorage.Shared.Hitbox)
local Net = require(ReplicatedStorage.Shared.Net)
local Cues = require(script.Parent.Cues)
local Health = require(script.Parent.Health)
local ShellCombat = require(script.Parent.ShellCombat)
local Shells = require(script.Parent.Shells)
local Weapons = require(script.Parent.Weapons)

local G = Config.Gear

type Grenade = { part: BasePart, pos: Vector3, vel: Vector3, fuseAt: number, owner: Player }
type Placed = { part: BasePart, pos: Vector3, owner: Player?, endsAt: number? }

local Gear = {}

local folder: Folder
local combat: RemoteEvent
local mapParams = RaycastParams.new()
mapParams.FilterType = Enum.RaycastFilterType.Include
local counts: { [Player]: number } = {}
local readyAt: { [Player]: number } = {}
local grenades: { Grenade } = {}
local mines: { Placed } = {}
local darts: { Placed } = {}
local stations: { Placed } = {}

local function serverTime(clockTime: number): number
	return workspace:GetServerTimeNow() + (clockTime - os.clock())
end

local function publish(player: Player)
	local class = player:GetAttribute("Class")
	local info = Config.Classes[class]
	player:SetAttribute("Gear", if info then info.Gear else nil)
	player:SetAttribute("GearCount", counts[player] or 0)
	player:SetAttribute("GearReadyAt", if readyAt[player] then serverTime(readyAt[player]) else 0)
end

local function makePart(name: string, size: Vector3, cframe: CFrame, color: Color3, material: Enum.Material?, shape: Enum.PartType?): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.CFrame = cframe
	p.Color = color
	p.Material = material or Enum.Material.Neon
	if shape then
		p.Shape = shape
	end
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Parent = folder
	return p
end

function Gear.equip(player: Player, class: string)
	local info = Config.Classes[class]
	counts[player] = if info then info.GearCount else 0
	readyAt[player] = nil
	publish(player)
end

function Gear.remove(player: Player)
	counts[player] = nil
	readyAt[player] = nil
end

-- A new round: no grenades in the air, no mines, darts or Nano-Regen stations left behind.
function Gear.clear()
	for _, list in { grenades, mines, darts, stations } do
		for _, item in list do
			item.part:Destroy()
		end
		table.clear(list)
	end
end

local function explode(grenade: Grenade, at: Vector3)
	grenade.part:Destroy()
	local frag = G.FragGrenade
	ShellCombat.explosion(at, frag.Radius, frag.Damage, frag.Stagger, grenade.owner)
	combat:FireAllClients("explosion", at, frag.Radius)
end

local function throwGrenade(player: Player, origin: Vector3, aim: Vector3)
	local frag = G.FragGrenade
	local velocity = (aim + Vector3.new(0, 0.25, 0)).Unit * frag.ThrowSpeed
	local part = makePart("Grenade", Vector3.new(0.8, 0.8, 0.8), CFrame.new(origin), Color3.fromRGB(70, 75, 60), Enum.Material.Metal, Enum.PartType.Ball)
	table.insert(grenades, { part = part, pos = origin, vel = velocity, fuseAt = os.clock() + frag.Fuse, owner = player })
end

local function placeMine(player: Player, origin: Vector3, aim: Vector3): boolean
	local hit = workspace:Raycast(origin, aim * G.TripMine.PlaceRange, mapParams)
	local pos, normal
	if hit then
		pos, normal = hit.Position, hit.Normal
	else
		local floor = workspace:Raycast(origin + aim * 3, Vector3.new(0, -12, 0), mapParams)
		if not floor then
			return false
		end
		pos, normal = floor.Position, floor.Normal
	end
	local cf = CFrame.lookAt(pos, pos + normal) * CFrame.new(0, 0, -0.1)
	local part = makePart("TripMine", Vector3.new(1.2, 1.2, 0.2), cf, Color3.fromRGB(255, 190, 60))
	table.insert(mines, { part = part, pos = pos, owner = player })
	return true
end

local function fireDart(player: Player, origin: Vector3, aim: Vector3)
	local hit = Weapons.trace(origin, aim, G.SensorDart.Range, workspace:GetServerTimeNow())
	combat:FireAllClients("dart", origin, hit.point)
	if hit.kind == "shell" and hit.shell then
		ShellCombat.dartReveal(hit.shell)
		return
	end
	if hit.kind ~= "none" then
		local part = makePart("SensorDart", Vector3.new(0.3, 0.3, 0.8), CFrame.lookAt(hit.point, hit.point + aim), Color3.fromRGB(120, 255, 200))
		table.insert(darts, { part = part, pos = hit.point, owner = player })
	end
end

local function placeStation(player: Player, origin: Vector3, aim: Vector3): boolean
	local flat = Vector3.new(aim.X, 0, aim.Z)
	flat = if flat.Magnitude > 0.1 then flat.Unit else Vector3.new(0, 0, -1)
	local floor = workspace:Raycast(origin + flat * 3, Vector3.new(0, -12, 0), mapParams)
	if not floor then
		return false
	end
	local N = G.NanoRegen
	local part = makePart("NanoRegen", Vector3.new(0.4, N.Radius * 2, N.Radius * 2), CFrame.new(floor.Position + Vector3.new(0, 0.2, 0)) * CFrame.Angles(0, 0, math.pi / 2), Color3.fromRGB(120, 255, 200), Enum.Material.ForceField, Enum.PartType.Cylinder)
	part.Transparency = 0.5
	table.insert(stations, { part = part, pos = floor.Position, owner = player, endsAt = os.clock() + N.Duration })
	return true
end

-- origin: the merc's head. aim: where they're looking.
function Gear.use(player: Player, origin: any, aim: any)
	local body = Health.ofPlayer(player)
	if not body or body.downed or body.model:GetAttribute("Operating") or not Hitbox.finiteVector(origin) or not Hitbox.finiteVector(aim) or aim.Magnitude < 0.5 then
		return
	end
	local head = body.model:FindFirstChild("Head") :: BasePart?
	if not head then
		return
	end
	if (origin - head.Position).Magnitude > Config.Combat.MaxOriginError then
		origin = head.Position
	end
	aim = aim.Unit
	local class = player:GetAttribute("Class")
	if class == "Medic" then
		local now = os.clock()
		if readyAt[player] and now < readyAt[player] then
			return
		end
		if placeStation(player, origin, aim) then
			readyAt[player] = now + G.NanoRegen.Cooldown
			publish(player)
		end
		return
	end
	if (counts[player] or 0) <= 0 then
		return
	end
	local used = true
	if class == "Assault" then
		throwGrenade(player, origin, aim)
	elseif class == "Technician" then
		used = placeMine(player, origin, aim)
	elseif class == "Scout" then
		fireDart(player, origin, aim)
	else
		used = false
	end
	if used then
		counts[player] -= 1
		publish(player)
	end
end

local function nearestShell(pos: Vector3, radius: number): Shells.Shell?
	for _, shell in Shells.all() do
		if not shell.dead and (shell.state.pos + Vector3.new(0, 2.5, 0) - pos).Magnitude <= radius then
			return shell
		end
	end
	return nil
end

function Gear.tick(dt: number)
	local now = os.clock()
	local frag = G.FragGrenade
	for i = #grenades, 1, -1 do
		local g = grenades[i]
		local nextVel = g.vel - Vector3.new(0, frag.Gravity * dt, 0)
		local step = g.vel * dt
		local hit = workspace:Raycast(g.pos, step, mapParams)
		if hit or now >= g.fuseAt or nearestShell(g.pos, 2.5) then
			table.remove(grenades, i)
			explode(g, if hit then hit.Position + hit.Normal * 0.3 else g.pos)
		else
			g.pos += step
			g.vel = nextVel
			g.part.CFrame = CFrame.new(g.pos)
		end
	end
	for i = #mines, 1, -1 do
		local mine = mines[i]
		local shell = nearestShell(mine.pos, G.TripMine.TriggerRadius)
		if shell then
			table.remove(mines, i)
			mine.part:Destroy()
			ShellCombat.slow(shell, G.TripMine.SlowScale, G.TripMine.SlowSeconds)
			Cues.emit("TripAlarm", mine.pos, G.TripMine.AlarmRange)
			combat:FireAllClients("alarm", mine.pos)
		end
	end
	for i = #darts, 1, -1 do
		local dart = darts[i]
		local shell = nearestShell(dart.pos, G.SensorDart.TriggerRadius)
		if shell then
			table.remove(darts, i)
			dart.part:Destroy()
			ShellCombat.dartReveal(shell)
			combat:FireAllClients("dartPing", dart.pos)
		end
	end
	local N = G.NanoRegen
	for i = #stations, 1, -1 do
		local station = stations[i]
		if now >= (station.endsAt :: number) then
			table.remove(stations, i)
			station.part:Destroy()
			continue
		end
		for _, body in Health.near(station.pos + Vector3.new(0, 3, 0), N.Radius, false) do
			Health.heal(body.model, N.HealPerSecond * dt)
		end
	end
	for player, at in readyAt do
		if now >= at then
			readyAt[player] = nil
			publish(player)
		end
	end
end

function Gear.init()
	combat = Net.get("Combat")
	mapParams.FilterDescendantsInstances = { workspace:WaitForChild("Map") }
	folder = Instance.new("Folder")
	folder.Name = "Gear"
	folder.Parent = workspace
end

return Gear
