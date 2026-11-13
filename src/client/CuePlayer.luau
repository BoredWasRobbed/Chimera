-- Plays the tells the server sends to players in earshot. Cue sounds are placeholders until the audio
-- pass: with no SoundId set, Studio shows a floating label where the cue played instead.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)
local Net = require(ReplicatedStorage.Shared.Net)
local Hud = require(script.Parent.Hud)

local CuePlayer = {}

local folder: Folder
local recent: { { name: string, at: number } } = {}
local labels: { { label: TextLabel, position: Vector3, expires: number } } = {}

local function anchor(position: Vector3, lifetime: number): Part
	local part = Instance.new("Part")
	part.Name = "Cue"
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Transparency = 1
	part.Size = Vector3.new(0.2, 0.2, 0.2)
	part.CFrame = CFrame.new(position)
	part.Parent = folder
	task.delay(lifetime, function()
		part:Destroy()
	end)
	return part
end

local function play(name: string, position: Vector3)
	local def = Config.Cues[name]
	if not def then
		return
	end
	table.insert(recent, { name = name, at = os.clock() })
	while #recent > 20 do
		table.remove(recent, 1)
	end
	if def.SoundId ~= "" then
		local part = anchor(position, 6)
		local sound = Instance.new("Sound")
		sound.SoundId = def.SoundId
		sound.Volume = def.Volume
		sound.RollOffMaxDistance = 80
		sound.Parent = part
		sound:Play()
	end
	if RunService:IsStudio() then
		local label = Hud.text(Hud.gui(), {
			Name = "CueLabel",
			Text = `♪ {def.Label}`,
			TextSize = 16,
			TextColor3 = Color3.fromRGB(255, 220, 120),
			TextStrokeTransparency = 0.3,
			TextXAlignment = Enum.TextXAlignment.Center,
			AnchorPoint = Vector2.new(0.5, 1),
			Size = UDim2.fromOffset(220, 22),
			Visible = false,
		})
		table.insert(labels, { label = label, position = position + Vector3.new(0, 2, 0), expires = os.clock() + 1.6 })
	end
end

-- Studio cue labels are screen-space so they show through walls, like a sound would carry.
local function placeLabels()
	local camera = workspace.CurrentCamera
	local now = os.clock()
	for index = #labels, 1, -1 do
		local entry = labels[index]
		if now >= entry.expires then
			entry.label:Destroy()
			table.remove(labels, index)
		else
			local projected = camera:WorldToViewportPoint(entry.position)
			entry.label.Visible = projected.Z > 0
			entry.label.Position = UDim2.fromOffset(projected.X, projected.Y)
		end
	end
end

function CuePlayer.init(clientFolder: Folder)
	folder = Instance.new("Folder")
	folder.Name = "Cues"
	folder.Parent = clientFolder
	Net.get("Cue").OnClientEvent:Connect(function(name, position)
		if type(name) == "string" and typeof(position) == "Vector3" then
			play(name, position)
		end
	end)
	if RunService:IsStudio() then
		RunService.RenderStepped:Connect(placeLabels)
	end
end

-- For tests: cues heard in the last few seconds.
function CuePlayer.recent(seconds: number): { string }
	local out = {}
	local now = os.clock()
	for _, entry in recent do
		if now - entry.at <= seconds then
			table.insert(out, entry.name)
		end
	end
	return out
end

return CuePlayer
