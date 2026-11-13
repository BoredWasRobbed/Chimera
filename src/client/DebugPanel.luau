-- Studio-only DEV panel and test hook. Lets one tester switch roles, spawn a patrolling test shell,
-- cycle its visibility state and watch what the server decides this merc perceives.
-- ReplicatedStorage.ChimeraClientHook (BindableFunction, this client only) returns JSON client state.
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Net = require(ReplicatedStorage.Shared.Net)
local Hud = require(script.Parent.Hud)

local DebugPanel = {}

local player = Players.LocalPlayer

function DebugPanel.init(describe: () -> { [string]: any }, commands: { [string]: (...any) -> any })
	local remote = Net.get("Debug")
	local gui = Hud.gui()
	local overlayOn = false

	local panel = Hud.frame(gui, {
		Name = "DevPanel",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -16, 0, 120),
		Size = UDim2.fromOffset(200, 176),
		BackgroundTransparency = 0.4,
		ZIndex = 40,
	})
	Hud.text(panel, {
		Text = "DEV (Studio only)",
		TextSize = 14,
		TextColor3 = Hud.DIM,
		Position = UDim2.fromOffset(8, 4),
		Size = UDim2.new(1, -16, 0, 18),
		ZIndex = 41,
	})
	local overlay = Hud.text(gui, {
		Name = "PerceptionOverlay",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -16, 0, 304),
		Size = UDim2.fromOffset(320, 120),
		TextSize = 14,
		TextYAlignment = Enum.TextYAlignment.Top,
		TextXAlignment = Enum.TextXAlignment.Right,
		Visible = false,
		ZIndex = 40,
	})

	local buttons = {
		{ "SwitchRole", "Switch role", function()
			remote:FireServer("switchRole")
		end },
		{ "ToggleBot", "Test shell on/off", function()
			remote:FireServer("toggleBot")
		end },
		{ "CycleVisibility", "Cycle visibility", function()
			remote:FireServer("cycleVisibility")
		end },
		{ "Overlay", "Perception overlay", function()
			overlayOn = not overlayOn
			overlay.Visible = overlayOn
			remote:FireServer("overlay", overlayOn)
		end },
	}
	for index, def in buttons do
		local button = Hud.button(panel, {
			Name = def[1],
			Text = def[2],
			Position = UDim2.fromOffset(8, 26 + (index - 1) * 36),
			Size = UDim2.new(1, -16, 0, 30),
			ZIndex = 41,
		})
		button.Activated:Connect(def[3])
	end

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
