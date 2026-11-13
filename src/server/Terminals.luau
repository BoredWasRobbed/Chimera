-- Mainframe Terminals, stubbed for milestone 1: reboots arrive in milestone 3. Corrupt already works:
-- it knocks 20% off the terminal's progress and locks it for 10 s, with a visible and audible tell.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Cues = require(script.Parent.Cues)
local MapData = require(script.Parent.MapData)
local MatchEvents = require(script.Parent.MatchEvents)

local Terminals = {}

local lockedUntil: { [string]: number } = {}

local function setScreen(id: string, text: string, color: Color3)
	local terminal = MapData.terminals[id]
	local screen = terminal and terminal.screen
	if not screen then
		return
	end
	screen.Color = color
	local display = screen:FindFirstChild("Display")
	local label = display and display:FindFirstChild("Text")
	if label and label:IsA("TextLabel") then
		label.Text = text
		label.TextColor3 = color
	end
end

local function idleText(id: string): string
	local terminal = MapData.terminals[id]
	local progress = terminal and terminal.model:GetAttribute("Progress") or 0
	return string.format("MAINFRAME\nREBOOT %d%%", math.floor(progress * 100 + 0.5))
end

function Terminals.init()
	for id, terminal in MapData.terminals do
		if terminal.model:GetAttribute("Progress") == nil then
			terminal.model:SetAttribute("Progress", 0)
		end
		setScreen(id, idleText(id), Color3.fromRGB(110, 200, 255))
	end
end

function Terminals.isLocked(id: string): boolean
	return (lockedUntil[id] or 0) > os.clock()
end

function Terminals.corrupt(id: string): (boolean, string?)
	local terminal = MapData.terminals[id]
	if not terminal then
		return false, "No such terminal"
	end
	if Terminals.isLocked(id) then
		return false, "Terminal is already locked"
	end
	local settings = Config.Interface.CorruptTerminal
	local progress = terminal.model:GetAttribute("Progress") or 0
	terminal.model:SetAttribute("Progress", math.max(0, progress - settings.ProgressLoss))
	local untilTime = os.clock() + settings.LockSeconds
	lockedUntil[id] = untilTime
	terminal.model:SetAttribute("LockedUntil", workspace:GetServerTimeNow() + settings.LockSeconds)
	setScreen(id, "SYSTEM FAULT\nLOCKED", Color3.fromRGB(200, 90, 255))
	MatchEvents.fire("TerminalCorrupted", { terminal = id })
	Cues.emit("TerminalCorrupt", (terminal.screen or terminal.model.PrimaryPart or terminal.model:GetPivot()).Position, settings.SoundRange)
	task.delay(settings.LockSeconds, function()
		if lockedUntil[id] == untilTime then
			lockedUntil[id] = nil
			setScreen(id, idleText(id), Color3.fromRGB(110, 200, 255))
		end
	end)
	return true
end

return Terminals
