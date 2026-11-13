-- Draws every merc's shoulder flashlight (and decoys', which copy one) from the replicated Flashlight
-- and Aim attributes. The local merc's light follows its own aim directly, so it never lags. On the
-- Chimera's client, beams within 40 studs of its camera or shell also show as shafts through walls.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)

local Flashlights = {}

local F = Config.Flashlight
local player = Players.LocalPlayer

type Lamp = { part: BasePart, light: SpotLight, shaft: BasePart, aim: Vector3 }

local folder: Folder
local lamps: { [Model]: Lamp } = {}
local localAim: Vector3? = nil

-- MercCombat reports the local aim every frame.
function Flashlights.setLocalAim(aim: Vector3?)
	localAim = aim
end

local function makeLamp(): Lamp
	local p = Instance.new("Part")
	p.Name = "Lamp"
	p.Size = Vector3.new(0.3, 0.3, 0.3)
	p.Transparency = 1
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Parent = folder
	local light = Instance.new("SpotLight")
	light.Range = F.RenderRange
	light.Angle = F.BeamHalfAngle * 2 + 10
	light.Brightness = 3
	light.Color = Color3.fromRGB(255, 244, 220)
	light.Shadows = true
	light.Face = Enum.NormalId.Front
	light.Parent = p

	local shaft = Instance.new("Part")
	shaft.Name = "Shaft"
	shaft.Shape = Enum.PartType.Cylinder
	shaft.Size = Vector3.new(Config.Visibility.ExposeRange, 3.5, 3.5)
	shaft.Material = Enum.Material.Neon
	shaft.Color = Color3.fromRGB(255, 240, 190)
	shaft.Transparency = 0.85
	shaft.Anchored = true
	shaft.CanCollide = false
	shaft.CanQuery = false
	shaft.CanTouch = false
	shaft.CastShadow = false
	local highlight = Instance.new("Highlight")
	highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
	highlight.FillColor = Color3.fromRGB(255, 240, 190)
	highlight.FillTransparency = 0.4
	highlight.OutlineColor = Color3.fromRGB(255, 240, 190)
	highlight.OutlineTransparency = 0.5
	highlight.Parent = shaft
	return { part = p, light = light, shaft = shaft, aim = Vector3.new(0, 0, -1) }
end

local function bodies(): { Model }
	local out = {}
	for _, other in Players:GetPlayers() do
		if other.Character then
			table.insert(out, other.Character)
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

local function render(dt: number)
	local isChimera = player:GetAttribute("Role") == "Chimera"
	local viewpoint = workspace.CurrentCamera.CFrame.Position
	local seen = {}
	for _, model in bodies() do
		local torso = model:FindFirstChild("Torso") :: BasePart?
		local on = model:GetAttribute("Flashlight") == true
		if not torso or not on then
			continue
		end
		seen[model] = true
		local lamp = lamps[model]
		if not lamp then
			lamp = makeLamp()
			lamps[model] = lamp
		end
		local target = if model == player.Character and localAim then localAim else model:GetAttribute("Aim")
		if typeof(target) == "Vector3" and target.Magnitude > 0.5 then
			lamp.aim = lamp.aim:Lerp(target.Unit, math.clamp(dt * 15, 0, 1)).Unit
		end
		local origin = (torso.CFrame * CFrame.new(0.9, 0.8, -0.5)).Position
		lamp.part.CFrame = CFrame.lookAt(origin, origin + lamp.aim)
		local showShaft = isChimera and (origin - viewpoint).Magnitude <= F.ChimeraSeesBeamsWithin + 15
		if showShaft then
			local length = lamp.shaft.Size.X
			lamp.shaft.CFrame = CFrame.lookAt(origin, origin + lamp.aim) * CFrame.new(0, 0, -length / 2) * CFrame.Angles(0, math.pi / 2, 0)
			lamp.shaft.Parent = folder
		else
			lamp.shaft.Parent = nil
		end
	end
	for model, lamp in lamps do
		if not seen[model] then
			lamp.part:Destroy()
			lamp.shaft:Destroy()
			lamps[model] = nil
		end
	end
end

function Flashlights.init(clientFolder: Folder)
	folder = Instance.new("Folder")
	folder.Name = "Flashlights"
	folder.Parent = clientFolder
	RunService.RenderStepped:Connect(render)
end

return Flashlights
