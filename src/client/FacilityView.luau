-- Facility mode on the Chimera's client. It sees through one security camera at a time and pans within
-- the mount's limits (right-drag or A/D/W/S, scroll to zoom). Linked cameras show as markers: click one,
-- or press its number, to hop there in 0.5 s. The cursor aims Interface at lights, doors, terminals and
-- stocked docks. The server decides everything; this only draws and asks.
local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local CameraMath = require(ReplicatedStorage.Shared.CameraMath)
local Config = require(ReplicatedStorage.Shared.Config)
local FacilityMap = require(ReplicatedStorage.Shared.FacilityMap)
local DockViews = require(script.Parent.DockViews)
local Hud = require(script.Parent.Hud)
local TargetHighlight = require(script.Parent.TargetHighlight)

export type Target = { kind: string, id: string, instance: Instance }

local FacilityView = {}

local player = Players.LocalPlayer
local CAM = Config.Camera
local NUMBER_KEYS = {
	Enum.KeyCode.One,
	Enum.KeyCode.Two,
	Enum.KeyCode.Three,
	Enum.KeyCode.Four,
	Enum.KeyCode.Five,
	Enum.KeyCode.Six,
	Enum.KeyCode.Seven,
	Enum.KeyCode.Eight,
	Enum.KeyCode.Nine,
}

local requestHop: (string) -> () = function() end
local cameras: { [string]: FacilityMap.CameraInfo } = {}
local current: FacilityMap.CameraInfo? = nil
local active = false
local relinking = false
local yawOffset, pitchOffset, fov = 0, 0, CAM.Fov
local dragging = false
local hover: Target? = nil
local hoverParams = RaycastParams.new()
local markers: { { button: TextButton, camera: FacilityMap.CameraInfo, label: string } } = {}
local hiddenParts: { BasePart } = {}
local connections: { RBXScriptConnection } = {}
local ui: { [string]: any } = {}
local testPointer: Vector2? = nil -- Studio tests aim here instead of at the mouse

local function camNumber(id: string): string
	local order = {}
	for camId in cameras do
		table.insert(order, camId)
	end
	table.sort(order)
	return string.format("%02d", table.find(order, id) or 0)
end

local function setCameraHidden(info: FacilityMap.CameraInfo?)
	for _, part in hiddenParts do
		part.LocalTransparencyModifier = 0
	end
	table.clear(hiddenParts)
	if info then
		for _, part in info.model:GetDescendants() do
			if part:IsA("BasePart") then
				part.LocalTransparencyModifier = 1
				table.insert(hiddenParts, part)
			end
		end
	end
end

local function clearMarkers()
	for _, marker in markers do
		marker.button:Destroy()
	end
	table.clear(markers)
	if ui.links then
		for _, child in ui.links:GetChildren() do
			if child:IsA("GuiButton") then
				child:Destroy()
			end
		end
	end
end

-- Markers are 2D buttons projected onto the feed every frame (they show through walls, and links
-- behind the view slide to the screen edge with an arrow).
local function placeMarkers()
	local camera = workspace.CurrentCamera
	local viewport = camera.ViewportSize
	local center = viewport / 2
	local margin = Vector2.new(110, 60)
	for _, marker in markers do
		local world = marker.camera.lens.Position + Vector3.new(0, 1.2, 0)
		local projected = camera:WorldToViewportPoint(world)
		local point = Vector2.new(projected.X, projected.Y)
		local behind = projected.Z < 0
		if behind then
			point = viewport - point
		end
		local inside = not behind
			and point.X >= margin.X
			and point.X <= viewport.X - margin.X
			and point.Y >= margin.Y
			and point.Y <= viewport.Y - margin.Y
		if inside then
			marker.button.Text = `◉ {marker.label}`
		else
			local d = point - center
			if d.Magnitude < 1 then
				d = Vector2.new(0, 1)
			end
			local scale = math.min(
				(center.X - margin.X) / math.max(math.abs(d.X), 1e-3),
				(center.Y - margin.Y) / math.max(math.abs(d.Y), 1e-3)
			)
			point = center + d * scale
			marker.button.Text = if d.X < 0 then `◀ {marker.label}` else `{marker.label} ▶`
		end
		marker.button.Position = UDim2.fromOffset(point.X, point.Y)
	end
end

local function buildMarkers()
	clearMarkers()
	if not current then
		return
	end
	for index, linkId in current.links do
		local cam = cameras[linkId]
		if not cam then
			continue
		end
		local label = if index <= 9 then `[{index}] {cam.displayName}` else cam.displayName

		local button = Hud.button(ui.markerLayer, {
			Name = `Marker_{linkId}`,
			Text = `◉ {label}`,
			AnchorPoint = Vector2.new(0.5, 1),
			Size = UDim2.fromOffset(200, 26),
			TextColor3 = Hud.CYAN,
			BackgroundTransparency = 0.35,
			ZIndex = 6,
		})
		button.Activated:Connect(function()
			requestHop(linkId)
		end)
		table.insert(markers, { button = button, camera = cam, label = label })

		local listButton = Hud.button(ui.links, {
			Name = `Link_{linkId}`,
			Text = label,
			LayoutOrder = index,
			Size = UDim2.fromOffset(170, 28),
			TextColor3 = Hud.CYAN,
		})
		listButton.Activated:Connect(function()
			requestHop(linkId)
		end)
	end
end

local function buildUi()
	local gui = Hud.gui()
	local feed = Hud.frame(gui, {
		Name = "Feed",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Visible = false,
	})
	ui.feed = feed
	ui.markerLayer = Hud.frame(feed, {
		Name = "Markers",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
	})
	-- Corner brackets of a security feed.
	for _, corner in { Vector2.new(0, 0), Vector2.new(1, 0), Vector2.new(0, 1), Vector2.new(1, 1) } do
		local x = if corner.X == 0 then 24 else -24
		local y = if corner.Y == 0 then 24 else -24
		local pos = UDim2.new(corner.X, x, corner.Y, y)
		Hud.frame(feed, { AnchorPoint = corner, Position = pos, Size = UDim2.fromOffset(48, 3), BackgroundColor3 = Hud.WHITE, BackgroundTransparency = 0.4 })
		Hud.frame(feed, { AnchorPoint = corner, Position = pos, Size = UDim2.fromOffset(3, 48), BackgroundColor3 = Hud.WHITE, BackgroundTransparency = 0.4 })
	end
	ui.camLabel = Hud.text(feed, {
		Name = "CamLabel",
		Position = UDim2.fromOffset(40, 36),
		Size = UDim2.fromOffset(600, 24),
		TextSize = 20,
	})
	ui.recLabel = Hud.text(feed, {
		Name = "Rec",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -40, 0, 36),
		Size = UDim2.fromOffset(260, 24),
		TextSize = 18,
		TextXAlignment = Enum.TextXAlignment.Right,
	})
	local links = Hud.frame(feed, {
		Name = "Links",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -24),
		Size = UDim2.new(1, -420, 0, 28),
		BackgroundTransparency = 1,
	})
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.Padding = UDim.new(0, 6)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = links
	ui.links = links

	local static = Hud.frame(gui, {
		Name = "Static",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.fromRGB(70, 74, 78),
		BackgroundTransparency = 0.15,
		Visible = false,
		ZIndex = 20,
	})
	ui.static = static
	ui.noise = {}
	for i = 1, 14 do
		ui.noise[i] = Hud.frame(static, {
			BackgroundColor3 = Color3.fromRGB(200, 205, 210),
			BackgroundTransparency = 0.5,
			Size = UDim2.new(1, 0, 0, 6),
			ZIndex = 21,
		})
	end
	ui.staticLabel = Hud.text(static, {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(600, 40),
		TextSize = 26,
		TextXAlignment = Enum.TextXAlignment.Center,
		ZIndex = 22,
	})
end

local function updateHover()
	hover = nil
	if relinking or not current then
		TargetHighlight.set(nil)
		return
	end
	local mouse = testPointer or UserInputService:GetMouseLocation()
	local inset = GuiService:GetGuiInset()
	if not testPointer then
		for _, object in player.PlayerGui:GetGuiObjectsAtPosition(mouse.X - inset.X, mouse.Y - inset.Y) do
			if object:IsA("GuiButton") and object.Visible then
				TargetHighlight.set(nil)
				return
			end
		end
	end
	local camera = workspace.CurrentCamera
	local ray = camera:ViewportPointToRay(mouse.X, mouse.Y)
	local result = workspace:Raycast(ray.Origin, ray.Direction * Config.Interface.CameraRange, hoverParams)
	if result then
		local kind, id = FacilityMap.targetOf(result.Instance)
		if kind and type(id) == "string" then
			if kind ~= "TakeShell" or DockViews.state(id) == "stocked" then
				local adornee = result.Instance
				if kind == "TakeShell" or kind == "LockDoor" or kind == "CorruptTerminal" then
					adornee = result.Instance:FindFirstAncestorOfClass("Model") or adornee
				elseif kind == "Blackout" then
					adornee = result.Instance.Parent or adornee
				end
				hover = { kind = kind, id = id, instance = adornee }
			end
		end
	end
	TargetHighlight.set(if hover then hover.instance else nil)
end

local function render(dt: number)
	local info = current
	if not active or not info then
		return
	end
	if not UserInputService:GetFocusedTextBox() then
		local yawInput = (if UserInputService:IsKeyDown(Enum.KeyCode.A) then 1 else 0) - (if UserInputService:IsKeyDown(Enum.KeyCode.D) then 1 else 0)
		local pitchInput = (if UserInputService:IsKeyDown(Enum.KeyCode.W) then 1 else 0) - (if UserInputService:IsKeyDown(Enum.KeyCode.S) then 1 else 0)
		yawOffset += math.rad(CAM.KeyPanSpeed) * yawInput * dt
		pitchOffset += math.rad(CAM.KeyPanSpeed) * pitchInput * dt
	end
	if dragging then
		local delta = UserInputService:GetMouseDelta()
		yawOffset -= math.rad(delta.X * CAM.DragSensitivity)
		pitchOffset -= math.rad(delta.Y * CAM.DragSensitivity)
	end
	yawOffset = math.clamp(yawOffset, -math.rad(info.panLimit), math.rad(info.panLimit))
	pitchOffset = math.clamp(pitchOffset, -math.rad(info.tiltLimit), math.rad(info.tiltLimit))

	local camera = workspace.CurrentCamera
	camera.CameraType = Enum.CameraType.Scriptable
	camera.FieldOfView = fov
	camera.CFrame = CameraMath.viewCFrame(info.origin, info.baseYaw + yawOffset, info.basePitch + pitchOffset)

	if relinking then
		for _, bar in ui.noise do
			bar.Position = UDim2.fromScale(0, math.random())
			bar.BackgroundTransparency = 0.3 + math.random() * 0.6
		end
		ui.static.BackgroundTransparency = 0.05 + math.random() * 0.2
	end
	ui.recLabel.Text = `● REC  {os.date("%H:%M:%S")}`
	placeMarkers()
	updateHover()
end

local function onInputBegan(input: InputObject, processed: boolean)
	if not active then
		return
	end
	if input.UserInputType == Enum.UserInputType.MouseButton2 then
		dragging = true
		UserInputService.MouseBehavior = Enum.MouseBehavior.LockCurrentPosition
		return
	end
	if processed or input.UserInputType ~= Enum.UserInputType.Keyboard or not current then
		return
	end
	local index = table.find(NUMBER_KEYS, input.KeyCode)
	if index and current.links[index] then
		requestHop(current.links[index])
	end
end

local function onInputEnded(input: InputObject)
	if input.UserInputType == Enum.UserInputType.MouseButton2 then
		dragging = false
		if active then
			UserInputService.MouseBehavior = Enum.MouseBehavior.Default
		end
	end
end

local function onInputChanged(input: InputObject, processed: boolean)
	if active and not processed and input.UserInputType == Enum.UserInputType.MouseWheel then
		fov = math.clamp(fov - input.Position.Z * 5, CAM.MinFov, CAM.MaxFov)
	end
end

function FacilityView.init(clientFolder: Folder, doorTargets: Folder, onRequestHop: (string) -> ())
	requestHop = onRequestHop
	cameras = FacilityMap.cameras()
	local map, facility = FacilityMap.folders()
	local include = { map, facility:WaitForChild("Lights"), DockViews.folder(), doorTargets }
	hoverParams.FilterType = Enum.RaycastFilterType.Include
	hoverParams.FilterDescendantsInstances = include
	TargetHighlight.init(clientFolder)
	buildUi()
end

function FacilityView.setCamera(cameraId: string)
	local info = cameras[cameraId]
	if not info then
		return
	end
	if not current or current.id ~= cameraId then
		yawOffset, pitchOffset = 0, 0
	end
	current = info
	ui.camLabel.Text = `CAM {camNumber(cameraId)}  {string.upper(info.displayName)}`
	if active then
		setCameraHidden(info)
		buildMarkers()
	end
end

function FacilityView.start(cameraId: string)
	FacilityView.setCamera(cameraId)
	if active then
		return
	end
	active = true
	relinking = false
	fov = CAM.Fov
	ui.feed.Visible = true
	ui.static.Visible = false
	setCameraHidden(current)
	buildMarkers()
	UserInputService.MouseBehavior = Enum.MouseBehavior.Default
	UserInputService.MouseIconEnabled = true
	ui.hints = Hud.hints({
		"Click a marker or 1-9  hop to a linked camera",
		"Right-drag or A/D/W/S  look   Scroll  zoom",
		"E  Interface on what you aim at",
		"Hold E on a stocked dock  take its shell",
	}, UDim2.fromOffset(24, 76), Vector2.zero)
	table.insert(connections, UserInputService.InputBegan:Connect(onInputBegan))
	table.insert(connections, UserInputService.InputEnded:Connect(onInputEnded))
	table.insert(connections, UserInputService.InputChanged:Connect(onInputChanged))
	RunService:BindToRenderStep("ChimeraFacility", Enum.RenderPriority.Camera.Value + 1, render)
end

function FacilityView.stop()
	if not active then
		return
	end
	active = false
	dragging = false
	relinking = false
	RunService:UnbindFromRenderStep("ChimeraFacility")
	for _, connection in connections do
		connection:Disconnect()
	end
	table.clear(connections)
	clearMarkers()
	setCameraHidden(nil)
	hover = nil
	TargetHighlight.set(nil)
	ui.feed.Visible = false
	ui.static.Visible = false
	if ui.hints then
		ui.hints:Destroy()
		ui.hints = nil
	end
	UserInputService.MouseBehavior = Enum.MouseBehavior.Default
end

function FacilityView.beginRelink(targetId: string)
	relinking = true
	local target = cameras[targetId]
	ui.staticLabel.Text = `RELINKING ▸ {if target then string.upper(target.displayName) else targetId}`
	ui.static.Visible = true
	clearMarkers()
end

function FacilityView.endRelink()
	relinking = false
	ui.static.Visible = false
	if active then
		buildMarkers()
	end
end

function FacilityView.target(): Target?
	return hover
end

function FacilityView.promptAnchor(): Vector2
	local mouse = UserInputService:GetMouseLocation()
	return Vector2.new(mouse.X + 18, mouse.Y + 14)
end

function FacilityView.cameraName(id: string): string
	local info = cameras[id]
	return if info then info.displayName else id
end

function FacilityView.describe(): { [string]: any }
	return {
		active = active,
		cameraId = current and current.id,
		relinking = relinking,
		yaw = yawOffset,
		pitch = pitchOffset,
		fov = fov,
		hover = hover and { kind = hover.kind, id = hover.id },
		links = current and current.links,
	}
end

-- For tests: turn this camera to face a world point (within its limits) and aim at the screen centre.
function FacilityView.lookAt(point: Vector3?)
	local info = current
	if not point then
		testPointer = nil
		return
	end
	if not info then
		return
	end
	local yaw, pitch = CameraMath.anglesFromLook((point - info.origin).Unit)
	yawOffset = CameraMath.wrap(yaw - info.baseYaw)
	pitchOffset = pitch - info.basePitch
	local viewport = workspace.CurrentCamera.ViewportSize
	testPointer = Vector2.new(viewport.X / 2, viewport.Y / 2)
end

return FacilityView
