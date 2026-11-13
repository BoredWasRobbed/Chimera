-- The merc's combat controls and HUD. An over-the-shoulder camera with the mouse locked (hold Left Alt
-- for a cursor); the body faces where you aim. Firing, gear, the flashlight, Flash and Stim are requests:
-- the server owns ammo, cooldowns and every hit, and this client only draws its own tracer at once.
--   LMB fire   R reload   G gear   F flashlight   V Flash   H Stim   T hold/holster the motion tracker
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Config = require(ReplicatedStorage.Shared.Config)
local Net = require(ReplicatedStorage.Shared.Net)
local DetectionHud = require(script.Parent.DetectionHud)
local Effects = require(script.Parent.Effects)
local Flashlights = require(script.Parent.Flashlights)
local Hud = require(script.Parent.Hud)

local MercCombat = {}

local player = Players.LocalPlayer
local SENSITIVITY = 0.3
local CAMERA_OFFSET = Vector3.new(2.8, 1.2, 8) -- far enough right that the merc's head never covers the crosshair

local actionRemote: RemoteEvent
local running = false
local connections: { RBXScriptConnection } = {}
local ui: { [string]: any } = {}
local yaw, pitch = 0, -0.1
local aimPoint = Vector3.zero
local aimDir = Vector3.new(0, 0, -1)
local firing = false
local nextShotAt = 0
local predictedAmmo: number? = nil
local reloadRequestedAt = 0
local lastAimSent = Vector3.zero
local lastAimSentAt = 0
local hitMarkerUntil = 0
local blindUntil, blindSeconds = 0, 1
local cameraParams = RaycastParams.new()
local aimParams = RaycastParams.new()
local clientFolder: Folder
local lookFrozen = false -- the ping wheel uses the mouse while it's open

local function serverNow(): number
	return workspace:GetServerTimeNow()
end

local function weapon()
	local id = player:GetAttribute("Weapon")
	return if id then Config.Weapons[id] else nil
end

local function character(): (Model?, BasePart?, Humanoid?)
	local c = player.Character
	local root = c and c:FindFirstChild("HumanoidRootPart") :: BasePart?
	local humanoid = c and c:FindFirstChildOfClass("Humanoid")
	return c, root, humanoid
end

local function isDowned(): boolean
	local c = player.Character
	return c ~= nil and c:GetAttribute("Downed") == true
end

-- Rebooting a terminal: the operator can't shoot or use gear.
local function operating(): boolean
	local c = player.Character
	return c ~= nil and c:GetAttribute("Operating") ~= nil
end

local function freeCursor(): boolean
	return UserInputService:IsKeyDown(Enum.KeyCode.LeftAlt) or UserInputService:GetFocusedTextBox() ~= nil
end

local function ammo(): number
	return predictedAmmo or player:GetAttribute("Ammo") or 0
end

local function reloading(): boolean
	return (player:GetAttribute("ReloadEndsAt") or 0) > serverNow()
end

local function canFire(): boolean
	local c, root = character()
	return c ~= nil and root ~= nil and not isDowned() and not operating() and not DetectionHud.isHeld() and not freeCursor() and not reloading() and ammo() > 0
end

local function muzzle(): Vector3
	local c = player.Character
	local torso = c and c:FindFirstChild("Torso") :: BasePart?
	return if torso then (torso.CFrame * CFrame.new(1.4, 0.3, -1.4)).Position else aimPoint
end

local function requestReload()
	if os.clock() - reloadRequestedAt > 0.5 and not reloading() then
		reloadRequestedAt = os.clock()
		actionRemote:FireServer("reload")
	end
end

local function fire()
	local w = weapon()
	local c = player.Character
	local head = c and c:FindFirstChild("Head") :: BasePart?
	if not w or not head then
		return
	end
	if ammo() <= 0 then
		requestReload()
		return
	end
	local origin = head.Position
	local direction = (aimPoint - origin).Unit
	actionRemote:FireServer("fire", origin, direction, serverNow() - Config.Perception.InterpolationDelay)
	local from = muzzle()
	Effects.tracer(from, aimPoint)
	if not w.Silenced then
		Effects.muzzle(from)
	end
	predictedAmmo = ammo() - 1
	if predictedAmmo <= 0 then
		requestReload()
	end
end

local function tryFire()
	local w = weapon()
	local now = os.clock()
	if w and now >= nextShotAt and canFire() then
		nextShotAt = now + w.Interval
		fire()
	end
end

local function updateHud()
	local c = player.Character
	local hp = c and c:GetAttribute("HP") or 0
	local maxHp = c and c:GetAttribute("MaxHP") or 100
	ui.setHp(hp / math.max(maxHp, 1))
	ui.hpLabel.Text = `HP {hp}`

	local w = weapon()
	local class = player:GetAttribute("Class") or "?"
	ui.weaponLabel.Text = `{string.upper(class)} · {if w then w.Name else "-"}`
	if reloading() then
		local endsAt = player:GetAttribute("ReloadEndsAt") or 0
		ui.ammoLabel.Text = "RELOADING"
		ui.setReload(1 - math.clamp((endsAt - serverNow()) / (if w then w.Reload else 1), 0, 1))
		ui.reloadBar.Visible = true
	else
		ui.ammoLabel.Text = `{ammo()} / {player:GetAttribute("Magazine") or 0}`
		ui.reloadBar.Visible = false
	end

	local gear = player:GetAttribute("Gear")
	local gearInfo = gear and Config.Gear[gear]
	local gearName = if gearInfo then gearInfo.Name else "-"
	if gear == "NanoRegen" then
		local readyIn = (player:GetAttribute("GearReadyAt") or 0) - serverNow()
		ui.gearLabel.Text = if readyIn > 0 then string.format("[G] %s  %ds", gearName, math.ceil(readyIn)) else `[G] {gearName}  ready`
	else
		ui.gearLabel.Text = `[G] {gearName} ×{player:GetAttribute("GearCount") or 0}`
	end
	ui.stimLabel.Text = if c and c:GetAttribute("Stim") then "[H] Stim  ready" else "[H] Stim  used"

	local battery = player:GetAttribute("Battery") or 0
	local on = c and c:GetAttribute("Flashlight") == true
	ui.setBattery(battery / 100)
	local flashIn = (player:GetAttribute("FlashReadyAt") or 0) - serverNow()
	ui.lightLabel.Text = string.format("[F] Light %s %d%%   [V] Flash %s", if on then "ON" else "off", math.floor(battery), if flashIn > 0 then `{math.ceil(flashIn)}s` else "ready")

	ui.hitMarker.Visible = os.clock() < hitMarkerUntil
	local blindLeft = blindUntil - os.clock()
	ui.blind.Visible = blindLeft > 0
	if blindLeft > 0 then
		ui.blind.BackgroundTransparency = 1 - math.clamp(blindLeft / blindSeconds, 0, 1) * 0.95
	end

	local downed = isDowned()
	ui.downed.Visible = downed
	if downed then
		local left = (c and c:GetAttribute("BleedEndsAt") or 0) - serverNow()
		ui.downedLabel.Text = string.format("DOWNED  ·  bleeding out in %d s\nA teammate can revive you (hold E)", math.max(0, math.ceil(left)))
	end
	ui.crosshair.Visible = not downed and not DetectionHud.isHeld()
end

local function render(dt: number)
	local c, root, humanoid = character()
	if not c or not root or not humanoid then
		return
	end
	local free = freeCursor()
	UserInputService.MouseBehavior = if free then Enum.MouseBehavior.Default else Enum.MouseBehavior.LockCenter
	UserInputService.MouseIconEnabled = free
	if not free and not lookFrozen then
		local delta = UserInputService:GetMouseDelta()
		yaw -= math.rad(delta.X * SENSITIVITY)
		pitch = math.clamp(pitch - math.rad(delta.Y * SENSITIVITY), -1.3, 1.2)
	end
	humanoid.AutoRotate = false
	root.CFrame = CFrame.new(root.Position) * CFrame.Angles(0, yaw, 0)

	local camera = workspace.CurrentCamera
	local pivot = root.Position + Vector3.new(0, if isDowned() then 0.3 else 1.6, 0)
	local rotation = CFrame.Angles(0, yaw, 0) * CFrame.Angles(pitch, 0, 0)
	local desired = pivot + rotation:VectorToWorldSpace(CAMERA_OFFSET)
	local offset = desired - pivot
	local blocked = workspace:Raycast(pivot, offset, cameraParams)
	local position = if blocked then pivot + offset.Unit * math.max(0.4, blocked.Distance - 0.4) else desired
	camera.CameraType = Enum.CameraType.Scriptable
	camera.FieldOfView = 70
	camera.CFrame = CFrame.new(position) * rotation
	-- With a wall right behind, the camera ends up inside the body: hide it rather than fill the view.
	local fade = if (position - pivot).Magnitude < 2.5 then 1 else 0
	for _, part in c:GetDescendants() do
		if part:IsA("BasePart") and part.LocalTransparencyModifier ~= fade then
			part.LocalTransparencyModifier = fade
		end
	end

	local viewport = camera.ViewportSize
	local ray = camera:ViewportPointToRay(viewport.X / 2, viewport.Y / 2)
	local hit = workspace:Raycast(ray.Origin, ray.Direction * 400, aimParams)
	aimPoint = if hit then hit.Position else ray.Origin + ray.Direction * 400
	local head = c:FindFirstChild("Head") :: BasePart?
	if head then
		local toAim = aimPoint - head.Position
		if toAim.Magnitude > 0.5 then
			aimDir = toAim.Unit
		end
	end
	Flashlights.setLocalAim(aimDir)
	local now = os.clock()
	if now - lastAimSentAt >= 0.1 and aimDir:Dot(lastAimSent) < 0.9995 then
		lastAimSentAt = now
		lastAimSent = aimDir
		actionRemote:FireServer("aim", aimDir)
	end

	local w = weapon()
	if firing and w and w.Auto then
		tryFire()
	end
	updateHud()
end

local function onInputBegan(input: InputObject, processed: boolean)
	if processed or not running then
		return
	end
	if input.UserInputType == Enum.UserInputType.MouseButton1 then
		firing = true
		local w = weapon()
		if w and not w.Auto then
			tryFire()
		end
		return
	end
	if input.UserInputType ~= Enum.UserInputType.Keyboard then
		return
	end
	local key = input.KeyCode
	local c = player.Character
	local head = c and c:FindFirstChild("Head") :: BasePart?
	if key == Enum.KeyCode.R then
		requestReload()
	elseif key == Enum.KeyCode.G and head and not isDowned() and not operating() then
		actionRemote:FireServer("gear", head.Position, aimDir)
	elseif key == Enum.KeyCode.F then
		actionRemote:FireServer("flashlight", not (c and c:GetAttribute("Flashlight") == true))
	elseif key == Enum.KeyCode.V and not isDowned() then
		actionRemote:FireServer("flash")
	elseif key == Enum.KeyCode.H then
		actionRemote:FireServer("stim")
	elseif key == Enum.KeyCode.T then
		DetectionHud.setHeld(not DetectionHud.isHeld())
	end
end

local function onInputEnded(input: InputObject)
	if input.UserInputType == Enum.UserInputType.MouseButton1 then
		firing = false
	end
end

-- Weld prompts are for Technicians only, nobody can revive themselves, and a terminal's Reboot prompt
-- shows only while you could reboot it (during the race, not done, not locked, nobody else on it).
-- Prompts are shared server objects, so this client hides the ones that aren't for it.
local function filterPrompts()
	local isTechnician = player:GetAttribute("Class") == "Technician"
	local state = ReplicatedStorage:FindFirstChild("MatchState")
	local racing = state ~= nil and state:GetAttribute("Phase") == "Race"
	local terminals = workspace:FindFirstChild("Map") and workspace.Map:FindFirstChild("Terminals")
	if terminals then
		for _, model in terminals:GetChildren() do
			local anchor = model:FindFirstChild("Console") or model:FindFirstChild("Screen")
			local reboot = anchor and anchor:FindFirstChild("Reboot") :: ProximityPrompt?
			if reboot then
				local operator = model:GetAttribute("Operator")
				local locked = (model:GetAttribute("LockedUntil") or 0) > serverNow()
				local wanted = racing and not model:GetAttribute("Done") and not locked and (operator == nil or operator == player.Name) and not isDowned()
				if reboot.Enabled ~= wanted then
					reboot.Enabled = wanted
				end
			end
		end
	end
	local doors = workspace:FindFirstChild("Map") and workspace.Map:FindFirstChild("Doors")
	if doors then
		for _, door in doors:GetChildren() do
			local anchor = door:FindFirstChild("LockLight1") or door:FindFirstChild("Panel")
			local weld = anchor and anchor:FindFirstChild("WeldPrompt") :: ProximityPrompt?
			local panel = door:FindFirstChild("Panel")
			local force = panel and panel:FindFirstChild("ForceOpen") :: ProximityPrompt?
			if weld then
				local wanted = isTechnician and not door:GetAttribute("Welded") and not (force and force.Enabled)
				if weld.Enabled ~= wanted then
					weld.Enabled = wanted
				end
			end
		end
	end
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	local own = root and root:FindFirstChild("Revive") :: ProximityPrompt?
	if own and own.Enabled then
		own.Enabled = false
	end
	-- Medics revive twice as fast; the server checks the hold time either way.
	local reviveSeconds = if player:GetAttribute("Class") == "Medic" then Config.Health.MedicReviveSeconds else Config.Health.ReviveSeconds
	for _, model in workspace:GetChildren() do
		local other = model:IsA("Model") and model:FindFirstChild("HumanoidRootPart")
		local revive = other and other:FindFirstChild("Revive") :: ProximityPrompt?
		if revive and revive.HoldDuration ~= reviveSeconds then
			revive.HoldDuration = reviveSeconds
		end
	end
end

local function buildHud()
	local gui = Hud.gui()
	local hpBar, setHp = Hud.bar(gui, {
		Name = "MercHP",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 76), -- under the match bar
		Size = UDim2.fromOffset(300, 10),
	}, Color3.fromRGB(235, 240, 245))
	ui.hpBar, ui.setHp = hpBar, setHp
	ui.hpLabel = Hud.text(hpBar, { Position = UDim2.fromOffset(0, 12), Size = UDim2.new(1, 0, 0, 18), TextSize = 15, TextXAlignment = Enum.TextXAlignment.Center, Font = Enum.Font.GothamMedium })

	local panel = Hud.frame(gui, {
		Name = "Loadout",
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, -16, 1, -60),
		Size = UDim2.fromOffset(300, 128),
		BackgroundTransparency = 0.45,
	})
	ui.panel = panel
	local function line(y: number, size: number): TextLabel
		return Hud.text(panel, { Position = UDim2.fromOffset(10, y), Size = UDim2.new(1, -20, 0, size + 4), TextSize = size, Font = Enum.Font.GothamMedium })
	end
	ui.weaponLabel = line(6, 13)
	ui.ammoLabel = line(22, 24)
	local reloadBar, setReload = Hud.bar(panel, { Position = UDim2.fromOffset(10, 50), Size = UDim2.new(1, -20, 0, 4) }, Hud.WHITE)
	ui.reloadBar, ui.setReload = reloadBar, setReload
	ui.gearLabel = line(58, 14)
	ui.stimLabel = line(76, 14)
	ui.lightLabel = line(94, 13)
	local batteryBar, setBattery = Hud.bar(panel, { Position = UDim2.fromOffset(10, 114), Size = UDim2.new(1, -20, 0, 4) }, Color3.fromRGB(255, 235, 170))
	ui.batteryBar, ui.setBattery = batteryBar, setBattery

	ui.crosshair = Hud.frame(gui, { Name = "Crosshair", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(4, 4), BackgroundColor3 = Hud.WHITE, BackgroundTransparency = 0.1 })
	ui.hitMarker = Hud.text(gui, { Name = "HitMarker", Text = "✕", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(30, 30), TextSize = 22, TextXAlignment = Enum.TextXAlignment.Center, Visible = false })

	ui.downed = Hud.frame(gui, { Name = "Downed", Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.fromRGB(10, 10, 12), BackgroundTransparency = 0.55, Visible = false, ZIndex = 2 })
	ui.downedLabel = Hud.text(ui.downed, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.35), Size = UDim2.fromOffset(700, 60), TextSize = 22, TextXAlignment = Enum.TextXAlignment.Center, Font = Enum.Font.GothamMedium, ZIndex = 3 })
	ui.blind = Hud.frame(gui, { Name = "Blind", Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.fromRGB(240, 243, 246), BackgroundTransparency = 1, Visible = false, ZIndex = 20 })

	ui.hints = Hud.hints({
		"WASD move   Shift sprint   Hold Alt cursor",
		"LMB fire   R reload   G gear   H Stim",
		"F flashlight   V Flash   T motion tracker",
		"E revive / force doors (Technician: weld)",
		"Hold E at a terminal  reboot it",
		"Z / middle mouse  ping (hold: wheel)",
	})
end

function MercCombat.init(folder: Folder)
	clientFolder = folder
	actionRemote = Net.get("MercAction")
	local map, facility = workspace:WaitForChild("Map"), workspace:WaitForChild("Facility")
	cameraParams.FilterType = Enum.RaycastFilterType.Include
	cameraParams.FilterDescendantsInstances = { map }
	aimParams.FilterType = Enum.RaycastFilterType.Include
	local include = { map, facility:WaitForChild("Lights"), facility:WaitForChild("Cameras") }
	for _, name in { "Shells", "Docks" } do
		local f = folder:FindFirstChild(name)
		if f then
			table.insert(include, f)
		end
	end
	local decoys = workspace:WaitForChild("Decoys", 5)
	if decoys then
		table.insert(include, decoys)
	end
	aimParams.FilterDescendantsInstances = include
	Net.get("MercEvents").OnClientEvent:Connect(function(kind, a)
		if kind == "hitMarker" then
			hitMarkerUntil = os.clock() + 0.15
		elseif kind == "blind" and type(a) == "number" then
			blindSeconds = a
			blindUntil = os.clock() + a
		end
	end)
	player:GetAttributeChangedSignal("Ammo"):Connect(function()
		predictedAmmo = nil
	end)
end

function MercCombat.start()
	if running then
		return
	end
	running = true
	firing = false
	predictedAmmo = nil
	local camera = workspace.CurrentCamera
	local _, ry = camera.CFrame:ToOrientation()
	yaw, pitch = ry, -0.1
	buildHud()
	DetectionHud.start()
	table.insert(connections, UserInputService.InputBegan:Connect(onInputBegan))
	table.insert(connections, UserInputService.InputEnded:Connect(onInputEnded))
	local accumulator = 0
	table.insert(connections, RunService.Heartbeat:Connect(function(dt)
		accumulator += dt
		if accumulator >= 0.25 then
			accumulator = 0
			filterPrompts()
		end
	end))
	RunService:BindToRenderStep("MercCamera", Enum.RenderPriority.Camera.Value + 1, render)
end

function MercCombat.stop()
	if not running then
		return
	end
	running = false
	firing = false
	RunService:UnbindFromRenderStep("MercCamera")
	for _, connection in connections do
		connection:Disconnect()
	end
	table.clear(connections)
	DetectionHud.stop()
	for _, key in { "hpBar", "panel", "crosshair", "hitMarker", "downed", "blind", "hints" } do
		if ui[key] then
			ui[key]:Destroy()
		end
	end
	table.clear(ui)
	Flashlights.setLocalAim(nil)
	UserInputService.MouseBehavior = Enum.MouseBehavior.Default
	UserInputService.MouseIconEnabled = true
	local _, _, humanoid = character()
	if humanoid then
		humanoid.AutoRotate = true
	end
end

-- The ping wheel takes the mouse while it's open.
function MercCombat.setLookFrozen(frozen: boolean)
	lookFrozen = frozen
end

-- Where the crosshair points in the world (pings mark it).
function MercCombat.aimPoint(): Vector3
	return aimPoint
end

function MercCombat.isRunning(): boolean
	return running
end

function MercCombat.describe(): { [string]: any }
	return {
		running = running,
		operating = operating(),
		ammo = ammo(),
		reloading = reloading(),
		aimPoint = { math.floor(aimPoint.X), math.floor(aimPoint.Y), math.floor(aimPoint.Z) },
		trackerHeld = DetectionHud.isHeld(),
	}
end

-- For Studio tests: aim at a world point and fire once, through the same path as the mouse.
function MercCombat.testFireAt(point: Vector3)
	aimPoint = point
	local w = weapon()
	if w and canFire() then
		nextShotAt = os.clock() + w.Interval
		fire()
	end
end

-- For Studio tests: face a world point (the camera turns there next frame).
function MercCombat.testLookAt(point: Vector3)
	local c = player.Character
	local head = c and c:FindFirstChild("Head") :: BasePart?
	if head then
		local d = (point - head.Position).Unit
		yaw = math.atan2(-d.X, -d.Z)
		pitch = math.asin(math.clamp(d.Y, -1, 1))
	end
end

return MercCombat
