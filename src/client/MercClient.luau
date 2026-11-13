-- Merc controls for milestone 1: walk at 14, hold Shift to sprint at 20 for up to 5 s.
-- The sprint is predicted here so it starts instantly; the server runs the same stamina model,
-- owns the result and corrects this client twice a second.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Config = require(ReplicatedStorage.Shared.Config)
local Net = require(ReplicatedStorage.Shared.Net)
local Hud = require(script.Parent.Hud)

local MercClient = {}

local M = Config.Merc
local player = Players.LocalPlayer

local running = false
local connections: { RBXScriptConnection } = {}
local sprintRemote: RemoteEvent
local stamina = M.SprintSeconds
local exhausted = false
local sprinting = false
local lastSprintAt = -math.huge
local lastWant = false
local ui: { [string]: any } = {}

local function wantsSprint(): boolean
	if UserInputService:GetFocusedTextBox() then
		return false
	end
	return UserInputService:IsKeyDown(Enum.KeyCode.LeftShift) or UserInputService:IsKeyDown(Enum.KeyCode.RightShift)
end

local function update(dt: number)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then
		return
	end
	local now = os.clock()
	local want = wantsSprint()
	if want ~= lastWant then
		lastWant = want
		sprintRemote:FireServer(want)
	end
	local moving = humanoid.MoveDirection.Magnitude > 0.1
	local downed = character:GetAttribute("Downed") == true
	if want and moving and not downed and not exhausted and stamina > 0 then
		sprinting = true
		lastSprintAt = now
		stamina = math.max(0, stamina - dt)
		if stamina <= 0 then
			exhausted = true
			sprinting = false
		end
	else
		sprinting = false
		if now - lastSprintAt >= M.StaminaRegenDelay then
			stamina = math.min(M.SprintSeconds, stamina + M.StaminaRegenPerSecond * dt)
		end
		if exhausted and stamina >= M.SprintRestartSeconds then
			exhausted = false
		end
	end
	-- Same rule as the server's MercMovement.speedFor: crawl at 30% when downed, and any slow on top.
	local speed = if sprinting then M.SprintSpeed else M.WalkSpeed
	if downed then
		speed = M.WalkSpeed * Config.Health.DownedSpeedScale
	end
	local slowUntil = character:GetAttribute("SlowUntil")
	if type(slowUntil) == "number" and workspace:GetServerTimeNow() < slowUntil then
		speed *= character:GetAttribute("SlowScale") or 1
	end
	if humanoid.WalkSpeed ~= speed then
		humanoid.WalkSpeed = speed
	end

	local full = stamina >= M.SprintSeconds - 1e-3
	ui.bar.Visible = not full or sprinting
	ui.setFill(stamina / M.SprintSeconds)
	ui.label.Text = if exhausted then "WINDED" else "STAMINA"
	ui.label.TextColor3 = if exhausted then Hud.WARN else Hud.DIM
end

local function onServerState(serverStamina: number, serverExhausted: boolean)
	if not running then
		return
	end
	if math.abs(serverStamina - stamina) > 0.3 then
		stamina = serverStamina
	end
	exhausted = serverExhausted
end

function MercClient.init()
	sprintRemote = Net.get("MercSprint")
	Net.get("MercState").OnClientEvent:Connect(onServerState)
end

function MercClient.start()
	if running then
		return
	end
	running = true
	stamina = M.SprintSeconds
	exhausted = false
	sprinting = false
	lastWant = false

	local gui = Hud.gui()
	local bar, setFill = Hud.bar(gui, {
		Name = "Stamina",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -40),
		Size = UDim2.fromOffset(240, 8),
		Visible = false,
	}, Hud.CYAN)
	ui.bar = bar
	ui.setFill = setFill
	ui.label = Hud.text(bar, {
		Text = "STAMINA",
		TextSize = 13,
		TextColor3 = Hud.DIM,
		Position = UDim2.fromOffset(0, -18),
		Size = UDim2.new(1, 0, 0, 16),
	})

	local camera = workspace.CurrentCamera
	camera.CameraType = Enum.CameraType.Custom
	UserInputService.MouseBehavior = Enum.MouseBehavior.Default

	table.insert(connections, RunService.Heartbeat:Connect(update))
	table.insert(connections, player.CharacterAdded:Connect(function(character)
		stamina = M.SprintSeconds
		exhausted = false
		local humanoid = character:WaitForChild("Humanoid", 10)
		if humanoid then
			workspace.CurrentCamera.CameraSubject = humanoid
			workspace.CurrentCamera.CameraType = Enum.CameraType.Custom
		end
	end))
	local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		camera.CameraSubject = humanoid
	end
end

function MercClient.stop()
	if not running then
		return
	end
	running = false
	for _, connection in connections do
		connection:Disconnect()
	end
	table.clear(connections)
	if lastWant then
		lastWant = false
		sprintRemote:FireServer(false)
	end
	for _, key in { "bar", "hints" } do
		if ui[key] then
			ui[key]:Destroy()
		end
	end
	table.clear(ui)
end

function MercClient.describe(): { [string]: any }
	return { running = running, stamina = stamina, exhausted = exhausted, sprinting = sprinting }
end

return MercClient
