-- Teammates' name tags show through walls within 30 studs (shared merc kit). They read the MercTag
-- attribute, which real mercs and Static Decoys both carry, so a decoy gets a tag like anyone else.
-- Downed teammates show their bleed-out timer.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Hud = require(script.Parent.Hud)

local NameTags = {}

local RANGE = 30
local player = Players.LocalPlayer

local running = false
local connection: RBXScriptConnection? = nil
local labels: { [Model]: TextLabel } = {}

local function candidates(): { Model }
	local out = {}
	for _, other in Players:GetPlayers() do
		if other ~= player and other.Character and other:GetAttribute("Role") == "Merc" then
			table.insert(out, other.Character)
		end
	end
	for _, child in workspace:GetChildren() do
		if child:IsA("Model") and child:GetAttribute("MercTag") and not Players:GetPlayerFromCharacter(child) then
			table.insert(out, child) -- Studio dummies
		end
	end
	local decoys = workspace:FindFirstChild("Decoys")
	if decoys then
		for _, model in decoys:GetChildren() do
			if model:IsA("Model") then
				table.insert(out, model)
			end
		end
	end
	return out
end

local function render()
	local camera = workspace.CurrentCamera
	local me = player.Character
	local root = me and me:FindFirstChild("HumanoidRootPart") :: BasePart?
	local seen = {}
	if root then
		for _, model in candidates() do
			local head = model:FindFirstChild("Head") :: BasePart?
			local tag = model:GetAttribute("MercTag")
			if not head or not tag or (head.Position - root.Position).Magnitude > RANGE then
				continue
			end
			local projected = camera:WorldToViewportPoint(head.Position + Vector3.new(0, 1.6, 0))
			if projected.Z <= 0 then
				continue
			end
			seen[model] = true
			local label = labels[model]
			if not label then
				label = Hud.text(Hud.gui(), { Name = "NameTag", AnchorPoint = Vector2.new(0.5, 1), Size = UDim2.fromOffset(220, 34), TextSize = 14, TextXAlignment = Enum.TextXAlignment.Center, TextYAlignment = Enum.TextYAlignment.Bottom, FontFace = Hud.FONT_BOLD })
				labels[model] = label
			end
			label.Position = UDim2.fromOffset(projected.X, projected.Y)
			if model:GetAttribute("Downed") then
				local left = (model:GetAttribute("BleedEndsAt") or 0) - workspace:GetServerTimeNow()
				label.Text = string.format("%s\nDOWNED %ds", tag, math.max(0, math.ceil(left)))
				label.TextColor3 = Hud.WARN
			else
				label.Text = tag
				label.TextColor3 = Hud.WHITE
			end
		end
	end
	for model, label in labels do
		if not seen[model] then
			label:Destroy()
			labels[model] = nil
		end
	end
end

function NameTags.start()
	if running then
		return
	end
	running = true
	connection = RunService.RenderStepped:Connect(render)
end

function NameTags.stop()
	running = false
	if connection then
		connection:Disconnect()
		connection = nil
	end
	for model, label in labels do
		label:Destroy()
		labels[model] = nil
	end
end

return NameTags
