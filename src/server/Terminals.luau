-- Mainframe Terminals. A merc holds E at a terminal to reboot it: a 40 s channel (Technician 28 s, and
-- 10% less per merc short of five), and progress saves when the hold stops. One operator at a time; the
-- operator can't shoot, and any damage interrupts the channel. A reboot is loud: the Chimera gets an alert
-- with the terminal's location. Corrupt (the Chimera's Interface) knocks 20% off, locks the terminal for
-- 10 s and adds 3% upload. A finished terminal turns on its wing's emergency lights and shuts down that
-- wing's docks (Match does both, through the done callback).
--
-- Both teams see every terminal's progress: the model's Progress (0..1), Operator (a player name),
-- Done and LockedUntil (server time) attributes replicate to everyone.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Cues = require(script.Parent.Cues)
local Health = require(script.Parent.Health)
local MapData = require(script.Parent.MapData)
local MatchEvents = require(script.Parent.MatchEvents)
local MatchState = require(script.Parent.MatchState)

local Terminals = {}

local T = Config.Terminals
local IDLE_COLOR = Color3.fromRGB(110, 200, 255)
local BUSY_COLOR = Color3.fromRGB(255, 205, 90)
local LOCK_COLOR = Color3.fromRGB(200, 90, 255)
local DONE_COLOR = Color3.fromRGB(90, 255, 140)

type State = {
	progress: number,
	done: boolean,
	lockedUntil: number,
	operator: Player?,
	lastAlert: number,
	publishedAt: number,
	screenKey: string,
}

local states: { [string]: State } = {}
local onDone: (string, string) -> () = function() end
local onStarted: (string) -> () = function() end

local function positionOf(id: string): Vector3
	local terminal = MapData.terminals[id]
	return (terminal.screen or terminal.model.PrimaryPart or terminal.model:GetPivot()).Position
end

local function setScreen(id: string, text: string, color: Color3)
	local state = states[id]
	local key = text .. color:ToHex()
	if state.screenKey == key then
		return
	end
	state.screenKey = key
	local screen = MapData.terminals[id].screen
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

local function refresh(id: string, force: boolean?)
	local state = states[id]
	local model = MapData.terminals[id].model
	local now = os.clock()
	if force or now - state.publishedAt >= 0.1 then
		state.publishedAt = now
		model:SetAttribute("Progress", math.floor(state.progress * 1000 + 0.5) / 1000)
	end
	model:SetAttribute("Operator", if state.operator then state.operator.Name else nil)
	model:SetAttribute("Done", state.done or nil)
	local percent = math.floor(state.progress * 100)
	if state.done then
		setScreen(id, "REBOOTED\nWING SECURE", DONE_COLOR)
	elseif Terminals.isLocked(id) then
		setScreen(id, "SYSTEM FAULT\nLOCKED", LOCK_COLOR)
	elseif state.operator then
		setScreen(id, string.format("REBOOTING\n%d%%", percent), BUSY_COLOR)
	else
		setScreen(id, string.format("MAINFRAME\nREBOOT %d%%", percent), IDLE_COLOR)
	end
end

function Terminals.isLocked(id: string): boolean
	local state = states[id]
	return state ~= nil and state.lockedUntil > os.clock()
end

function Terminals.isDone(id: string): boolean
	local state = states[id]
	return state ~= nil and state.done
end

function Terminals.doneCount(): number
	local count = 0
	for _, state in states do
		if state.done then
			count += 1
		end
	end
	return count
end

function Terminals.wingOf(id: string): string
	local terminal = MapData.terminals[id]
	local room = terminal and MapData.rooms[terminal.room]
	return if room then room.wing else ""
end

function Terminals.rebootSeconds(player: Player): number
	local base = if player:GetAttribute("Class") == "Technician" then T.TechnicianRebootSeconds else T.RebootSeconds
	return base * MatchState.rebootScale()
end

-- The terminal this player is operating, if any.
function Terminals.operating(player: Player): string?
	for id, state in states do
		if state.operator == player then
			return id
		end
	end
	return nil
end

local function stop(id: string)
	local state = states[id]
	local operator = state.operator
	if not operator then
		return
	end
	state.operator = nil
	local character = operator.Character
	if character and character:GetAttribute("Operating") == id then
		character:SetAttribute("Operating", nil)
	end
	refresh(id, true)
end

-- Why this player can't operate this terminal right now, or nil.
local function problemFor(player: Player, id: string): string?
	local state = states[id]
	if not state then
		return "No such terminal"
	end
	if MatchState.phase ~= "Race" then
		return "Terminals come online when the race starts"
	end
	if state.done then
		return "Already rebooted"
	end
	if Terminals.isLocked(id) then
		return "Terminal locked"
	end
	if player:GetAttribute("Role") ~= "Merc" or player:GetAttribute("Eliminated") then
		return "Mercs only"
	end
	local body = Health.ofPlayer(player)
	if not body or body.downed then
		return "Can't reboot while downed"
	end
	if (body.root.Position - positionOf(id)).Magnitude > T.OperateRange then
		return "Too far from the terminal"
	end
	if state.operator and state.operator ~= player then
		return "Someone else is rebooting it"
	end
	return nil
end

-- A merc started holding E at the terminal.
function Terminals.begin(player: Player, id: string): (boolean, string?)
	local problem = problemFor(player, id)
	if problem then
		return false, problem
	end
	local current = Terminals.operating(player)
	if current and current ~= id then
		stop(current)
	end
	local state = states[id]
	if state.operator == player then
		return true
	end
	state.operator = player
	if player.Character then
		player.Character:SetAttribute("Operating", id)
	end
	refresh(id, true)
	Cues.emit("RebootStart", positionOf(id), 40)
	local now = os.clock()
	if now - state.lastAlert >= T.AlertCooldown then
		state.lastAlert = now
		task.spawn(onStarted, id)
	end
	return true
end

-- The operator let go, or something interrupted them. Progress stays.
function Terminals.release(player: Player)
	local id = Terminals.operating(player)
	if id then
		stop(id)
	end
end

local function complete(id: string)
	local state = states[id]
	stop(id)
	state.progress = 1
	state.done = true
	refresh(id, true)
	Cues.emit("TerminalRebooted", positionOf(id), 120)
	task.spawn(onDone, id, Terminals.wingOf(id))
end

function Terminals.corrupt(id: string): (boolean, string?)
	local state = states[id]
	if not state then
		return false, "No such terminal"
	end
	if state.done then
		return false, "That terminal is already rebooted"
	end
	if Terminals.isLocked(id) then
		return false, "Terminal is already locked"
	end
	local settings = Config.Interface.CorruptTerminal
	stop(id)
	state.progress = math.max(0, state.progress - settings.ProgressLoss)
	state.lockedUntil = os.clock() + settings.LockSeconds
	local model = MapData.terminals[id].model
	model:SetAttribute("LockedUntil", workspace:GetServerTimeNow() + settings.LockSeconds)
	refresh(id, true)
	MatchEvents.fire("TerminalCorrupted", { terminal = id })
	Cues.emit("TerminalCorrupt", positionOf(id), settings.SoundRange)
	local lockedUntil = state.lockedUntil
	task.delay(settings.LockSeconds, function()
		if states[id] == state and state.lockedUntil == lockedUntil then
			model:SetAttribute("LockedUntil", nil)
			refresh(id, true)
		end
	end)
	return true
end

-- Studio: set a terminal's progress directly (1 completes it).
function Terminals.setProgress(id: string, progress: number)
	local state = states[id]
	if not state or state.done then
		return
	end
	state.progress = math.clamp(progress, 0, 1)
	if state.progress >= 1 then
		complete(id)
	else
		refresh(id, true)
	end
end

function Terminals.reset()
	for id, state in states do
		stop(id)
		state.progress = 0
		state.done = false
		state.lockedUntil = 0
		state.lastAlert = 0
		MapData.terminals[id].model:SetAttribute("LockedUntil", nil)
		refresh(id, true)
	end
end

function Terminals.tick(dt: number)
	for id, state in states do
		local operator = state.operator
		if not operator then
			continue
		end
		if not operator.Parent or problemFor(operator, id) then
			stop(id)
			continue
		end
		state.progress = math.min(1, state.progress + dt / Terminals.rebootSeconds(operator))
		if state.progress >= 1 then
			complete(id)
		else
			refresh(id, false)
		end
	end
end

-- done(id, wing) runs when a terminal finishes; started(id) when a reboot starts (for the Chimera's alert).
function Terminals.init(done: (string, string) -> (), started: (string) -> ())
	onDone, onStarted = done, started
	for id, terminal in MapData.terminals do
		states[id] = { progress = 0, done = false, lockedUntil = 0, operator = nil, lastAlert = 0, publishedAt = 0, screenKey = "" }
		local anchor = terminal.model:FindFirstChild("Console") or terminal.screen or terminal.model.PrimaryPart
		if anchor and anchor:IsA("BasePart") then
			local prompt = Instance.new("ProximityPrompt")
			prompt.Name = "Reboot"
			prompt.ActionText = "Reboot (hold)"
			prompt.ObjectText = terminal.displayName
			prompt.HoldDuration = 0
			prompt.KeyboardKeyCode = Enum.KeyCode.E
			prompt.MaxActivationDistance = T.PromptDistance
			prompt.RequiresLineOfSight = false
			prompt.Parent = anchor
			prompt.Triggered:Connect(function(player)
				Terminals.begin(player, id)
			end)
			prompt.TriggerEnded:Connect(function(player)
				if states[id].operator == player then
					stop(id)
				end
			end)
		end
		refresh(id, true)
	end
	-- Any damage interrupts the channel.
	Health.onDamaged(function(body)
		if body.player then
			Terminals.release(body.player)
		end
	end)
end

return Terminals
