-- The graybox robot shell: an R6-proportioned body plus a three-segment tail, built from anchored parts
-- and posed by code every frame. It only ever exists on clients (the server's shell is just numbers).
-- Module parts (claws, leap fin, decoy emitter, overload spool) show only on a Revealed shell and on the
-- Chimera's own view, so sharp mercs can read the build.
local ShellRig = {}

export type Look = "dormant" | "booting" | "owner" | "cloaked" | "exposed" | "revealed"
export type Action = { kind: string, progress: number }

local BODY_COLOR = Color3.fromRGB(58, 62, 70)
local EYE_ON = Color3.fromRGB(255, 25, 25)
local EYE_OFF = Color3.fromRGB(45, 18, 18)
local CLOAK_COLOR = Color3.fromRGB(150, 175, 220)
local MODULE_COLOR = Color3.fromRGB(190, 90, 255)

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

local MODULE_PARTS = {
	{ "ClawL", Vector3.new(0.2, 0.3, 1.8) }, -- Energy Claws
	{ "ClawR", Vector3.new(0.2, 0.3, 1.8) },
	{ "LeapFin", Vector3.new(0.3, 1.4, 0.9) }, -- System Leap
	{ "DecoyEmitter", Vector3.new(0.5, 0.5, 0.5) }, -- Static Decoy
	{ "OverloadSpool", Vector3.new(0.9, 1.2, 0.7) }, -- Overload
}

local MODULE_NAMES = {}
for _, def in MODULE_PARTS do
	MODULE_NAMES[def[1]] = true
end

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

-- withModules: the shell the Chimera is in (dormant shells in docks carry no build).
function ShellRig.build(name: string, withModules: boolean?): Model
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
	if withModules then
		for _, def in MODULE_PARTS do
			local p = makePart(model, def[1], def[2])
			p.Color = MODULE_COLOR
			p.Material = Enum.Material.Neon
			p.Transparency = 1
		end
	end
	model.PrimaryPart = model:FindFirstChild("Torso") :: BasePart
	return model
end

local partCache: { [Model]: { [string]: BasePart } } = setmetatable({}, { __mode = "k" }) :: any

local function partsOf(model: Model): { [string]: BasePart }
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
	return byName
end

-- feet: CFrame at the shell's feet, facing where it looks. phase: walk-cycle angle (radians).
-- stride: 0..1 for how big the steps are. t: clock for idle motion. action: an attack, assimilation or
-- leap channel in progress, which overrides the arms.
function ShellRig.pose(model: Model, feet: CFrame, phase: number, stride: number, t: number, action: Action?)
	local byName = partsOf(model)
	local swing = math.sin(phase) * 0.65 * stride
	local bob = math.abs(math.cos(phase)) * 0.12 * stride

	local hunch = 0
	local armL, armR = -swing * 0.8, swing * 0.8
	if action then
		local p = math.clamp(action.progress, 0, 1)
		if action.kind == "attack" then
			-- A fast two-handed rake: up, then down through the target.
			local arc = if p < 0.4 then -2.6 * (p / 0.4) else -2.6 + 2.2 * ((p - 0.4) / 0.6)
			armL, armR = arc, arc
			hunch = 0.25
		elseif action.kind == "assimilate" then
			hunch = 0.6
			armL, armR = -1.2 + math.sin(t * 8) * 0.15, -1.2 - math.sin(t * 8) * 0.15
		elseif action.kind == "leap" then
			armL, armR = -2.9, -2.9
			hunch = -0.1
		end
	end

	local body = feet * CFrame.new(0, 2 + bob, 0) * CFrame.Angles(-hunch, 0, 0)
	byName.Torso.CFrame = body * CFrame.new(0, 1, 0)
	local head = body * CFrame.new(0, 2.6, 0)
	byName.Head.CFrame = head
	byName.EyeL.CFrame = head * CFrame.new(-0.32, 0.1, -0.61)
	byName.EyeR.CFrame = head * CFrame.new(0.32, 0.1, -0.61)

	byName.LeftLeg.CFrame = feet * CFrame.new(-0.5, 2 + bob, 0) * CFrame.Angles(swing, 0, 0) * CFrame.new(0, -1, 0)
	byName.RightLeg.CFrame = feet * CFrame.new(0.5, 2 + bob, 0) * CFrame.Angles(-swing, 0, 0) * CFrame.new(0, -1, 0)
	local leftArm = body * CFrame.new(-1.5, 1.5, 0) * CFrame.Angles(armL, 0, 0) * CFrame.new(0, -0.5, 0)
	local rightArm = body * CFrame.new(1.5, 1.5, 0) * CFrame.Angles(armR, 0, 0) * CFrame.new(0, -0.5, 0)
	byName.LeftArm.CFrame = leftArm
	byName.RightArm.CFrame = rightArm

	local sway = math.sin(t * 1.7) * 0.25
	local c = feet * CFrame.new(0, 2.4 + bob, 0.5) * CFrame.Angles(-0.35, sway, 0)
	byName.Tail1.CFrame = c * CFrame.new(0, 0, 0.7)
	c = c * CFrame.new(0, 0, 1.4) * CFrame.Angles(-0.3, sway, 0)
	byName.Tail2.CFrame = c * CFrame.new(0, 0, 0.65)
	c = c * CFrame.new(0, 0, 1.3) * CFrame.Angles(-0.3, sway, 0)
	byName.Tail3.CFrame = c * CFrame.new(0, 0, 0.6)

	if byName.ClawL then
		byName.ClawL.CFrame = leftArm * CFrame.new(0, -1.1, -0.6) * CFrame.Angles(-0.4, 0, 0)
		byName.ClawR.CFrame = rightArm * CFrame.new(0, -1.1, -0.6) * CFrame.Angles(-0.4, 0, 0)
		byName.LeapFin.CFrame = body * CFrame.new(0, 1.4, 0.75)
		byName.DecoyEmitter.CFrame = body * CFrame.new(1.25, 2.25, -0.1)
		byName.OverloadSpool.CFrame = body * CFrame.new(0, 0.8, 0.85)
	end
end

-- How the body is drawn. `amount` (0..1) scales the cloak shimmer: 0 still, 1 at full speed.
function ShellRig.setLook(model: Model, look: Look, amount: number?)
	local a = math.clamp(amount or 0, 0, 1)
	local showModules = look == "revealed" or look == "owner"
	for _, p in model:GetChildren() do
		if not p:IsA("BasePart") then
			continue
		end
		if MODULE_NAMES[p.Name] then
			p.Transparency = if showModules then (if look == "owner" then 0.3 else 0) else 1
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
			-- Phase Weave: a balanced cloak whose shimmer grows with speed.
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

-- Merc clients make the bodies they perceive solid, so they bump into the shell and their aim lands on
-- it (the server still decides every hit).
function ShellRig.setSolid(model: Model, solid: boolean)
	for name, part in partsOf(model) do
		if name == "Torso" or name == "Head" or name == "LeftLeg" or name == "RightLeg" then
			part.CanCollide = solid
		end
		if not MODULE_NAMES[name] then
			part.CanQuery = solid
		end
	end
end

return ShellRig
