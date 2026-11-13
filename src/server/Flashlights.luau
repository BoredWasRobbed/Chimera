-- Merc shoulder flashlights, owned by the server: on/off, the battery (200 s of light, 0.5% a second),
-- Flash (20% battery, 20 s cooldown), and charging stations (25% a second). The beam follows the merc's
-- aim, which clients report ten times a second. A beam within 15 studs turns a Cloaked shell Exposed;
-- the Chimera's client draws beams through walls (see client Flashlights).
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local FacilityMap = require(ReplicatedStorage.Shared.FacilityMap)
local Hitbox = require(ReplicatedStorage.Shared.Hitbox)
local Health = require(script.Parent.Health)
local Sight = require(script.Parent.Sight)

local F = Config.Flashlight
local DRAIN = 100 / F.BatterySeconds

type Light = {
	player: Player,
	on: boolean,
	battery: number,
	flashReadyAt: number,
	aim: Vector3,
	aimPublishedAt: number,
	publishedBattery: number,
}

local Flashlights = {}

local lights: { [Player]: Light } = {}
local stationPads: { BasePart } = {}
local onFlash: (Player, Vector3, Vector3) -> () = function() end

local function serverTime(clockTime: number): number
	return workspace:GetServerTimeNow() + (clockTime - os.clock())
end

local function publish(light: Light)
	local player = light.player
	light.publishedBattery = math.floor(light.battery * 10 + 0.5) / 10
	player:SetAttribute("Battery", light.publishedBattery)
	player:SetAttribute("FlashReadyAt", serverTime(light.flashReadyAt))
	local character = player.Character
	if character then
		character:SetAttribute("Flashlight", light.on and light.battery > 0)
	end
end

-- Where a merc's beam starts and points: the right shoulder, along their aim.
function Flashlights.beamOf(player: Player): (Vector3?, Vector3?)
	local light = lights[player]
	local character = player.Character
	local torso = character and character:FindFirstChild("Torso") :: BasePart?
	if not light or not torso then
		return nil, nil
	end
	return (torso.CFrame * CFrame.new(0.9, 0.8, -0.5)).Position, light.aim
end

-- Is `point` inside any lit beam within `range` (and in its cone), with nothing in the way?
function Flashlights.covers(point: Vector3, range: number): boolean
	for player, light in lights do
		if not light.on or light.battery <= 0 then
			continue
		end
		local body = Health.ofPlayer(player)
		if not body then
			continue
		end
		local origin, aim = Flashlights.beamOf(player)
		if origin and aim and Hitbox.inCone(origin, aim, point, range, F.BeamHalfAngle) and Sight.clear(origin, point) then
			return true
		end
	end
	return false
end

function Flashlights.addMerc(player: Player)
	local light: Light = {
		player = player,
		on = false,
		battery = 100,
		flashReadyAt = 0,
		aim = Vector3.new(0, 0, -1),
		aimPublishedAt = 0,
		publishedBattery = -1,
	}
	lights[player] = light
	publish(light)
end

function Flashlights.removeMerc(player: Player)
	lights[player] = nil
end

-- A fresh body: full battery, light off.
function Flashlights.reset(player: Player)
	local light = lights[player]
	if light then
		light.on = false
		light.battery = 100
		light.flashReadyAt = 0
		publish(light)
	end
end

function Flashlights.setAim(player: Player, aim: any)
	local light = lights[player]
	if not light or not Hitbox.finiteVector(aim) or aim.Magnitude < 0.5 then
		return
	end
	light.aim = aim.Unit
	local now = os.clock()
	local character = player.Character
	if character and now - light.aimPublishedAt >= 0.1 then
		light.aimPublishedAt = now
		character:SetAttribute("Aim", light.aim)
	end
end

function Flashlights.toggle(player: Player, on: any)
	local light = lights[player]
	if not light or type(on) ~= "boolean" then
		return
	end
	light.on = on and light.battery > 0
	publish(light)
end

-- A burst that Reveals and staggers a shell in the beam within 12 studs.
function Flashlights.flash(player: Player): boolean
	local light = lights[player]
	local body = Health.ofPlayer(player)
	if not light or not body or body.downed then
		return false
	end
	local now = os.clock()
	if now < light.flashReadyAt or light.battery < F.FlashCost then
		return false
	end
	light.battery -= F.FlashCost
	light.flashReadyAt = now + F.FlashCooldown
	publish(light)
	local origin, aim = Flashlights.beamOf(player)
	if origin and aim then
		onFlash(player, origin, aim)
	end
	return true
end

function Flashlights.tick(dt: number)
	for player, light in lights do
		local body = Health.ofPlayer(player)
		if not body then
			continue
		end
		if light.on then
			light.battery = math.max(0, light.battery - DRAIN * dt)
			if light.battery <= 0 then
				light.on = false
				publish(light)
			end
		end
		for _, pad in stationPads do
			if light.battery < 100 and (body.root.Position - pad.Position).Magnitude <= F.ChargeRange then
				light.battery = math.min(100, light.battery + F.ChargePerSecond * dt)
				break
			end
		end
		if math.abs(light.battery - light.publishedBattery) >= 0.5 or (light.battery >= 100 and light.publishedBattery < 100) then
			publish(light)
		end
	end
end

function Flashlights.init(flashed: (Player, Vector3, Vector3) -> ())
	onFlash = flashed
	for _, station in FacilityMap.stations() do
		table.insert(stationPads, station.pad)
	end
end

return Flashlights
