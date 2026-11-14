-- The building's mood on every client, all decoration:
--   Flicker      failing light fixtures (a Fixture part tagged Flicker; attribute FlickerMode "flicker",
--                "dying" or "buzz") stutter while their room has power. A fixture the server has switched
--                off (Blackout, a shot, the Upload finale) is left alone, so the server still owns the lights.
--   Lightning    now and then over the city: the CityGlow spotlights outside the windows flash and the sky
--                lights up for a moment.
--   RainGlass    window textures: the rain on the glass runs down.
--   CityBeacon   the white beacons on the city's masts blink.
-- It reads only what every client already has and changes nothing the server owns.
local CollectionService = game:GetService("CollectionService")
local Lighting = game:GetService("Lighting")
local RunService = game:GetService("RunService")

local Ambience = {}

local NEAR = 140 -- studs: fixtures and rainy panes farther from the camera aren't animated
local DARK = Color3.fromRGB(46, 46, 48)

type Flicker = {
	part: BasePart,
	lights: { Light },
	base: { number },
	color: Color3?,
	mode: string,
	seed: Random,
	nextAt: number,
	level: number,
}

local flickers: { Flicker } = {}
local glows: { { light: SpotLight, base: number } } = {}
local panes: { Texture } = {}
local beacons: { BasePart } = {}

local function addFlicker(part: Instance)
	if not part:IsA("BasePart") then
		return
	end
	local lights, base = {}, {}
	for _, d in part:GetDescendants() do
		if d:IsA("Light") then
			table.insert(lights, d)
			table.insert(base, d.Brightness)
		end
	end
	table.insert(flickers, {
		part = part,
		lights = lights,
		base = base,
		color = if part.Material == Enum.Material.Neon then part.Color else nil,
		mode = part:GetAttribute("FlickerMode") or "flicker",
		seed = Random.new(#flickers * 7919 + 17),
		nextAt = 0,
		level = 1,
	})
end

local function powered(f: Flicker): boolean
	-- The server switches a fixture off by disabling its lights and making it plain plastic.
	if f.part.Material ~= Enum.Material.Neon then
		return false
	end
	for _, l in f.lights do
		if not l.Enabled then
			return false
		end
	end
	return true
end

local function apply(f: Flicker, level: number)
	if f.level == level then
		return
	end
	f.level = level
	for i, l in f.lights do
		l.Brightness = f.base[i] * level
	end
	if f.color then
		f.part.Color = DARK:Lerp(f.color, math.clamp(level, 0, 1))
	end
end

-- Picks the next level and how long it holds, by mode.
local function step(f: Flicker, now: number)
	local r = f.seed
	if f.mode == "dying" then
		-- Mostly a dim glow, sputtering up for a moment now and then.
		if f.level > 0.5 then
			apply(f, 0.06 + r:NextNumber() * 0.1)
			f.nextAt = now + 0.4 + r:NextNumber() * 2.6
		else
			apply(f, 0.6 + r:NextNumber() * 0.4)
			f.nextAt = now + 0.04 + r:NextNumber() * 0.25
		end
	elseif f.mode == "buzz" then
		apply(f, 0.82 + r:NextNumber() * 0.18)
		f.nextAt = now + 0.03 + r:NextNumber() * 0.06
	else
		-- Mostly on; drops out for a blink or a burst of them.
		if f.level < 0.5 then
			apply(f, 1)
			f.nextAt = now + (if r:NextNumber() < 0.3 then 0.05 + r:NextNumber() * 0.12 else 0.6 + r:NextNumber() * 4)
		else
			apply(f, r:NextNumber() * 0.15)
			f.nextAt = now + 0.03 + r:NextNumber() * 0.15
		end
	end
end

-- Lightning: two to four flashes over about half a second.
local atmosphereBase: { color: Color3, decay: Color3, haze: number }? = nil
local outdoorBase: Color3? = nil

local function flash(strength: number)
	for _, g in glows do
		g.light.Brightness = g.base * (1 + 9 * strength)
	end
	local atmosphere = Lighting:FindFirstChildOfClass("Atmosphere")
	if atmosphere and atmosphereBase then
		atmosphere.Color = atmosphereBase.color:Lerp(Color3.fromRGB(205, 214, 240), 0.7 * strength)
		atmosphere.Decay = atmosphereBase.decay:Lerp(Color3.fromRGB(150, 160, 200), 0.6 * strength)
	end
	if outdoorBase then
		Lighting.OutdoorAmbient = outdoorBase:Lerp(Color3.fromRGB(120, 130, 160), strength)
	end
end

local function settle()
	for _, g in glows do
		g.light.Brightness = g.base
	end
	local atmosphere = Lighting:FindFirstChildOfClass("Atmosphere")
	if atmosphere and atmosphereBase then
		atmosphere.Color = atmosphereBase.color
		atmosphere.Decay = atmosphereBase.decay
	end
	if outdoorBase then
		Lighting.OutdoorAmbient = outdoorBase
	end
end

local function strike(rng: Random)
	local near = rng:NextNumber() < 0.45
	for _ = 1, rng:NextInteger(2, 4) do
		flash(if near then 0.7 + rng:NextNumber() * 0.3 else 0.15 + rng:NextNumber() * 0.2)
		task.wait(0.04 + rng:NextNumber() * 0.09)
		flash(if near then 0.08 else 0.02)
		task.wait(0.05 + rng:NextNumber() * 0.2)
	end
	settle()
end

function Ambience.init()
	for _, part in CollectionService:GetTagged("Flicker") do
		addFlicker(part)
	end
	CollectionService:GetInstanceAddedSignal("Flicker"):Connect(addFlicker)
	for _, part in CollectionService:GetTagged("CityGlow") do
		local light = part:FindFirstChildOfClass("SpotLight")
		if light then
			table.insert(glows, { light = light, base = part:GetAttribute("BaseBrightness") or light.Brightness })
		end
	end
	for _, tex in CollectionService:GetTagged("RainGlass") do
		if tex:IsA("Texture") then
			table.insert(panes, tex)
		end
	end
	for _, part in CollectionService:GetTagged("CityBeacon") do
		if part:IsA("BasePart") then
			table.insert(beacons, part)
		end
	end
	local atmosphere = Lighting:FindFirstChildOfClass("Atmosphere")
	if atmosphere then
		atmosphereBase = { color = atmosphere.Color, decay = atmosphere.Decay, haze = atmosphere.Haze }
	end
	outdoorBase = Lighting.OutdoorAmbient

	local rng = Random.new()
	task.spawn(function()
		task.wait(8 + rng:NextNumber() * 12)
		while true do
			strike(rng)
			task.wait(18 + rng:NextNumber() * 50)
		end
	end)

	local rainClock, beaconOn = 0, true
	RunService.Heartbeat:Connect(function(dt)
		local camera = workspace.CurrentCamera
		if not camera then
			return
		end
		local eye = camera.CFrame.Position
		local now = os.clock()
		for _, f in flickers do
			if f.part.Parent and (f.part.Position - eye).Magnitude < NEAR then
				if powered(f) then
					if not f.color then
						f.color = f.part.Color -- first seen lit: that's its colour
					end
					if now >= f.nextAt then
						step(f, now)
					end
				else
					f.level = -1 -- re-apply on the next powered frame
				end
			end
		end
		rainClock += dt
		if rainClock >= 1 / 15 then
			for _, tex in panes do
				local part = tex.Parent
				if part and part:IsA("BasePart") and (part.Position - eye).Magnitude < NEAR then
					tex.OffsetStudsV = (tex.OffsetStudsV + rainClock * 0.9) % tex.StudsPerTileV
				end
			end
			rainClock = 0
		end
		local on = (now % 2.4) < 0.25
		if on ~= beaconOn then
			beaconOn = on
			for _, b in beacons do
				b.Transparency = if on then 0 else 0.92
			end
		end
	end)
end

return Ambience
