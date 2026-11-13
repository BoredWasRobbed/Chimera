-- Watching through the facility cameras: Overwatch for eliminated mercs, and a plain camera view for
-- spectators (players who joined mid-match or were sent to the lobby for idling).
--   Any camera: click it in the list, or A/D (←/→) to step through them. Right-drag to look.
--   Overwatch only: click the view to ping that spot for the living mercs (3 charges, one back every
--   20 s); F tags the Chimera if it's Exposed or Revealed on your camera (outlined for 3 s, 30 s cooldown).
-- The server sends the shell only when the watched camera can see it. The camera the Chimera is in
-- crackles with static; a shot-out camera shows SIGNAL LOST.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local CameraMath = require(ReplicatedStorage.Shared.CameraMath)
local Config = require(ReplicatedStorage.Shared.Config)
local FacilityMap = require(ReplicatedStorage.Shared.FacilityMap)
local Net = require(ReplicatedStorage.Shared.Net)
local Hud = require(script.Parent.Hud)

local Spectate = {}

local player = Players.LocalPlayer
local running = false
local overwatch = false
local order: { string } = {}
local cameras: { [string]: FacilityMap.CameraInfo } = {}
local index = 1
local yawOffset, pitchOffset = 0, 0
local dragging = false
local connections: { RBXScriptConnection } = {}
local ui: { [string]: any } = {}
local listButtons: { [string]: TextButton } = {}
local actionRemote: RemoteEvent
local rayParams = RaycastParams.new()

local function current(): FacilityMap.CameraInfo?
	return cameras[order[index]]
end

local function selectCamera(newIndex: number)
	index = (newIndex - 1) % #order + 1
	yawOffset, pitchOffset = 0, 0
	actionRemote:FireServer("spectate", order[index])
end

local function serverNow(): number
	return workspace:GetServerTimeNow()
end

local function overwatchStatus(): string
	local charges = player:GetAttribute("PingCharges") or Config.Pings.OverwatchCharges
	local dots = string.rep("●", charges) .. string.rep("○", Config.Pings.OverwatchCharges - charges)
	local recharge = player:GetAttribute("PingRechargeAt") or 0
	local nextIn = if charges < Config.Pings.OverwatchCharges and recharge > 0 then string.format(" +1 in %d s", math.ceil(math.max(0, recharge - serverNow()))) else ""
	local tagAt = player:GetAttribute("TagReadyAt") or 0
	local tag = if tagAt > serverNow() then string.format("TAG in %d s", math.ceil(tagAt - serverNow())) else "TAG ready (F)"
	return `PING {dots}{nextIn}   ·   {tag}`
end

local function render(_dt: number)
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
	local broken = type(brokenUntil) == "number" and brokenUntil > serverNow()
	local rec = info.recLight
	local watched = rec ~= nil and rec.Material == Enum.Material.Neon
	-- Short lines on the left, clear of the match bar at the top centre.
	ui.label.Text = `{if overwatch then "OVERWATCH" else "SPECTATING"}   CAM {index}/{#order}`
	ui.camName.Text = string.upper(info.displayName)
	ui.static.Visible = broken or watched
	if broken then
		ui.static.BackgroundTransparency = 0.05
		ui.staticLabel.Text = "SIGNAL LOST"
	elseif watched then
		ui.static.BackgroundTransparency = 0.55 + math.random() * 0.3
		ui.staticLabel.Text = ""
	end
	ui.status.Text = if overwatch then overwatchStatus() else "You'll play the next round"
	for id, button in listButtons do
		button.BackgroundTransparency = if id == order[index] then 0.05 else 0.4
	end
end

-- Overwatch Ping: the spot under the mouse, seen from this camera.
local function pingUnderMouse()
	local camera = workspace.CurrentCamera
	local mouse = UserInputService:GetMouseLocation()
	local ray = camera:ViewportPointToRay(mouse.X, mouse.Y)
	local hit = workspace:Raycast(ray.Origin, ray.Direction * Config.Interface.CameraRange, rayParams)
	if hit then
		actionRemote:FireServer("owPing", hit.Position)
	end
end

function Spectate.init()
	actionRemote = Net.get("MatchAction")
	cameras = FacilityMap.cameras()
	for id in cameras do
		table.insert(order, id)
	end
	table.sort(order)
	rayParams.FilterType = Enum.RaycastFilterType.Include
	rayParams.FilterDescendantsInstances = { workspace:WaitForChild("Map") }
end

function Spectate.start()
	if running then
		return
	end
	running = true
	overwatch = player:GetAttribute("Role") == "Merc" and player:GetAttribute("Eliminated") == true
	local gui = Hud.gui()
	ui.label = Hud.text(gui, { Name = "SpectateLabel", Position = UDim2.fromOffset(40, 36), Size = UDim2.fromOffset(300, 24), TextSize = 18, ZIndex = 8 })
	ui.camName = Hud.text(gui, { Name = "SpectateCamera", Position = UDim2.fromOffset(40, 60), Size = UDim2.fromOffset(300, 22), TextSize = 16, ZIndex = 8 })
	ui.status = Hud.text(gui, { Name = "SpectateStatus", Position = UDim2.fromOffset(40, 84), Size = UDim2.fromOffset(330, 22), TextSize = 15, TextColor3 = Hud.CYAN, ZIndex = 8 })
	ui.static = Hud.frame(gui, { Name = "SpectateStatic", Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.fromRGB(70, 74, 78), Visible = false, ZIndex = 5 })
	ui.staticLabel = Hud.text(ui.static, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(400, 40), TextSize = 26, TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 6 })

	-- Every camera, two columns, bottom right.
	local rows = math.ceil(#order / 2)
	local list = Hud.frame(gui, { Name = "CameraList", AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -16, 1, -16), Size = UDim2.fromOffset(372, 28 + rows * 26), BackgroundTransparency = 0.45, ZIndex = 8 })
	ui.list = list
	Hud.text(list, { Text = "CAMERAS", Position = UDim2.fromOffset(8, 4), Size = UDim2.fromOffset(200, 18), TextSize = 13, TextColor3 = Hud.DIM, Font = Enum.Font.GothamBold, ZIndex = 9 })
	for i, id in order do
		local column = if i <= rows then 0 else 1
		local row = if i <= rows then i - 1 else i - rows - 1
		local button = Hud.button(list, {
			Name = id,
			Text = `{i}  {cameras[id].displayName}`,
			TextXAlignment = Enum.TextXAlignment.Left,
			Position = UDim2.fromOffset(8 + column * 180, 24 + row * 26),
			Size = UDim2.fromOffset(176, 24),
			TextSize = 12,
			ZIndex = 9,
		})
		listButtons[id] = button
		button.Activated:Connect(function()
			selectCamera(i)
		end)
	end

	local hints = { "Click a camera in the list, or A/D", "Right-drag  look" }
	if overwatch then
		table.insert(hints, "Click the view  ping it for the mercs")
		table.insert(hints, "F  tag an Exposed/Revealed Chimera")
	end
	ui.hints = Hud.hints(hints)
	UserInputService.MouseBehavior = Enum.MouseBehavior.Default
	UserInputService.MouseIconEnabled = true
	table.insert(connections, UserInputService.InputBegan:Connect(function(input, processed)
		if input.UserInputType == Enum.UserInputType.MouseButton2 then
			dragging = true
			UserInputService.MouseBehavior = Enum.MouseBehavior.LockCurrentPosition
		elseif processed then
			return
		elseif input.UserInputType == Enum.UserInputType.MouseButton1 and overwatch then
			pingUnderMouse()
		elseif input.KeyCode == Enum.KeyCode.F and overwatch then
			actionRemote:FireServer("owTag")
		elseif input.KeyCode == Enum.KeyCode.D or input.KeyCode == Enum.KeyCode.Right then
			selectCamera(index + 1)
		elseif input.KeyCode == Enum.KeyCode.A or input.KeyCode == Enum.KeyCode.Left then
			selectCamera(index - 1)
		end
	end))
	table.insert(connections, UserInputService.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton2 then
			dragging = false
			UserInputService.MouseBehavior = Enum.MouseBehavior.Default
		end
	end))
	RunService:BindToRenderStep("Spectate", Enum.RenderPriority.Camera.Value + 1, render)
	selectCamera(index)
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
	for _, key in { "label", "camName", "static", "hints", "status", "list" } do
		if ui[key] then
			ui[key]:Destroy()
		end
	end
	table.clear(ui)
	table.clear(listButtons)
	UserInputService.MouseBehavior = Enum.MouseBehavior.Default
	workspace.CurrentCamera.CameraType = Enum.CameraType.Custom
end

-- Studio tests: watch a camera, ping a point, or tag.
function Spectate.testCamera(id: string)
	local i = table.find(order, id)
	if i then
		selectCamera(i)
	end
end

function Spectate.describe(): { [string]: any }
	return {
		running = running,
		overwatch = overwatch,
		camera = order[index],
		status = ui.status and ui.status.Text,
		label = ui.label and ui.label.Text,
	}
end

return Spectate
