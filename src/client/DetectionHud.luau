-- The motion tracker and heartbeat, as the server reports them: a strength (1-4, 4 nearest) and one of
-- eight directions for the tracker, an intensity (1-3) for the heartbeat. Never a position.
-- Tracker sectors count counter-clockwise from straight ahead: 0 ahead, 2 left, 4 behind, 6 right.
-- Held (T), the tracker shows a blip on its screen; holstered, you only get the ping.
-- Sounds are placeholders: the pulses are visual until the audio pass.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Net = require(ReplicatedStorage.Shared.Net)
local Hud = require(script.Parent.Hud)

local DetectionHud = {}

local running = false
local held = false
local tracker = { strength = 0, sector = 0, at = 0 }
local heartbeat = { intensity = 0, at = 0 }
local ui: { [string]: any } = {}
local connection: RBXScriptConnection? = nil
local nextBeatAt = 0

function DetectionHud.isHeld(): boolean
	return held
end

function DetectionHud.setHeld(on: boolean)
	held = on
	if ui.screen then
		ui.screen.Visible = on
	end
end

local function ping()
	if not ui.ping then
		return
	end
	ui.ping.TextTransparency = 0
	ui.ping.Text = string.rep("•", tracker.strength) .. "  ping"
	TweenService:Create(ui.ping, TweenInfo.new(0.45), { TextTransparency = 1 }):Play()
	if held and ui.blip then
		local angle = tracker.sector * (math.pi / 4)
		local radius = (5 - tracker.strength) / 4 * 0.42
		ui.blip.Position = UDim2.fromScale(0.5 - math.sin(angle) * radius, 0.5 - math.cos(angle) * radius)
		ui.blip.BackgroundTransparency = 0
		TweenService:Create(ui.blip, TweenInfo.new(0.5), { BackgroundTransparency = 1 }):Play()
	end
end

local function render()
	if not running then
		return
	end
	local now = os.clock()
	if heartbeat.intensity > 0 and now - heartbeat.at < 1.2 then
		if now >= nextBeatAt then
			nextBeatAt = now + (1.1 - heartbeat.intensity * 0.25)
			ui.heart.TextTransparency = 0
			ui.heart.TextSize = 26 + heartbeat.intensity * 4
			TweenService:Create(ui.heart, TweenInfo.new(0.35), { TextTransparency = 0.85, TextSize = 24 }):Play()
			ui.vignette.BackgroundTransparency = 0.95 - heartbeat.intensity * 0.08
			TweenService:Create(ui.vignette, TweenInfo.new(0.4), { BackgroundTransparency = 1 }):Play()
		end
	else
		ui.heart.TextTransparency = 1
	end
end

local function build()
	local gui = Hud.gui()
	ui.vignette = Hud.frame(gui, { Name = "HeartVignette", Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.fromRGB(200, 205, 215), BackgroundTransparency = 1, ZIndex = 1 })
	ui.heart = Hud.text(gui, { Name = "Heartbeat", Text = "♥", AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(0.5, -165, 0, 14), Size = UDim2.fromOffset(40, 40), TextSize = 24, TextColor3 = Color3.fromRGB(235, 235, 240), TextXAlignment = Enum.TextXAlignment.Center, TextTransparency = 1 })
	ui.ping = Hud.text(gui, { Name = "TrackerPing", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0.5, 18), Size = UDim2.fromOffset(160, 18), TextSize = 14, TextColor3 = Color3.fromRGB(170, 255, 200), TextXAlignment = Enum.TextXAlignment.Center, TextTransparency = 1 })
	local screen = Hud.frame(gui, { Name = "TrackerScreen", AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, -220, 1, -40), Size = UDim2.fromOffset(150, 150), BackgroundColor3 = Color3.fromRGB(8, 20, 14), BackgroundTransparency = 0.15, Visible = held })
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.5, 0)
	corner.Parent = screen
	for _, scale in { 0.33, 0.66 } do
		local ring = Hud.frame(screen, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromScale(scale, scale), BackgroundTransparency = 1 })
		local stroke = Instance.new("UIStroke")
		stroke.Color = Color3.fromRGB(60, 140, 90)
		stroke.Transparency = 0.3
		stroke.Parent = ring
		local c = Instance.new("UICorner")
		c.CornerRadius = UDim.new(0.5, 0)
		c.Parent = ring
	end
	Hud.text(screen, { Text = "▲", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromScale(0.5, 0.02), Size = UDim2.fromOffset(20, 16), TextSize = 12, TextColor3 = Color3.fromRGB(90, 200, 130), TextXAlignment = Enum.TextXAlignment.Center })
	local blip = Hud.frame(screen, { Name = "Blip", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(14, 14), BackgroundColor3 = Color3.fromRGB(170, 255, 200), BackgroundTransparency = 1 })
	local blipCorner = Instance.new("UICorner")
	blipCorner.CornerRadius = UDim.new(0.5, 0)
	blipCorner.Parent = blip
	ui.screen, ui.blip = screen, blip
end

function DetectionHud.init()
	Net.get("MercEvents").OnClientEvent:Connect(function(kind, a, b)
		if kind == "tracker" and type(a) == "number" then
			tracker.strength, tracker.sector, tracker.at = a, tonumber(b) or 0, os.clock()
			if running and a > 0 then
				ping()
			end
		elseif kind == "heartbeat" and type(a) == "number" then
			heartbeat.intensity, heartbeat.at = a, os.clock()
		end
	end)
end

function DetectionHud.start()
	if running then
		return
	end
	running = true
	build()
	connection = RunService.RenderStepped:Connect(render)
end

function DetectionHud.stop()
	running = false
	held = false
	if connection then
		connection:Disconnect()
		connection = nil
	end
	for _, key in { "vignette", "heart", "ping", "screen" } do
		if ui[key] then
			ui[key]:Destroy()
		end
	end
	table.clear(ui)
end

function DetectionHud.describe(): { [string]: any }
	return { held = held, tracker = { tracker.strength, tracker.sector, math.floor((os.clock() - tracker.at) * 10) / 10 }, heartbeat = heartbeat.intensity }
end

return DetectionHud
