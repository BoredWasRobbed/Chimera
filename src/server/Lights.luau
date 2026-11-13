-- Room lights and the Blackout Interface action (stub for milestone 1: the room goes dark for 20 s).
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Cues = require(script.Parent.Cues)
local MapData = require(script.Parent.MapData)

local Lights = {}

local darkUntil: { [string]: number } = {}
local saved: { [BasePart]: { color: Color3, material: Enum.Material } } = {}

local function setRoomLit(roomId: string, lit: boolean)
	local room = MapData.rooms[roomId]
	if not room then
		return
	end
	for _, fixture in room.fixtures do
		if not saved[fixture] then
			saved[fixture] = { color = fixture.Color, material = fixture.Material }
		end
		local original = saved[fixture]
		fixture.Material = if lit then original.material else Enum.Material.SmoothPlastic
		fixture.Color = if lit then original.color else Color3.fromRGB(30, 30, 32)
		for _, light in fixture:GetDescendants() do
			if light:IsA("Light") then
				light.Enabled = lit
			end
		end
	end
	if room.panel then
		local indicator = room.panel:FindFirstChild("Indicator")
		if indicator and indicator:IsA("BasePart") then
			indicator.Color = if lit then Color3.fromRGB(120, 220, 255) else Color3.fromRGB(25, 25, 25)
		end
	end
end

function Lights.isDark(roomId: string): boolean
	return (darkUntil[roomId] or 0) > os.clock()
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
		setRoomLit(roomId, false)
	end)
	task.delay(settings.DurationSeconds, function()
		if darkUntil[roomId] == untilTime then
			darkUntil[roomId] = nil
			setRoomLit(roomId, true)
		end
	end)
	return true
end

return Lights
