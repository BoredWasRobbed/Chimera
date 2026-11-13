-- Studio-only DEV panel and test hook, so one tester can exercise both sides alone.
--   Combat: switch role, a test shell that patrols or hunts, its visibility, the perception overlay, a
--   dummy merc to down and assimilate, class, down yourself, respawn.
--   Match: skip the phase, +60 s on the clock, +10% upload, force either finale, +10 s held, and the
--   Studio rules (a round starts with 1 player; idle players aren't kicked).
-- ReplicatedStorage.ChimeraClientHook (BindableFunction, this client only) returns JSON client state.
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Net = require(ReplicatedStorage.Shared.Net)
local Hud = require(script.Parent.Hud)

local DebugPanel = {}

local player = Players.LocalPlayer

local COLUMNS = {
	{
		title = "Combat",
		buttons = {
			{ "SwitchRole", "Switch role", "switchRole" },
			{ "ToggleBot", "Test shell on/off", "toggleBot" },
			{ "BotHunt", "Test shell hunts/patrols", "botHunt" },
			{ "CycleVisibility", "Cycle visibility", "cycleVisibility" },
			{ "Overlay", "Perception overlay", "overlay" },
			{ "SpawnDummy", "Spawn dummy merc", "spawnDummy" },
			{ "CycleClass", "Cycle class", "cycleClass" },
			{ "DownMe", "Down me", "downMe" },
			{ "Respawn", "Respawn me", "respawn" },
		},
	},
	{
		title = "Match",
		buttons = {
			{ "SkipPhase", "Skip phase", "skipPhase" },
			{ "AddTime", "Clock +60 s", "addTime" },
			{ "Upload", "Upload +10%", "upload" },
			{ "ForcePurge", "Force Purge finale", "forcePurge" },
			{ "ForceUpload", "Force Upload finale", "forceUpload" },
			{ "Hold", "Finale: held +10 s", "hold" },
			{ "MinPlayers", "Min players", "minPlayers" },
			{ "Afk", "Idle kicks", "afk" },
		},
	},
}

local COLUMN_WIDTH = 200

function DebugPanel.init(describe: () -> { [string]: any }, commands: { [string]: (...any) -> any })
	local remote = Net.get("Debug")
	local gui = Hud.gui()
	local overlayOn = false
	local open = false

	local rows = 0
	for _, column in COLUMNS do
		rows = math.max(rows, #column.buttons)
	end
	local width = COLUMN_WIDTH * #COLUMNS + 8
	local panel = Hud.frame(gui, {
		Name = "DevPanel",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -16, 0, 100),
		Size = UDim2.fromOffset(width, 26 + rows * 32),
		BackgroundTransparency = 0.4,
		Visible = false,
		ZIndex = 40,
	})
	local toggle = Hud.button(gui, {
		Name = "DevToggle",
		Text = "DEV ▾",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -16, 0, 72),
		Size = UDim2.fromOffset(80, 24),
		TextSize = 13,
		ZIndex = 41,
	})
	toggle.Activated:Connect(function()
		open = not open
		panel.Visible = open
		toggle.Text = if open then "DEV ▴" else "DEV ▾"
	end)
	local overlay = Hud.text(gui, {
		Name = "PerceptionOverlay",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -26 - width, 0, 100),
		Size = UDim2.fromOffset(340, 100),
		TextSize = 14,
		TextYAlignment = Enum.TextYAlignment.Top,
		TextXAlignment = Enum.TextXAlignment.Right,
		Visible = false,
		ZIndex = 40,
	})

	local studioButtons: { [string]: TextButton } = {}
	for columnIndex, column in COLUMNS do
		local x = 8 + (columnIndex - 1) * COLUMN_WIDTH
		Hud.text(panel, {
			Text = `{column.title} · Studio only`,
			TextSize = 13,
			TextColor3 = Hud.DIM,
			Position = UDim2.fromOffset(x, 4),
			Size = UDim2.fromOffset(COLUMN_WIDTH - 8, 18),
			ZIndex = 41,
		})
		for index, def in column.buttons do
			local button = Hud.button(panel, {
				Name = def[1],
				Text = def[2],
				Position = UDim2.fromOffset(x, 24 + (index - 1) * 32),
				Size = UDim2.fromOffset(COLUMN_WIDTH - 8, 28),
				TextSize = 14,
				ZIndex = 41,
			})
			if def[3] == "minPlayers" or def[3] == "afk" then
				studioButtons[def[3]] = button
			end
			button.Activated:Connect(function()
				if def[3] == "overlay" then
					overlayOn = not overlayOn
					overlay.Visible = overlayOn
					remote:FireServer("overlay", overlayOn)
				else
					remote:FireServer(def[3])
				end
			end)
		end
	end

	-- The Studio rules' buttons show what's in force.
	local state = ReplicatedStorage:WaitForChild("MatchState")
	local function showStudioRules()
		local solo = state:GetAttribute("StudioMinPlayers") == true
		local afk = state:GetAttribute("StudioAfk") == true
		studioButtons.minPlayers.Text = if solo then "Min players: 1 (Studio)" else "Min players: 4 (real)"
		studioButtons.afk.Text = if afk then "Idle kicks: on (real)" else "Idle kicks: off (Studio)"
	end
	state:GetAttributeChangedSignal("StudioMinPlayers"):Connect(showStudioRules)
	state:GetAttributeChangedSignal("StudioAfk"):Connect(showStudioRules)
	showStudioRules()

	remote.OnClientEvent:Connect(function(kind, value)
		if kind == "message" then
			Hud.toast(tostring(value), Hud.CYAN)
		elseif kind == "perception" and overlayOn and type(value) == "table" then
			local lines = {}
			for id, entry in value do
				table.insert(lines, `{id}: {if entry[1] then "SEEN" else "unseen"} · {entry[2]}`)
			end
			table.sort(lines)
			overlay.Text = if #lines > 0 then table.concat(lines, "\n") else "no active shells"
		end
	end)

	local hook = Instance.new("BindableFunction")
	hook.Name = "ChimeraClientHook"
	hook.OnInvoke = function(command, ...)
		local handler = if command == nil or command == "describe" then describe else commands[command]
		if not handler then
			return HttpService:JSONEncode({ error = `unknown command {command}` })
		end
		local ok, result = pcall(handler, ...)
		if not ok then
			result = { error = tostring(result) }
		elseif type(result) ~= "table" then
			result = { result = result }
		end
		result.player = player.Name
		return HttpService:JSONEncode(result)
	end
	hook.Parent = ReplicatedStorage
end

return DebugPanel
