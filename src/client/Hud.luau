-- Graybox UI helpers: one ScreenGui shared by every client controller, plus small factories.
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

local Hud = {}

Hud.CYAN = Color3.fromRGB(120, 220, 255)
Hud.WHITE = Color3.fromRGB(235, 240, 245)
Hud.DIM = Color3.fromRGB(150, 160, 170)
Hud.WARN = Color3.fromRGB(255, 170, 60)
Hud.PANEL = Color3.fromRGB(12, 16, 20)
Hud.FONT = Enum.Font.Code

local gui: ScreenGui
local toastFrame: Frame

function Hud.init()
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
	gui = Instance.new("ScreenGui")
	gui.Name = "ChimeraHud"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.DisplayOrder = 5
	gui.Parent = playerGui

	toastFrame = Instance.new("Frame")
	toastFrame.Name = "Toasts"
	toastFrame.BackgroundTransparency = 1
	toastFrame.AnchorPoint = Vector2.new(0.5, 0)
	toastFrame.Position = UDim2.new(0.5, 0, 0, 70)
	toastFrame.Size = UDim2.fromOffset(520, 200)
	toastFrame.ZIndex = 50
	toastFrame.Parent = gui
	local layout = Instance.new("UIListLayout")
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.Padding = UDim.new(0, 4)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = toastFrame
end

function Hud.gui(): ScreenGui
	return gui
end

function Hud.frame(parent: Instance, props: { [string]: any }): Frame
	local f = Instance.new("Frame")
	f.BorderSizePixel = 0
	f.BackgroundColor3 = Hud.PANEL
	f.BackgroundTransparency = 0.35
	for key, value in props do
		(f :: any)[key] = value
	end
	f.Parent = parent
	return f
end

function Hud.text(parent: Instance, props: { [string]: any }): TextLabel
	local t = Instance.new("TextLabel")
	t.BackgroundTransparency = 1
	t.Font = Hud.FONT
	t.TextColor3 = Hud.WHITE
	t.TextSize = 16
	t.TextStrokeTransparency = 0.6
	t.TextXAlignment = Enum.TextXAlignment.Left
	for key, value in props do
		(t :: any)[key] = value
	end
	t.Parent = parent
	return t
end

function Hud.button(parent: Instance, props: { [string]: any }): TextButton
	local b = Instance.new("TextButton")
	b.AutoButtonColor = true
	b.BorderSizePixel = 0
	b.BackgroundColor3 = Hud.PANEL
	b.BackgroundTransparency = 0.25
	b.Font = Hud.FONT
	b.TextColor3 = Hud.WHITE
	b.TextSize = 15
	for key, value in props do
		(b :: any)[key] = value
	end
	b.Parent = parent
	return b
end

-- A horizontal bar: returns the container and a setter taking 0..1.
function Hud.bar(parent: Instance, props: { [string]: any }, color: Color3): (Frame, (number) -> ())
	local back = Hud.frame(parent, props)
	local fill = Hud.frame(back, {
		Name = "Fill",
		BackgroundColor3 = color,
		BackgroundTransparency = 0.1,
		Size = UDim2.fromScale(1, 1),
	})
	return back, function(alpha: number)
		fill.Size = UDim2.fromScale(math.clamp(alpha, 0, 1), 1)
	end
end

function Hud.toast(text: string, color: Color3?)
	if not toastFrame then
		return
	end
	local label = Hud.text(toastFrame, {
		Text = text,
		TextColor3 = color or Hud.WARN,
		TextSize = 18,
		TextXAlignment = Enum.TextXAlignment.Center,
		Size = UDim2.fromOffset(520, 24),
		BackgroundTransparency = 0.4,
		BackgroundColor3 = Hud.PANEL,
		ZIndex = 50,
	})
	task.delay(1.6, function()
		local tween = TweenService:Create(label, TweenInfo.new(0.4), { TextTransparency = 1, BackgroundTransparency = 1, TextStrokeTransparency = 1 })
		tween:Play()
		tween.Completed:Wait()
		label:Destroy()
	end)
end

-- Control hints, bottom-left unless placed elsewhere. Returns the frame so a controller can remove it.
function Hud.hints(lines: { string }, position: UDim2?, anchor: Vector2?): Frame
	local frame = Hud.frame(gui, {
		Name = "Hints",
		AnchorPoint = anchor or Vector2.new(0, 1),
		Position = position or UDim2.new(0, 16, 1, -16),
		Size = UDim2.fromOffset(350, 20 * #lines + 12),
		BackgroundTransparency = 0.5,
	})
	for index, line in lines do
		Hud.text(frame, {
			Text = line,
			TextSize = 14,
			TextColor3 = Hud.DIM,
			Position = UDim2.fromOffset(10, 6 + (index - 1) * 20),
			Size = UDim2.new(1, -20, 0, 20),
		})
	end
	return frame
end

return Hud
