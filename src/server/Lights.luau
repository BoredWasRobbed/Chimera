-- Room lights: the Blackout Interface action (the room goes dark for 20 s), and fixtures that mercs
-- shoot out, which stay dark for the rest of the match. For the match: a rebooted terminal turns on its
-- wing's emergency lights, the Purge finale floodlights the Core, and the Upload finale kills every
-- light in the Core.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local FacilityMap = require(ReplicatedStorage.Shared.FacilityMap)
local Cues = require(script.Parent.Cues)
local MapData = require(script.Parent.MapData)

local Lights = {}

local EMERGENCY_ON = Color3.fromRGB(255, 160, 60) -- amber, as the design doc has it: red is the Chimera's
local EMERGENCY_OFF = Color3.fromRGB(35, 35, 38)
local FLOOD_ON = Color3.fromRGB(235, 245, 255)
local FLOOD_OFF = Color3.fromRGB(30, 32, 36)

local darkUntil: { [string]: number } = {}
local saved: { [BasePart]: { color: Color3, material: Enum.Material } } = {}
local broken: { [BasePart]: boolean } = {}
local powerCut: { [string]: boolean } = {} -- rooms with every light dead until the next round
local emergency: { [string]: { BasePart } } = {}
local floods: { BasePart } = {}

local function setFixtureLit(fixture: BasePart, lit: boolean)
	if not saved[fixture] then
		saved[fixture] = { color = fixture.Color, material = fixture.Material }
	end
	local original = saved[fixture]
	lit = lit and not broken[fixture]
	fixture.Material = if lit then original.material else Enum.Material.SmoothPlastic
	fixture.Color = if lit then original.color else Color3.fromRGB(30, 30, 32)
	for _, light in fixture:GetDescendants() do
		if light:IsA("Light") then
			light.Enabled = lit
		end
	end
end

local function setLamp(part: BasePart, on: boolean, onColor: Color3, offColor: Color3)
	part.Material = if on then Enum.Material.Neon else Enum.Material.SmoothPlastic
	part.Color = if on then onColor else offColor
	for _, light in part:GetDescendants() do
		if light:IsA("Light") then
			light.Enabled = on
		end
	end
end

-- A merc shot this fixture. Returns true if it was still working.
function Lights.breakFixture(fixture: BasePart): boolean
	if broken[fixture] or fixture.Name ~= "Fixture" then
		return false
	end
	setFixtureLit(fixture, false)
	broken[fixture] = true
	return true
end

local function setRoomLit(roomId: string, lit: boolean)
	local room = MapData.rooms[roomId]
	if not room then
		return
	end
	lit = lit and not powerCut[roomId]
	for _, fixture in room.fixtures do
		setFixtureLit(fixture, lit)
	end
	if room.panel then
		local indicator = room.panel:FindFirstChild("Indicator")
		if indicator and indicator:IsA("BasePart") then
			indicator.Color = if lit then Color3.fromRGB(120, 220, 255) else Color3.fromRGB(25, 25, 25)
		end
	end
end

function Lights.isDark(roomId: string): boolean
	return powerCut[roomId] == true or (darkUntil[roomId] or 0) > os.clock()
end

function Lights.blackout(roomId: string): (boolean, string?)
	local room = MapData.rooms[roomId]
	if not room then
		return false, "No such room"
	end
	if Lights.isDark(roomId) then
		return false, "Already dark"
	end
	local settings = Config.Interface.Blackout
	local untilTime = os.clock() + settings.DurationSeconds
	darkUntil[roomId] = untilTime
	local cuePosition = if room.panel then room.panel.Position else room.bounds.Position
	Cues.emit("PowerDown", cuePosition, settings.SoundRange)
	-- The tell: a short flicker, then dark.
	task.spawn(function()
		for _ = 1, 2 do
			setRoomLit(roomId, false)
			task.wait(0.08)
			setRoomLit(roomId, true)
			task.wait(0.1)
		end
		-- Lit again if a new round started during the flicker.
		setRoomLit(roomId, darkUntil[roomId] ~= untilTime)
	end)
	task.delay(settings.DurationSeconds, function()
		if darkUntil[roomId] == untilTime then
			darkUntil[roomId] = nil
			setRoomLit(roomId, true)
		end
	end)
	return true
end

-- Every light in the room dies until the next round (the Upload finale does this to the Core).
function Lights.cutPower(roomId: string)
	powerCut[roomId] = true
	setRoomLit(roomId, false)
	Lights.setFloodlights(false)
	local room = MapData.rooms[roomId]
	if room then
		Cues.emit("PowerDown", room.bounds.Position, 120)
	end
end

-- A rebooted terminal's wing: amber emergency lamps in each of its rooms, on for the rest of the match.
function Lights.setEmergency(wing: string, on: boolean)
	for roomId, parts in emergency do
		local room = MapData.rooms[roomId]
		if room and room.wing == wing then
			for _, part in parts do
				setLamp(part, on, EMERGENCY_ON, EMERGENCY_OFF)
			end
		end
	end
end

-- The Purge finale floodlights the Core.
function Lights.setFloodlights(on: boolean)
	for _, part in floods do
		setLamp(part, on, FLOOD_ON, FLOOD_OFF)
	end
end

-- A new round: every light works again.
function Lights.reset()
	table.clear(darkUntil)
	table.clear(broken)
	table.clear(powerCut)
	for roomId in MapData.rooms do
		setRoomLit(roomId, true)
	end
	for _, parts in emergency do
		for _, part in parts do
			setLamp(part, false, EMERGENCY_ON, EMERGENCY_OFF)
		end
	end
	Lights.setFloodlights(false)
end

function Lights.init()
	emergency = FacilityMap.emergencyLights()
	floods = FacilityMap.floodlights()
end

return Lights
