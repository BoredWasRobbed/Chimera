-- The graybox robot shell: an R6-proportioned body plus a three-segment tail, built from anchored parts
-- and posed by code every frame. It only ever exists on clients (the server's shell is just numbers),
-- so it never collides with or blocks anything.
local ShellRig = {}

export type Look = "dormant" | "booting" | "owner" | "cloaked" | "exposed" | "revealed"

local BODY_COLOR = Color3.fromRGB(58, 62, 70)
local EYE_ON = Color3.fromRGB(255, 25, 25)
local EYE_OFF = Color3.fromRGB(45, 18, 18)
local CLOAK_COLOR = Color3.fromRGB(150, 175, 220)

local BODY_PARTS = {
	{ "Torso", Vector3.new(2, 2, 1) },
	{ "Head", Vector3.new(1.4, 1.2, 1.2) },
	{ "LeftArm", Vector3.new(1, 2, 1) },
	{ "RightArm", Vector3.new(1, 2, 1) },
	{ "LeftLeg", Vector3.new(1, 2, 1) },
	{ "RightLeg", Vector3.new(1, 2, 1) },
	{ "Tail1", Vector3.new(0.6, 0.6, 1.4) },
	{ "Tail2", Vector3.new(0.5, 0.5, 1.3) },
	{ "Tail3", Vector3.new(0.4, 0.4, 1.2) },
}

local function makePart(model: Model, name: string, size: Vector3): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.Color = BODY_COLOR
	p.Material = Enum.Material.Metal
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = model
	return p
end

function ShellRig.build(name: string): Model
	local model = Instance.new("Model")
	model.Name = name
	for _, def in BODY_PARTS do
		makePart(model, def[1], def[2])
	end
	for _, eyeName in { "EyeL", "EyeR" } do
		local eye = makePart(model, eyeName, Vector3.new(0.32, 0.14, 0.1))
		eye.Material = Enum.Material.Neon
		eye.Color = EYE_ON
	end
	model.PrimaryPart = model:FindFirstChild("Torso") :: BasePart
	return model
end

-- feet: CFrame at the shell's feet, facing where it looks. phase: walk-cycle angle (radians).
-- stride: 0..1 for how big the steps are. t: clock for idle motion.
local partCache: { [Model]: { [string]: BasePart } } = setmetatable({}, { __mode = "k" }) :: any

function ShellRig.pose(model: Model, feet: CFrame, phase: number, stride: number, t: number)
	local byName = partCache[model]
	if not byName then
		byName = {}
		for _, p in model:GetChildren() do
			if p:IsA("BasePart") then
				byName[p.Name] = p
			end
		end
		partCache[model] = byName
	end
	local swing = math.sin(phase) * 0.65 * stride
	local bob = math.abs(math.cos(phase)) * 0.12 * stride

	local torso = feet * CFrame.new(0, 3 + bob, 0)
	byName.Torso.CFrame = torso
	local head = feet * CFrame.new(0, 4.6 + bob, 0)
	byName.Head.CFrame = head
	byName.EyeL.CFrame = head * CFrame.new(-0.32, 0.1, -0.61)
	byName.EyeR.CFrame = head * CFrame.new(0.32, 0.1, -0.61)

	byName.LeftLeg.CFrame = feet * CFrame.new(-0.5, 2 + bob, 0) * CFrame.Angles(swing, 0, 0) * CFrame.new(0, -1, 0)
	byName.RightLeg.CFrame = feet * CFrame.new(0.5, 2 + bob, 0) * CFrame.Angles(-swing, 0, 0) * CFrame.new(0, -1, 0)
	byName.LeftArm.CFrame = feet * CFrame.new(-1.5, 3.5 + bob, 0) * CFrame.Angles(-swing * 0.8, 0, 0) * CFrame.new(0, -0.5, 0)
	byName.RightArm.CFrame = feet * CFrame.new(1.5, 3.5 + bob, 0) * CFrame.Angles(swing * 0.8, 0, 0) * CFrame.new(0, -0.5, 0)

	local sway = math.sin(t * 1.7) * 0.25
	local c = feet * CFrame.new(0, 2.4 + bob, 0.5) * CFrame.Angles(-0.35, sway, 0)
	byName.Tail1.CFrame = c * CFrame.new(0, 0, 0.7)
	c = c * CFrame.new(0, 0, 1.4) * CFrame.Angles(-0.3, sway, 0)
	byName.Tail2.CFrame = c * CFrame.new(0, 0, 0.65)
	c = c * CFrame.new(0, 0, 1.3) * CFrame.Angles(-0.3, sway, 0)
	byName.Tail3.CFrame = c * CFrame.new(0, 0, 0.6)
end

-- How the body is drawn. `amount` (0..1) scales the cloak shimmer: 0 still, 1 at full speed.
function ShellRig.setLook(model: Model, look: Look, amount: number?)
	local a = math.clamp(amount or 0, 0, 1)
	for _, p in model:GetChildren() do
		if not p:IsA("BasePart") then
			continue
		end
		local isEye = p.Name == "EyeL" or p.Name == "EyeR"
		if isEye then
			if look == "dormant" then
				p.Material = Enum.Material.SmoothPlastic
				p.Color = EYE_OFF
				p.Transparency = 0
			elseif look == "cloaked" then
				p.Transparency = 1
			elseif look == "exposed" then
				p.Material = Enum.Material.Neon
				p.Color = EYE_ON
				p.Transparency = 0.5
			else
				p.Material = Enum.Material.Neon
				p.Color = EYE_ON
				p.Transparency = 0
			end
		elseif look == "cloaked" then
			p.Material = Enum.Material.ForceField
			p.Color = CLOAK_COLOR
			p.Transparency = 0.82 - 0.3 * a
		elseif look == "exposed" then
			p.Material = Enum.Material.ForceField
			p.Color = Color3.fromRGB(220, 230, 255)
			p.Transparency = 0.25 + 0.25 * a
		elseif look == "owner" then
			p.Material = Enum.Material.Metal
			p.Color = BODY_COLOR
			p.Transparency = 0.35
		else
			p.Material = Enum.Material.Metal
			p.Color = BODY_COLOR
			p.Transparency = 0
		end
	end
end

return ShellRig
