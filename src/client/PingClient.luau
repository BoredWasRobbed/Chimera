-- Pings on a merc's screen, and the merc ping wheel.
--   Z or middle mouse: tap to ping where you aim; hold for the wheel, move the mouse toward an entry and
--   release to send it (release in the middle to cancel).
-- Every ping shows the sender's name. Real pings carry a radio voice line, shown as 📻; a fake one from
-- Corrupt Data has none, which is the tell. Every merc client draws pings (living or on Overwatch, from
-- whatever camera it's using); only a living merc's client runs the wheel.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Config = require(ReplicatedStorage.Shared.Config)
local Net = require(ReplicatedStorage.Shared.Net)
local Hud = require(script.Parent.Hud)
local MercCombat = require(script.Parent.MercCombat)

local PingClient = {}

local P = Config.Pings
local RADIO = "📻"
local COLORS = {
	Ping = Color3.fromRGB(235, 240, 245),
	Chimera = Color3.fromRGB(255, 80, 80),
	Going = Color3.fromRGB(110, 210, 255),
	Terminal = Color3.fromRGB(90, 255, 140),
	Revive = Color3.fromRGB(255, 160, 60),
	Battery = Color3.fromRGB(255, 230, 110),
	Door = Color3.fromRGB(200, 140, 255),
	Overwatch = Color3.fromRGB(150, 200, 255),
}
local ICONS = {
	Ping = "●",
	Chimera = "⚠",
	Going = "»",
	Terminal = "▣",
	Revive = "✚",
	Battery = "🔋",
	Door = "👁",
	Overwatch = "◉",
}

type Active = { position: Vector3, expiresAt: number, marker: TextLabel }

local actionRemote: RemoteEvent
local layer: Frame
local feed: Frame
local wheelFrame: Frame
local wheelLabels: { TextLabel } = {}
local active: { Active } = {}
local received: { { [string]: any } } = {}
local wheelEnabled = false
local pressing = false
local pressAt = 0
local wheelOpen = false
local selection = Vector2.zero
local selected: number? = nil
local connections: { RBXScriptConnection } = {}

local function labelOf(kind: string): string
	return P.Labels[kind] or kind
end

local function addFeedLine(text: string, color: Color3)
	local line = Hud.text(feed, {
		Text = text,
		TextColor3 = color,
		TextSize = 15,
		Size = UDim2.new(1, 0, 0, 20),
		BackgroundTransparency = 0.5,
		BackgroundColor3 = Hud.PANEL,
		LayoutOrder = math.floor(os.clock() * 100),
	})
	local lines = {}
	for _, child in feed:GetChildren() do
		if child:IsA("TextLabel") then
			table.insert(lines, child)
		end
	end
	if #lines > 6 then
		table.sort(lines, function(a, b)
			return a.LayoutOrder < b.LayoutOrder
		end)
		lines[1]:Destroy()
	end
	task.delay(P.Seconds, function()
		line:Destroy()
	end)
end

local function onPing(ping: { [string]: any })
	if type(ping) ~= "table" or type(ping.kind) ~= "string" then
		return
	end
	table.insert(received, ping)
	if #received > 20 then
		table.remove(received, 1)
	end
	local kind = ping.kind
	local color = COLORS[kind] or COLORS.Ping
	local voice = if ping.voice then ` {RADIO}` else ""
	local position = Vector3.new(ping.x, ping.y, ping.z)
	local marker = Hud.text(layer, {
		Text = `{ICONS[kind] or "●"} {string.upper(labelOf(kind))}\n{ping.from}{voice}`,
		TextColor3 = color,
		TextSize = 14,
		Font = Enum.Font.GothamBold,
		AnchorPoint = Vector2.new(0.5, 1),
		Size = UDim2.fromOffset(190, 36),
		TextXAlignment = Enum.TextXAlignment.Center,
		TextStrokeTransparency = 0.3,
		Visible = false,
	})
	table.insert(active, { position = position, expiresAt = os.clock() + P.Seconds, marker = marker })
	local said = if kind == "Ping" then "Ping" elseif kind == "Overwatch" then "Overwatch ping" else labelOf(kind)
	addFeedLine(`{if ping.voice then RADIO .. " " else ""}{ping.from}: {said}`, color)
end

-- Draw each ping where it is in the world, held to the screen's edge when it's off screen.
local function render()
	local camera = workspace.CurrentCamera
	local viewport = camera.ViewportSize
	local now = os.clock()
	for i = #active, 1, -1 do
		local ping = active[i]
		if now >= ping.expiresAt then
			ping.marker:Destroy()
			table.remove(active, i)
			continue
		end
		local point, onScreen = camera:WorldToViewportPoint(ping.position + Vector3.new(0, 1, 0))
		local x, y = point.X, point.Y
		if point.Z < 0 then
			x, y = viewport.X - x, viewport.Y - y
			onScreen = false
		end
		if not onScreen then
			x = math.clamp(x, 100, viewport.X - 100)
			y = math.clamp(y, 60, viewport.Y - 20)
		end
		ping.marker.Position = UDim2.fromOffset(x, y)
		ping.marker.TextTransparency = if ping.expiresAt - now < 1 then 1 - (ping.expiresAt - now) else 0
		ping.marker.Visible = true
	end

	if wheelEnabled and pressing then
		if not wheelOpen and now - pressAt >= P.WheelHoldSeconds then
			wheelOpen = true
			selection = Vector2.zero
			selected = nil
			wheelFrame.Visible = true
			MercCombat.setLookFrozen(true)
		end
		if wheelOpen then
			local delta = UserInputService:GetMouseDelta()
			selection += Vector2.new(delta.X, delta.Y)
			if selection.Magnitude > 120 then
				selection = selection.Unit * 120
			end
			selected = nil
			if selection.Magnitude > 25 then
				-- Entries sit clockwise from the top, 60° apart.
				local angle = math.deg(math.atan2(selection.Y, selection.X)) + 90
				selected = math.round(((angle % 360) / 360) * #P.Wheel) % #P.Wheel + 1
			end
			for index, label in wheelLabels do
				local on = index == selected
				label.BackgroundTransparency = if on then 0.1 else 0.45
				label.TextColor3 = if on then COLORS[P.Wheel[index]] or Hud.WHITE else Hud.DIM
			end
		end
	end
end

local function send(kind: string)
	actionRemote:FireServer("ping", kind, MercCombat.aimPoint())
end

local function closeWheel()
	wheelOpen = false
	wheelFrame.Visible = false
	MercCombat.setLookFrozen(false)
end

local function isPingInput(input: InputObject): boolean
	return input.KeyCode == Enum.KeyCode.Z or input.UserInputType == Enum.UserInputType.MouseButton3
end

function PingClient.startWheel()
	if wheelEnabled then
		return
	end
	wheelEnabled = true
	table.insert(connections, UserInputService.InputBegan:Connect(function(input, processed)
		if not processed and isPingInput(input) and not pressing then
			pressing = true
			pressAt = os.clock()
		end
	end))
	table.insert(connections, UserInputService.InputEnded:Connect(function(input)
		if not isPingInput(input) or not pressing then
			return
		end
		pressing = false
		if wheelOpen then
			local choice = selected
			closeWheel()
			if choice then
				send(P.Wheel[choice])
			end
		else
			send("Ping")
		end
	end))
end

function PingClient.stopWheel()
	if not wheelEnabled then
		return
	end
	wheelEnabled = false
	pressing = false
	if wheelOpen then
		closeWheel()
	end
	for _, connection in connections do
		connection:Disconnect()
	end
	table.clear(connections)
end

-- Studio tests: send a ping (or a wheel entry) as if from the wheel.
function PingClient.testPing(kind: string)
	send(kind)
end

function PingClient.describe(): { [string]: any }
	local feedText = {}
	for _, child in feed:GetChildren() do
		if child:IsA("TextLabel") then
			table.insert(feedText, child.Text)
		end
	end
	return { wheel = wheelEnabled, wheelOpen = wheelOpen, markers = #active, feed = feedText, received = received }
end

function PingClient.init()
	actionRemote = Net.get("MatchAction")
	local gui = Hud.gui()
	layer = Hud.frame(gui, { Name = "Pings", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, ZIndex = 3 })
	feed = Hud.frame(gui, { Name = "PingFeed", Position = UDim2.fromOffset(16, 170), Size = UDim2.fromOffset(380, 150), BackgroundTransparency = 1 })
	local layout = Instance.new("UIListLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, 2)
	layout.Parent = feed

	wheelFrame = Hud.frame(gui, { Name = "PingWheel", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(320, 320), BackgroundTransparency = 1, Visible = false, ZIndex = 30 })
	Hud.text(wheelFrame, { Text = "release to ping\n(center: cancel)", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(140, 40), TextSize = 13, TextColor3 = Hud.DIM, TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 31 })
	for index, kind in P.Wheel do
		local angle = math.rad(-90 + (index - 1) * 360 / #P.Wheel)
		table.insert(wheelLabels, Hud.text(wheelFrame, {
			Text = `{ICONS[kind] or ""} {labelOf(kind)}`,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(0.5, math.cos(angle) * 115, 0.5, math.sin(angle) * 115),
			Size = UDim2.fromOffset(150, 30),
			TextSize = 15,
			Font = Enum.Font.GothamBold,
			TextXAlignment = Enum.TextXAlignment.Center,
			BackgroundTransparency = 0.45,
			BackgroundColor3 = Hud.PANEL,
			TextColor3 = Hud.DIM,
			ZIndex = 31,
		}))
	end

	Net.get("MatchFeed").OnClientEvent:Connect(function(kind, data)
		if kind == "ping" then
			onPing(data)
		end
	end)
	RunService.RenderStepped:Connect(render)
end

return PingClient
