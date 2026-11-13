-- The match on every client's screen, drawn from ReplicatedStorage.MatchState's attributes and the
-- terminals' own attributes (the server owns all of it):
--   top bar     the phase and clock, Threat Level, the upload meter, every terminal's progress, and in a
--               finale the held time (both teams see all of it)
--   lobby       who's here with their Chimera Chance, the Merc only toggle and the countdown
--   loadout     class cards within the slice caps for mercs, the default build for the Chimera
--   deployment  what your side is doing; results: who won and why
-- While the player has no body or camera of its own (lobby, loadout, results), the camera circles the Core.
-- It also reports recent input to the server, which sends idle players to the lobby.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Config = require(ReplicatedStorage.Shared.Config)
local Net = require(ReplicatedStorage.Shared.Net)
local Hud = require(script.Parent.Hud)

local MatchHud = {}

local player = Players.LocalPlayer
local UPLOAD_COLOR = Color3.fromRGB(205, 80, 255)
local MERC_COLOR = Color3.fromRGB(110, 210, 255)
local DONE_COLOR = Color3.fromRGB(90, 255, 140)
local LOCK_COLOR = Color3.fromRGB(200, 90, 255)
local BUSY_COLOR = Color3.fromRGB(255, 205, 90)

local PASSIVES = {
	Assault = "Hits slow the Chimera",
	Technician = "Welds doors, reboots in 28 s",
	Medic = "Revives in 2.5 s",
	Scout = "Heartbeat at 15 studs, sees leap trails",
}

local CHIMERA_BUILD = table.concat({
	"PHASE WEAVE  chassis: a balanced cloak, 1,000 HP",
	"ENERGY CLAWS  attack: 6-stud swipe, 35 damage",
	"SYSTEM LEAP  traversal: jump to a camera or terminal",
	"STATIC DECOY  utility: a fake merc walks where you aim",
	"OVERLOAD  sabotage: arm steam pipes and conduits",
}, "\n")

type TerminalCell = { model: Model, label: TextLabel, setBar: (number) -> (), fill: Frame }

local state: Configuration
local actionRemote: RemoteEvent
local ui: { [string]: any } = {}
local cells: { TerminalCell } = {}
local classCards: { [string]: { button: TextButton, count: TextLabel } } = {}
local orbitAngle = 0
local lastInputAt = 0
local lastReportAt = 0

local function attr(name: string): any
	return state:GetAttribute(name)
end

local function serverNow(): number
	return workspace:GetServerTimeNow()
end

local function clock(seconds: number): string
	seconds = math.max(0, math.floor(seconds))
	return string.format("%d:%02d", seconds // 60, seconds % 60)
end

local function untilEnd(): number
	local endsAt = attr("PhaseEndsAt") or 0
	return if endsAt > 0 then endsAt - serverNow() else 0
end

local function shortName(model: Model): string
	local name = model:GetAttribute("DisplayName") or model.Name
	return string.upper((string.gsub(name, " terminal$", "")))
end

local function buildTopBar(gui: ScreenGui)
	local bar = Hud.frame(gui, {
		Name = "MatchBar",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 6),
		Size = UDim2.fromOffset(540, 62),
		BackgroundTransparency = 0.45,
	})
	ui.bar = bar
	ui.phase = Hud.text(bar, { Position = UDim2.fromOffset(10, 3), Size = UDim2.fromOffset(380, 20), TextSize = 16, FontFace = Hud.FONT_BOLD })
	ui.threat = Hud.text(bar, { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -10, 0, 3), Size = UDim2.fromOffset(150, 20), TextSize = 15, FontFace = Hud.FONT_BOLD, TextXAlignment = Enum.TextXAlignment.Right })
	local upload, setUpload = Hud.bar(bar, { Position = UDim2.fromOffset(10, 25), Size = UDim2.new(1, -20, 0, 14), BackgroundTransparency = 0.2, BackgroundColor3 = Color3.fromRGB(30, 20, 40) }, UPLOAD_COLOR)
	ui.setUpload = setUpload
	ui.uploadLabel = Hud.text(upload, { Size = UDim2.fromScale(1, 1), TextSize = 12, FontFace = Hud.FONT_BOLD, TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 3 })

	local row = Hud.frame(bar, { Name = "Terminals", Position = UDim2.fromOffset(10, 43), Size = UDim2.new(1, -20, 0, 15), BackgroundTransparency = 1 })
	ui.terminalRow = row
	local folder = workspace:WaitForChild("Map"):WaitForChild("Terminals")
	local models = {}
	for _, model in folder:GetChildren() do
		if model:IsA("Model") and model:GetAttribute("TerminalId") then
			table.insert(models, model)
		end
	end
	table.sort(models, function(a, b)
		return a.Name < b.Name
	end)
	local width = 1 / math.max(1, #models)
	for index, model in models do
		local cell = Hud.frame(row, { Position = UDim2.new(width * (index - 1), 2, 0, 0), Size = UDim2.new(width, -4, 1, 0), BackgroundTransparency = 0.2, BackgroundColor3 = Color3.fromRGB(16, 22, 28) })
		local fill = Hud.frame(cell, { Name = "Fill", Size = UDim2.fromScale(0, 1), BackgroundColor3 = MERC_COLOR, BackgroundTransparency = 0.35 })
		local label = Hud.text(cell, { Size = UDim2.fromScale(1, 1), TextSize = 11, FontFace = Hud.FONT_BOLD, TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 3 })
		table.insert(cells, {
			model = model,
			label = label,
			fill = fill,
			setBar = function(alpha: number)
				fill.Size = UDim2.fromScale(math.clamp(alpha, 0, 1), 1)
			end,
		})
	end

	local finale = Hud.frame(bar, { Name = "Finale", Position = UDim2.fromOffset(10, 43), Size = UDim2.new(1, -20, 0, 15), BackgroundTransparency = 0.2, BackgroundColor3 = Color3.fromRGB(16, 22, 28), Visible = false })
	ui.finaleRow = finale
	ui.finaleFill = Hud.frame(finale, { Name = "Fill", Size = UDim2.fromScale(0, 1), BackgroundColor3 = MERC_COLOR, BackgroundTransparency = 0.2 })
	ui.finaleLabel = Hud.text(finale, { Size = UDim2.fromScale(1, 1), TextSize = 11, FontFace = Hud.FONT_BOLD, TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 3 })
end

local function centerPanel(gui: ScreenGui, name: string, height: number): Frame
	return Hud.frame(gui, {
		Name = name,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(520, height),
		BackgroundTransparency = 0.25,
		Visible = false,
		ZIndex = 10,
	})
end

local function buildLobby(gui: ScreenGui)
	local panel = centerPanel(gui, "Lobby", 340)
	ui.lobby = panel
	Hud.text(panel, { Text = "LOBBY", Position = UDim2.fromOffset(16, 10), Size = UDim2.fromOffset(300, 26), TextSize = 22, FontFace = Hud.FONT_BOLD, ZIndex = 11 })
	ui.lobbyStatus = Hud.text(panel, { Position = UDim2.fromOffset(16, 40), Size = UDim2.new(1, -32, 0, 20), TextSize = 16, TextColor3 = Hud.CYAN, ZIndex = 11 })
	Hud.text(panel, { Text = "CHIMERA CHANCE", Position = UDim2.fromOffset(16, 70), Size = UDim2.fromOffset(300, 18), TextSize = 13, TextColor3 = Hud.DIM, FontFace = Hud.FONT_BOLD, ZIndex = 11 })
	ui.lobbyList = Hud.text(panel, { Position = UDim2.fromOffset(16, 92), Size = UDim2.new(1, -32, 0, 180), TextSize = 15, TextYAlignment = Enum.TextYAlignment.Top, ZIndex = 11 })
	local toggle = Hud.button(panel, { Name = "MercOnly", AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 16, 1, -14), Size = UDim2.fromOffset(220, 30), TextSize = 15, ZIndex = 11 })
	ui.mercOnly = toggle
	toggle.Activated:Connect(function()
		actionRemote:FireServer("mercOnly", not player:GetAttribute("MercOnly"))
	end)
	Hud.text(panel, { Text = "Merc only: never be picked as the Chimera", AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 246, 1, -18), Size = UDim2.fromOffset(260, 22), TextSize = 12, TextColor3 = Hud.DIM, TextWrapped = true, ZIndex = 11 })
end

local function buildLoadout(gui: ScreenGui)
	local panel = centerPanel(gui, "Loadout", 310)
	ui.loadout = panel
	ui.loadoutTitle = Hud.text(panel, { Position = UDim2.fromOffset(16, 10), Size = UDim2.new(1, -32, 0, 26), TextSize = 22, FontFace = Hud.FONT_BOLD, ZIndex = 11 })
	ui.loadoutStatus = Hud.text(panel, { Position = UDim2.fromOffset(16, 40), Size = UDim2.new(1, -32, 0, 52), TextSize = 15, TextColor3 = Hud.CYAN, TextWrapped = true, TextYAlignment = Enum.TextYAlignment.Top, ZIndex = 11 })
	ui.build = Hud.text(panel, { Text = CHIMERA_BUILD, Position = UDim2.fromOffset(16, 100), Size = UDim2.new(1, -32, 0, 120), TextSize = 15, TextYAlignment = Enum.TextYAlignment.Top, LineHeight = 1.3, Visible = false, ZIndex = 11 })
	local cards = Hud.frame(panel, { Name = "Cards", Position = UDim2.fromOffset(16, 100), Size = UDim2.new(1, -32, 0, 190), BackgroundTransparency = 1, ZIndex = 11 })
	ui.cards = cards
	local order = Config.Classes.Order
	local width = 1 / #order
	for index, class in order do
		local info = Config.Classes[class]
		local button = Hud.button(cards, {
			Name = class,
			Text = "",
			Position = UDim2.new(width * (index - 1), 3, 0, 0),
			Size = UDim2.new(width, -6, 1, 0),
			BackgroundTransparency = 0.15,
			ZIndex = 12,
		})
		local stroke = Instance.new("UIStroke")
		stroke.Name = "Selected"
		stroke.Thickness = 2
		stroke.Color = MERC_COLOR
		stroke.Enabled = false
		stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		stroke.Parent = button
		Hud.text(button, { Text = string.upper(class), Position = UDim2.fromOffset(8, 8), Size = UDim2.new(1, -16, 0, 20), TextSize = 15, FontFace = Hud.FONT_BOLD, ZIndex = 13 })
		local lines = `{Config.Weapons[info.Weapon].Name}\n{Config.Gear[info.Gear].Name} ×{info.GearCount}\n\n{PASSIVES[class] or ""}`
		Hud.text(button, { Text = lines, Position = UDim2.fromOffset(8, 34), Size = UDim2.new(1, -16, 0, 110), TextSize = 12, TextWrapped = true, TextYAlignment = Enum.TextYAlignment.Top, TextColor3 = Hud.DIM, ZIndex = 13 })
		local count = Hud.text(button, { AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 8, 1, -8), Size = UDim2.new(1, -16, 0, 18), TextSize = 13, FontFace = Hud.FONT_BOLD, ZIndex = 13 })
		classCards[class] = { button = button, count = count }
		button.Activated:Connect(function()
			actionRemote:FireServer("class", class)
		end)
	end
end

local function buildResults(gui: ScreenGui)
	local panel = centerPanel(gui, "Results", 220)
	ui.results = panel
	ui.resultTitle = Hud.text(panel, { Position = UDim2.fromOffset(16, 18), Size = UDim2.new(1, -32, 0, 40), TextSize = 32, FontFace = Hud.FONT_BOLD, TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 11 })
	ui.resultYou = Hud.text(panel, { Position = UDim2.fromOffset(16, 62), Size = UDim2.new(1, -32, 0, 22), TextSize = 18, FontFace = Hud.FONT_BOLD, TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 11 })
	ui.resultReason = Hud.text(panel, { Position = UDim2.fromOffset(16, 96), Size = UDim2.new(1, -32, 0, 22), TextSize = 16, TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 11 })
	ui.resultStats = Hud.text(panel, { Position = UDim2.fromOffset(16, 126), Size = UDim2.new(1, -32, 0, 22), TextSize = 14, TextColor3 = Hud.DIM, TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 11 })
	ui.resultNext = Hud.text(panel, { AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 16, 1, -14), Size = UDim2.new(1, -32, 0, 20), TextSize = 14, TextColor3 = Hud.CYAN, TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 11 })
end

local function chimeraChances(): { [Player]: number }
	local total = 0
	for _, other in Players:GetPlayers() do
		if not other:GetAttribute("MercOnly") then
			total += other:GetAttribute("ChimeraWeight") or 1
		end
	end
	local out = {}
	for _, other in Players:GetPlayers() do
		out[other] = if other:GetAttribute("MercOnly") or total <= 0 then 0 else (other:GetAttribute("ChimeraWeight") or 1) / total
	end
	return out
end

local function updateTopBar(phase: string)
	local now = serverNow()
	local finale = attr("Finale")
	local show = phase == "Deployment" or phase == "Race" or phase == "Finale"
	ui.bar.Visible = show
	if not show then
		return
	end
	if phase == "Deployment" then
		ui.phase.Text = `DEPLOYMENT  {clock(untilEnd())}`
	elseif phase == "Race" then
		local started = attr("RaceStartedAt") or now
		ui.phase.Text = `RACE  {clock(now - started)} / {clock(Config.Match.RaceSeconds)}`
	else
		local prefix = if attr("Lockdown") then "LOCKDOWN · " else ""
		ui.phase.Text = `{prefix}{string.upper(finale or "")} FINALE  {clock(untilEnd())}`
	end
	local threat = attr("Threat") or 1
	ui.threat.Text = `THREAT {threat}`
	ui.threat.TextColor3 = Hud.WHITE:Lerp(Color3.fromRGB(255, 80, 80), (threat - 1) / 3)
	local upload = attr("Upload") or 0
	ui.setUpload(upload)
	ui.uploadLabel.Text = string.format("UPLOAD %d%%", math.floor(upload * 100))

	ui.finaleRow.Visible = finale ~= nil
	ui.terminalRow.Visible = finale == nil
	if finale then
		local held = attr("Hold") or 0
		local holdState = attr("HoldState") or "open"
		local holders = if finale == "Purge" then "MERCS HOLD" else "CHIMERA HOLDS"
		local stateText = if holdState == "holding" then "HOLDING" elseif holdState == "stalled" then "STALLED" else "PLATFORM OPEN"
		ui.finaleLabel.Text = string.format("%s THE PLATFORM  %d / %d s  ·  %s", holders, math.floor(held), Config.Finale.HoldSeconds, stateText)
		ui.finaleFill.Size = UDim2.fromScale(math.clamp(held / Config.Finale.HoldSeconds, 0, 1), 1)
		ui.finaleFill.BackgroundColor3 = if finale == "Purge" then MERC_COLOR else UPLOAD_COLOR
	else
		for _, cell in cells do
			local model = cell.model
			local progress = model:GetAttribute("Progress") or 0
			local locked = (model:GetAttribute("LockedUntil") or 0) > now
			local done = model:GetAttribute("Done") == true
			local operator = model:GetAttribute("Operator")
			local suffix = if done then "✓" elseif locked then "LOCKED" elseif operator then "▶" else ""
			cell.label.Text = string.format("%s %d%% %s", shortName(model), math.floor(progress * 100), suffix)
			cell.setBar(progress)
			cell.fill.BackgroundColor3 = if done then DONE_COLOR elseif locked then LOCK_COLOR elseif operator then BUSY_COLOR else MERC_COLOR
		end
	end
end

local function updatePanels(phase: string)
	local team = player:GetAttribute("Team")
	ui.lobby.Visible = phase == "Lobby"
	ui.loadout.Visible = phase == "Loadout"
	ui.results.Visible = phase == "Results"

	if phase == "Lobby" then
		local waiting = attr("Waiting") == true
		if waiting then
			ui.lobbyStatus.Text = `Waiting for players: {attr("PlayerCount") or 0} of {attr("PlayersNeeded") or Config.Match.MinPlayers}`
		else
			ui.lobbyStatus.Text = `Next round in {math.ceil(math.max(0, untilEnd()))} s`
		end
		local chances = chimeraChances()
		local players = Players:GetPlayers()
		table.sort(players, function(a, b)
			return a.Name < b.Name
		end)
		local lines = {}
		for _, other in players do
			local you = if other == player then "  (you)" else ""
			local note = if other:GetAttribute("MercOnly") then "merc only" else string.format("%d%%", math.round(chances[other] * 100))
			table.insert(lines, `{other.Name}{you}   {note}`)
		end
		ui.lobbyList.Text = table.concat(lines, "\n")
		ui.mercOnly.Text = if player:GetAttribute("MercOnly") then "Merc only: ON" else "Merc only: OFF"
	elseif phase == "Loadout" then
		local left = math.ceil(math.max(0, untilEnd()))
		ui.cards.Visible = team == "Merc"
		ui.build.Visible = team == "Chimera"
		if team == "Merc" then
			ui.loadoutTitle.Text = "PICK YOUR CLASS"
			ui.loadoutStatus.Text = `Deploying in {left} s. You're a merc: reboot {Config.Terminals.ForLockdown} terminals before the Chimera's upload fills.`
			local counts = {}
			for _, other in Players:GetPlayers() do
				local class = other:GetAttribute("Team") == "Merc" and other:GetAttribute("Class")
				if class then
					counts[class] = (counts[class] or 0) + 1
				end
			end
			local mine = player:GetAttribute("Class")
			for class, card in classCards do
				local cap = Config.Classes[class].Cap
				local n = counts[class] or 0
				card.count.Text = `{n} / {cap}`
				card.count.TextColor3 = if n >= cap and mine ~= class then Hud.WARN else Hud.WHITE
				local stroke = card.button:FindFirstChild("Selected") :: UIStroke?
				if stroke then
					stroke.Enabled = mine == class
				end
			end
		elseif team == "Chimera" then
			ui.loadoutTitle.Text = "YOU ARE THE CHIMERA"
			ui.loadoutStatus.Text = `Booting in {left} s. Hunt the mercs to fill your upload before they reboot {Config.Terminals.ForLockdown} terminals. Your build (the default):`
		else
			ui.loadoutTitle.Text = "MATCH STARTING"
			ui.loadoutStatus.Text = "You'll watch this round through the cameras and play the next one."
		end
	elseif phase == "Results" then
		local winner = attr("Winner")
		ui.resultTitle.Text = if winner == "Mercs" then "THE MERCS WIN" elseif winner == "Chimera" then "THE CHIMERA WINS" else "ROUND OVER"
		ui.resultTitle.TextColor3 = if winner == "Mercs" then MERC_COLOR else UPLOAD_COLOR
		local mySide = if team == "Merc" then "Mercs" elseif team == "Chimera" then "Chimera" else nil
		ui.resultYou.Text = if mySide == nil then "" elseif mySide == winner then "VICTORY" else "DEFEAT"
		ui.resultReason.Text = attr("WinReason") or ""
		ui.resultStats.Text = string.format(
			"Match time %s  ·  Upload %d%%  ·  Terminals rebooted %d / %d",
			clock(attr("MatchSeconds") or 0),
			math.floor((attr("Upload") or 0) * 100),
			attr("TerminalsDone") or 0,
			attr("TerminalsNeeded") or Config.Terminals.ForLockdown
		)
		ui.resultNext.Text = `Back to the lobby in {math.ceil(math.max(0, untilEnd()))} s`
	end

	-- Deployment: what your side is doing.
	local role = player:GetAttribute("Role")
	if phase == "Deployment" then
		ui.banner.Visible = true
		local left = math.ceil(math.max(0, untilEnd()))
		ui.banner.Text = if role == "Chimera"
			then `BOOTING INTO THE NETWORK · hop cameras to scout. Interface and shells come online in {left} s`
			elseif role == "Merc" then `DEPLOYING AT THE INSERTION LIFT · the race starts in {left} s`
			else `MATCH STARTING · the race starts in {left} s`
	else
		ui.banner.Visible = false
	end
end

-- No body and no camera of our own: circle the Core.
local function orbit(dt: number)
	if player:GetAttribute("Role") ~= "Lobby" then
		return
	end
	orbitAngle += dt * 0.08
	local camera = workspace.CurrentCamera
	camera.CameraType = Enum.CameraType.Scriptable
	camera.FieldOfView = 70
	-- Inside the Core's walls (±60) at every angle.
	local center = Vector3.new(0, 6, 0)
	local eye = center + Vector3.new(math.cos(orbitAngle) * 50, 24, math.sin(orbitAngle) * 50)
	camera.CFrame = CFrame.lookAt(eye, center)
end

local function reportActivity()
	local now = os.clock()
	if lastInputAt > lastReportAt and now - lastReportAt >= Config.Match.ActivityReportSeconds then
		lastReportAt = now
		actionRemote:FireServer("active")
	end
end

function MatchHud.init()
	state = ReplicatedStorage:WaitForChild("MatchState") :: Configuration
	actionRemote = Net.get("MatchAction")
	local gui = Hud.gui()
	buildTopBar(gui)
	buildLobby(gui)
	buildLoadout(gui)
	buildResults(gui)
	ui.banner = Hud.text(gui, {
		Name = "Banner",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 110),
		Size = UDim2.fromOffset(760, 26),
		TextSize = 17,
		FontFace = Hud.FONT_BOLD,
		TextXAlignment = Enum.TextXAlignment.Center,
		BackgroundTransparency = 0.45,
		BackgroundColor3 = Hud.PANEL,
		Visible = false,
	})

	Net.get("MatchFeed").OnClientEvent:Connect(function(kind, text)
		if kind == "notice" and type(text) == "string" then
			Hud.toast(text, Hud.CYAN)
		end
	end)

	UserInputService.InputBegan:Connect(function()
		lastInputAt = os.clock()
	end)
	UserInputService.InputChanged:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseMovement then
			lastInputAt = os.clock()
		end
	end)

	local accumulator = 0
	RunService.Heartbeat:Connect(function(dt)
		accumulator += dt
		if accumulator < 0.1 then
			return
		end
		accumulator = 0
		local phase = attr("Phase") or "Lobby"
		updateTopBar(phase)
		updatePanels(phase)
		reportActivity()
	end)
	RunService:BindToRenderStep("MatchOrbit", Enum.RenderPriority.Camera.Value + 2, orbit)
end

function MatchHud.describe(): { [string]: any }
	return {
		phase = attr("Phase"),
		bar = ui.bar and ui.bar.Visible and ui.phase.Text or nil,
		upload = ui.uploadLabel and ui.uploadLabel.Text,
		threat = ui.threat and ui.threat.Text,
		finale = ui.finaleRow and ui.finaleRow.Visible and ui.finaleLabel.Text or nil,
		terminals = (function()
			local out = {}
			for _, cell in cells do
				table.insert(out, cell.label.Text)
			end
			return out
		end)(),
		lobby = ui.lobby and ui.lobby.Visible and ui.lobbyStatus.Text or nil,
		loadout = ui.loadout and ui.loadout.Visible and ui.loadoutTitle.Text or nil,
		results = ui.results and ui.results.Visible and (ui.resultTitle.Text .. " · " .. ui.resultReason.Text) or nil,
		banner = ui.banner and ui.banner.Visible and ui.banner.Text or nil,
	}
end

return MatchHud
