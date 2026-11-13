-- An eliminated merc watches through the facility cameras (basic; full Overwatch with pings and tags is
-- milestone 3). The server sends the shell to them only when the camera they watch can see it. The
-- camera the Chimera is in crackles with static; a shot-out camera shows SIGNAL LOST.
--   A/D or ←/→ switch cameras, right-drag to look.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local CameraMath = require(ReplicatedStorage.Shared.CameraMath)
local FacilityMap = require(ReplicatedStorage.Shared.FacilityMap)
local Net = require(ReplicatedStorage.Shared.Net)
local Hud = require(script.Parent.Hud)

local Spectate = {}

local player = Players.LocalPlayer
local running = false
local order: { string } = {}
local cameras: { [string]: FacilityMap.CameraInfo } = {}
local index = 1
local yawOffset, pitchOffset = 0, 0
local dragging = false
local connections: { RBXScriptConnection } = {}
local ui: { [string]: any } = {}
local actionRemote: RemoteEvent

local function current(): FacilityMap.CameraInfo?
	return cameras[order[index]]
end

local function switchCamera(step: number)
	index = (index - 1 + step) % #order + 1
	yawOffset, pitchOffset = 0, 0
	actionRemote:FireServer("spectate", order[index])
end

local function render(dt: number)
	local info = current()
	if not info then
		return
	end
	if dragging then
		local delta = UserInputService:GetMouseDelta()
		yawOffset = math.clamp(yawOffset - math.rad(delta.X * 0.25), -math.rad(info.panLimit), math.rad(info.panLimit))
		pitchOffset = math.clamp(pitchOffset - math.rad(delta.Y * 0.25), -math.rad(info.tiltLimit), math.rad(info.tiltLimit))
	end
	local camera = workspace.CurrentCamera
	camera.CameraType = Enum.CameraType.Scriptable
	camera.FieldOfView = 70
	camera.CFrame = CameraMath.viewCFrame(info.origin, info.baseYaw + yawOffset, info.basePitch + pitchOffset)

	local brokenUntil = info.model:GetAttribute("BrokenUntil")
	local broken = type(brokenUntil) == "number" and brokenUntil > workspace:GetServerTimeNow()
	local rec = info.recLight
	local watched = rec ~= nil and rec.Material == Enum.Material.Neon
	ui.label.Text = `ELIMINATED · OVERWATCH (basic)   CAM {index}/{#order}  {string.upper(info.displayName)}`
	ui.static.Visible = broken or watched
	if broken then
		ui.static.BackgroundTransparency = 0.05
		ui.staticLabel.Text = "SIGNAL LOST"
	elseif watched then
		ui.static.BackgroundTransparency = 0.55 + math.random() * 0.3
		ui.staticLabel.Text = ""
	end
end

function Spectate.init()
	actionRemote = Net.get("MercAction")
	cameras = FacilityMap.cameras()
	for id in cameras do
		table.insert(order, id)
	end
	table.sort(order)
end

function Spectate.start()
	if running then
		return
	end
	running = true
	local gui = Hud.gui()
	ui.label = Hud.text(gui, { Name = "SpectateLabel", Position = UDim2.fromOffset(40, 36), Size = UDim2.fromOffset(800, 24), TextSize = 18, ZIndex = 8 })
	ui.static = Hud.frame(gui, { Name = "SpectateStatic", Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.fromRGB(70, 74, 78), Visible = false, ZIndex = 5 })
	ui.staticLabel = Hud.text(ui.static, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(400, 40), TextSize = 26, TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 6 })
	ui.hints = Hud.hints({ "A/D or ←/→  switch camera", "Right-drag  look" })
	UserInputService.MouseBehavior = Enum.MouseBehavior.Default
	UserInputService.MouseIconEnabled = true
	table.insert(connections, UserInputService.InputBegan:Connect(function(input, processed)
		if input.UserInputType == Enum.UserInputType.MouseButton2 then
			dragging = true
			UserInputService.MouseBehavior = Enum.MouseBehavior.LockCurrentPosition
		elseif not processed and (input.KeyCode == Enum.KeyCode.D or input.KeyCode == Enum.KeyCode.Right) then
			switchCamera(1)
		elseif not processed and (input.KeyCode == Enum.KeyCode.A or input.KeyCode == Enum.KeyCode.Left) then
			switchCamera(-1)
		end
	end))
	table.insert(connections, UserInputService.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton2 then
			dragging = false
			UserInputService.MouseBehavior = Enum.MouseBehavior.Default
		end
	end))
	RunService:BindToRenderStep("Spectate", Enum.RenderPriority.Camera.Value + 1, render)
	switchCamera(0)
end

function Spectate.stop()
	if not running then
		return
	end
	running = false
	RunService:UnbindFromRenderStep("Spectate")
	for _, connection in connections do
		connection:Disconnect()
	end
	table.clear(connections)
	for _, key in { "label", "static", "hints" } do
		if ui[key] then
			ui[key]:Destroy()
		end
	end
	table.clear(ui)
	UserInputService.MouseBehavior = Enum.MouseBehavior.Default
	workspace.CurrentCamera.CameraType = Enum.CameraType.Custom
end

function Spectate.describe(): { [string]: any }
	return { running = running, camera = order[index] }
end

return Spectate
