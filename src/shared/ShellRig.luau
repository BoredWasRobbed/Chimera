-- The robot shell's body: an R6 frame built from six body modules (head, torso, two arms, two legs)
-- whose armour panels swing open and lock shut, plus a three-segment tail. Every part is anchored and
-- posed by code each frame, and the body only ever exists on clients (the server's shell is numbers).
--
-- A body module is a dark inner frame wrapped in hinged panels. A dormant shell stands in its dock
-- unformed: its panels hang open, its head is bowed and its arms sag off the shoulders. While the Chimera
-- boots it, the frame glows and the panels twitch part-way shut. Once the Chimera takes it, the modules
-- lock into place in turn (legs, torso, arms, head), each one flashing red along its seams as it locks;
-- the visor slams shut last, the eyes ignite and the build's module parts slide out. Then the body
-- settles into its look.
--
-- The six R6 blocks and the tail segments are the hull: they collide and take aim, and Phase Weave's
-- shimmer is drawn on them. A Cloaked or Exposed body shows only the hull, exactly as before, so the
-- panels never make a cloaked shell easier to see.
--
-- Module parts (claws, leap fin, decoy emitter, overload spool) are the Chimera's ability modules. They
-- show only on a Revealed shell and on the Chimera's own view, so sharp mercs can read the build.
local ShellRig = {}

export type Look = "dormant" | "booting" | "owner" | "cloaked" | "exposed" | "revealed"
export type Action = { kind: string, progress: number }

-- The take, in seconds after the Chimera takes the shell.
ShellRig.FORM_SECONDS = 1.25 -- every module locked, the eyes lit and the module parts out
ShellRig.SETTLE_SECONDS = 0.35 -- then the body fades into its look (for mercs: the cloak engages)
ShellRig.PRIMED = 0.3 -- how far a booted shell's panels have closed (0 hanging open, 1 locked)

local FORM_SECONDS = ShellRig.FORM_SECONDS
local SETTLE_SECONDS = ShellRig.SETTLE_SECONDS
local PRIMED = ShellRig.PRIMED
local START = { RightLeg = 0, LeftLeg = 0.06, Torso = 0.22, RightArm = 0.45, LeftArm = 0.5, Head = 0.66 }
local STEP = 0.07 -- between one panel and the next within a module
local SWING_SECONDS = 0.24 -- one panel swinging shut
local SEAT_SECONDS = 0.3 -- a sagging module moving into place
local FLASH_SECONDS = 0.3 -- the seams' flash as a module locks
local DEPLOY_AT, DEPLOY_SECONDS = 1.0, 0.25 -- the module parts sliding out

local ARMOR = Color3.fromRGB(58, 62, 70)
local TRIM = Color3.fromRGB(84, 90, 101)
local DARK = Color3.fromRGB(40, 43, 50)
local FRAME_OFF = Color3.fromRGB(25, 27, 31)
local GLOW = Color3.fromRGB(105, 10, 10) -- a powered frame: the seams glow dull red
local GLOW_LOW = Color3.fromRGB(40, 4, 4)
local GLOW_HOT = Color3.fromRGB(255, 40, 30)
local GLOW_FLASH = Color3.fromRGB(255, 175, 160)
local EYE_ON = Color3.fromRGB(255, 25, 25)
local EYE_OFF = Color3.fromRGB(45, 18, 18)
local CLOAK_COLOR = Color3.fromRGB(150, 175, 220)
local EXPOSED_COLOR = Color3.fromRGB(220, 230, 255)
local MODULE_COLOR = Color3.fromRGB(190, 90, 255)
local TONES = { armor = ARMOR, trim = TRIM, dark = DARK }

local METAL = Enum.Material.Metal
local NEON = Enum.Material.Neon
local PLASTIC = Enum.Material.SmoothPlastic
local FORCE_FIELD = Enum.Material.ForceField

local V = Vector3.new
local NONE = Vector3.zero

--------------------------------------------------------------------------------------------------------
-- The body modules. Each fills one R6 block when formed (module space: the block's centre, +X the
-- shell's right, +Y up, -Z its front). `frame` is the inner frame's extent: x0, x1, y0, y1, z0, z1.

local MODULES = {
	Torso = { size = V(2, 2, 1), frame = { -0.86, 0.86, -1, 0.86, -0.36, 0.36 } },
	Head = { size = V(1.4, 1.2, 1.2), frame = { -0.56, 0.56, -0.6, 0.46, -0.46, 0.46 } },
	LeftArm = { size = V(1, 2, 1), frame = { -0.36, 0.36, -0.96, 0.96, -0.36, 0.36 } },
	RightArm = { size = V(1, 2, 1), frame = { -0.36, 0.36, -0.96, 0.96, -0.36, 0.36 } },
	LeftLeg = { size = V(1, 2, 1), frame = { -0.36, 0.36, -0.76, 1, -0.36, 0.36 } },
	RightLeg = { size = V(1, 2, 1), frame = { -0.36, 0.36, -0.76, 1, -0.36, 0.36 } },
}
local MODULE_ORDER = { "Torso", "Head", "LeftArm", "RightArm", "LeftLeg", "RightLeg" }
local HULL_PAD = 0.02 -- the hull sits just outside the panels, so the two never share a surface

-- How far a module hangs out of place on an unformed shell, at its joint (the neck, a shoulder).
local SAG = {
	Head = { pos = V(0, -0.16, -0.06), rot = V(-0.42, 0, 0) }, -- bowed, face down
	LeftArm = { pos = V(-0.16, -0.1, 0), rot = V(0.12, 0, -0.1) }, -- hanging off the shoulder
	RightArm = { pos = V(0.16, -0.1, 0), rot = V(0.12, 0, 0.1) },
}
local SLUMP, SLUMP_DROP = 0.14, 0.08 -- an unformed torso leans forward and sinks

local TAIL = {
	{ "Tail1", V(0.6, 0.6, 1.4) },
	{ "Tail2", V(0.5, 0.5, 1.3) },
	{ "Tail3", V(0.4, 0.4, 1.2) },
}

-- The Chimera's ability modules, shown on the body (see the header).
local MODULE_PARTS = {
	{ "ClawL", V(0.2, 0.3, 1.8) }, -- Energy Claws
	{ "ClawR", V(0.2, 0.3, 1.8) },
	{ "LeapFin", V(0.3, 1.4, 0.9) }, -- System Leap
	{ "DecoyEmitter", V(0.5, 0.5, 0.5) }, -- Static Decoy
	{ "OverloadSpool", V(0.9, 1.2, 0.7) }, -- Overload
}

local MODULE_NAMES = {}
for _, def in MODULE_PARTS do
	MODULE_NAMES[def[1]] = true
end

--------------------------------------------------------------------------------------------------------
-- The panels. Each is written as its extent in its module's space when locked (x0, x1, y0, y1, z0, z1;
-- panels are 0.14 thick and leave 0.06 seams), plus how it opens: it turns by `swing` (radians about
-- X, Y, Z) on a hinge along one of its edges, and moves by `push`. `step` orders the panels within a
-- module: step 0 locks first.

type PanelDef = {
	name: string,
	module: string,
	tone: string,
	step: number,
	size: Vector3,
	at: Vector3,
	hinge: Vector3,
	swing: Vector3,
	push: Vector3,
}

local PANELS: { PanelDef } = {}

local function edge(name: string, size: Vector3): Vector3
	local h = size / 2
	if name == "top" then
		return V(0, h.Y, 0)
	elseif name == "bottom" then
		return V(0, -h.Y, 0)
	elseif name == "left" then
		return V(-h.X, 0, 0)
	elseif name == "right" then
		return V(h.X, 0, 0)
	elseif name == "front" then
		return V(0, 0, -h.Z)
	elseif name == "back" then
		return V(0, 0, h.Z)
	end
	return NONE
end

local function panel(module: string, name: string, tone: string, step: number, x0: number, x1: number, y0: number, y1: number, z0: number, z1: number, hinge: string, swing: Vector3, push: Vector3)
	local size = V(x1 - x0, y1 - y0, z1 - z0)
	table.insert(PANELS, {
		name = `{module}_{name}`,
		module = module,
		tone = tone,
		step = step,
		size = size,
		at = V((x0 + x1) / 2, (y0 + y1) / 2, (z0 + z1) / 2),
		hinge = edge(hinge, size),
		swing = swing,
		push = push,
	})
end

-- Torso: chest doors that swing out from the middle, hatches over the stomach and back, side plates
-- and a collar under the head.
panel("Torso", "AbLower", "armor", 0, -1, 1, -1, -0.48, -0.5, -0.36, "bottom", V(-0.4, 0, 0), V(0, -0.02, -0.06))
panel("Torso", "BackLower", "armor", 0, -1, 1, -1, -0.03, 0.36, 0.5, "bottom", V(0.45, 0, 0), V(0, -0.02, 0.06))
panel("Torso", "AbUpper", "armor", 1, -1, 1, -0.42, 0.04, -0.5, -0.36, "bottom", V(-0.55, 0, 0), V(0, -0.04, -0.05))
panel("Torso", "BackUpper", "armor", 1, -1, 1, 0.03, 1, 0.36, 0.5, "top", V(-0.5, 0, 0), V(0, 0.04, 0.06))
panel("Torso", "SideL", "dark", 1, -1, -0.86, -1, 1, -0.36, 0.36, "bottom", V(0, 0, 0.12), V(-0.04, 0, 0))
panel("Torso", "SideR", "dark", 1, 0.86, 1, -1, 1, -0.36, 0.36, "bottom", V(0, 0, -0.12), V(0.04, 0, 0))
panel("Torso", "ChestL", "armor", 2, -1, -0.03, 0.1, 1, -0.5, -0.36, "left", V(0, 0.85, 0), V(-0.06, 0, -0.06))
panel("Torso", "ChestR", "armor", 2, 0.03, 1, 0.1, 1, -0.5, -0.36, "right", V(0, -0.85, 0), V(0.06, 0, -0.06))
panel("Torso", "Collar", "trim", 3, -0.86, 0.86, 0.86, 1, -0.36, 0.36, "center", NONE, V(0, -0.1, 0))

-- Head: cheeks that swing out, a cap that lifts, a jaw that drops and a visor (the brow) that flips up
-- and slams down last. The eyes sit in the slit between the jaw and the visor.
panel("Head", "Back", "armor", 0, -0.7, 0.7, -0.6, 0.6, 0.46, 0.6, "bottom", V(0.35, 0, 0), V(0, 0, 0.05))
panel("Head", "CheekL", "dark", 0, -0.7, -0.56, -0.6, 0.46, -0.46, 0.46, "back", V(0, 0.5, 0), V(-0.04, 0, 0))
panel("Head", "CheekR", "dark", 0, 0.56, 0.7, -0.6, 0.46, -0.46, 0.46, "back", V(0, -0.5, 0), V(0.04, 0, 0))
panel("Head", "Jaw", "armor", 1, -0.7, 0.7, -0.6, -0.03, -0.6, -0.46, "top", V(0.5, 0, 0), V(0, -0.06, -0.04))
panel("Head", "Cap", "armor", 2, -0.7, 0.7, 0.46, 0.6, -0.46, 0.46, "back", V(0.45, 0, 0), V(0, 0.08, 0.04))
panel("Head", "Brow", "trim", 3, -0.7, 0.7, 0.23, 0.6, -0.6, -0.46, "top", V(1.1, 0, 0), V(0, 0.06, -0.02))

-- `out` is +1 for the right side and -1 for the left: x extents are written for the right side and
-- mirrored, and so are turns about Y and Z.
local function mirrored(out: number, x0: number, x1: number): (number, number)
	if out > 0 then
		return x0, x1
	end
	return -x1, -x0
end

-- Arms: a gauntlet, plates that open like doors from the outer edge, and a pauldron that lifts off the
-- shoulder last.
local function arm(module: string, out: number)
	local outer = if out > 0 then "right" else "left"
	local inner = if out > 0 then "left" else "right"
	local ox0, ox1 = mirrored(out, 0.36, 0.5)
	local ix0, ix1 = mirrored(out, -0.5, -0.36)
	local px0, px1 = mirrored(out, -0.5, 0.6)
	panel(module, "Gauntlet", "dark", 0, -0.52, 0.52, -1, -0.64, -0.52, 0.52, "center", V(0.25, 0, 0), V(0, -0.2, -0.05))
	panel(module, "Outer", "armor", 0, ox0, ox1, -0.6, 0.26, -0.36, 0.36, "top", V(0, 0, 0.45 * out), V(0.05 * out, 0, 0))
	panel(module, "Inner", "dark", 0, ix0, ix1, -0.6, 0.26, -0.36, 0.36, "top", V(0, 0, -0.2 * out), NONE)
	panel(module, "Front", "armor", 1, -0.5, 0.5, -0.6, 0.26, -0.5, -0.36, outer, V(0, -0.6 * out, 0), V(0.03 * out, 0, -0.04))
	panel(module, "Back", "armor", 1, -0.5, 0.5, -0.6, 0.26, 0.36, 0.5, outer, V(0, 0.6 * out, 0), V(0.03 * out, 0, 0.04))
	panel(module, "Pauldron", "trim", 2, px0, px1, 0.32, 1, -0.55, 0.55, inner, V(0, 0, 0.35 * out), V(0.12 * out, 0.2, 0))
end

-- Legs: the foot stays planted; shin, calf and side plates open, then the thigh, then a knee cap that
-- snaps on last.
local function leg(module: string, out: number)
	local ox0, ox1 = mirrored(out, 0.36, 0.5)
	local ix0, ix1 = mirrored(out, -0.5, -0.36)
	panel(module, "Foot", "dark", 0, -0.52, 0.52, -1, -0.76, -0.64, 0.5, "center", NONE, NONE)
	panel(module, "Shin", "armor", 0, -0.5, 0.5, -0.7, 0.02, -0.5, -0.36, "bottom", V(-0.45, 0, 0), V(0, 0, -0.04))
	panel(module, "Calf", "armor", 0, -0.5, 0.5, -0.7, 1, 0.36, 0.5, "top", V(-0.35, 0, 0), V(0, 0, 0.04))
	panel(module, "Outer", "dark", 0, ox0, ox1, -0.7, 1, -0.36, 0.36, "top", V(0, 0, 0.3 * out), V(0.03 * out, 0, 0))
	panel(module, "Inner", "dark", 0, ix0, ix1, -0.7, 1, -0.36, 0.36, "center", NONE, V(0, -0.06, 0))
	panel(module, "Thigh", "armor", 1, -0.5, 0.5, 0.08, 1, -0.5, -0.36, "top", V(0.45, 0, 0), V(0, 0, -0.04))
	panel(module, "KneeCap", "trim", 2, -0.3, 0.3, -0.12, 0.2, -0.58, -0.42, "center", NONE, V(0, 0, -0.25))
end

arm("LeftArm", -1)
arm("RightArm", 1)
leg("LeftLeg", -1)
leg("RightLeg", 1)

-- When each module has fully locked, and when the eyes ignite (as the visor locks).
local LOCK_AT: { [string]: number } = {}
for _, def in PANELS do
	LOCK_AT[def.module] = math.max(LOCK_AT[def.module] or 0, START[def.module] + def.step * STEP + SWING_SECONDS)
end
local EYES_AT = LOCK_AT.Head

--------------------------------------------------------------------------------------------------------
-- Building. Every shell is a clone of one prototype (with or without module parts). All parts are
-- direct children of the model, so code that walks a shell's parts or looks for its model still works.

type Panel = {
	part: BasePart,
	def: PanelDef,
	locked: CFrame,
	hinge: CFrame,
	unhinge: CFrame,
	start: number, -- seconds after the take when it starts swinging shut
	wobble: number, -- its twitch's phase while the shell boots
}

type Rig = {
	parts: { BasePart }, -- every part, in posing order (for BulkMoveTo)
	cframes: { CFrame },
	hull: { [string]: BasePart },
	hullList: { BasePart },
	frames: { [string]: BasePart },
	frameAt: { [string]: CFrame },
	panels: { Panel },
	tailArmor: { BasePart },
	eyes: { BasePart },
	moduleParts: { [string]: BasePart },
	painted: { [BasePart]: { any } },
	modulesAt: { [string]: CFrame },
	-- state
	dormant: boolean, -- in a dock: posed by closure and twitch instead of the take's clock
	closure: number,
	twitch: number,
	clock: number,
	age: number, -- seconds since the take; math.huge once formed
	look: Look,
	amount: number,
	changing: boolean, -- the last pose repainted because the look was still changing
}

local function newPart(parent: Instance, name: string, size: Vector3, color: Color3, material: Enum.Material): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.Color = color
	p.Material = material
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = parent
	return p
end

local prototypes: { [boolean]: Model } = {}

local function prototype(withModules: boolean): Model
	local cached = prototypes[withModules]
	if cached then
		return cached
	end
	local model = Instance.new("Model")
	for _, name in MODULE_ORDER do
		local def = MODULES[name]
		local hull = newPart(model, name, def.size + V(HULL_PAD, HULL_PAD, HULL_PAD), ARMOR, METAL)
		hull.Transparency = 1
		local f = def.frame
		newPart(model, `{name}Frame`, V(f[2] - f[1], f[4] - f[3], f[6] - f[5]), FRAME_OFF, METAL)
	end
	for _, def in TAIL do
		local hull = newPart(model, def[1], def[2] + V(HULL_PAD, HULL_PAD, HULL_PAD), ARMOR, METAL)
		hull.Transparency = 1
		newPart(model, `{def[1]}Armor`, def[2], ARMOR, METAL)
	end
	for _, def in PANELS do
		newPart(model, def.name, def.size, TONES[def.tone], METAL)
	end
	for _, eyeName in { "EyeL", "EyeR" } do
		newPart(model, eyeName, V(0.32, 0.14, 0.1), EYE_OFF, PLASTIC)
	end
	if withModules then
		for _, def in MODULE_PARTS do
			local p = newPart(model, def[1], def[2], MODULE_COLOR, NEON)
			p.Transparency = 1
		end
	end
	prototypes[withModules] = model
	return model
end

local rigs: { [Model]: Rig } = setmetatable({}, { __mode = "k" }) :: any

local function newRig(model: Model): Rig
	local byName: { [string]: BasePart } = {}
	for _, child in model:GetChildren() do
		if child:IsA("BasePart") then
			byName[child.Name] = child
		end
	end
	local rig: Rig = {
		parts = {},
		cframes = {},
		hull = {},
		hullList = {},
		frames = {},
		frameAt = {},
		panels = {},
		tailArmor = {},
		eyes = { byName.EyeL, byName.EyeR },
		moduleParts = {},
		painted = {},
		modulesAt = {},
		dormant = false,
		closure = 0,
		twitch = 0,
		clock = 0,
		age = math.huge,
		look = "revealed",
		amount = 0,
		changing = false,
	}
	local function add(part: BasePart)
		table.insert(rig.parts, part)
		table.insert(rig.cframes, CFrame.identity)
		rig.painted[part] = { part.Material, part.Color, part.Transparency }
	end
	for _, name in MODULE_ORDER do
		local hull = byName[name]
		rig.hull[name] = hull
		table.insert(rig.hullList, hull)
		add(hull)
		local frame = byName[`{name}Frame`]
		rig.frames[name] = frame
		local f = MODULES[name].frame
		rig.frameAt[name] = CFrame.new((f[1] + f[2]) / 2, (f[3] + f[4]) / 2, (f[5] + f[6]) / 2)
		add(frame)
	end
	for _, def in TAIL do
		local hull = byName[def[1]]
		rig.hull[def[1]] = hull
		table.insert(rig.hullList, hull)
		add(hull)
		local armor = byName[`{def[1]}Armor`]
		table.insert(rig.tailArmor, armor)
		add(armor)
	end
	for index, def in PANELS do
		local part = byName[def.name]
		table.insert(rig.panels, {
			part = part,
			def = def,
			locked = CFrame.new(def.at),
			hinge = CFrame.new(def.hinge),
			unhinge = CFrame.new(-def.hinge),
			start = START[def.module] + def.step * STEP,
			wobble = index * 2.39996, -- golden angle: neighbours twitch out of step
		})
		add(part)
	end
	add(byName.EyeL)
	add(byName.EyeR)
	for _, def in MODULE_PARTS do
		local part = byName[def[1]]
		if part then
			rig.moduleParts[def[1]] = part
			add(part)
		end
	end
	return rig
end

-- withModules: the shell the Chimera is in (dormant shells in docks carry no build).
function ShellRig.build(name: string, withModules: boolean?): Model
	local model = prototype(withModules == true):Clone()
	model.Name = name
	model.PrimaryPart = model:FindFirstChild("Torso") :: BasePart
	rigs[model] = newRig(model)
	return model
end

--------------------------------------------------------------------------------------------------------
-- Assembly state.

-- A shell in a dock. closure: how far its panels have drawn in (0 hanging open, up to PRIMED as a boot
-- completes). twitch: 0..1, how hard they shudder while it boots. clock: any running time, for the
-- shudder.
function ShellRig.setDormant(model: Model, closure: number, twitch: number, clock: number)
	local rig = rigs[model]
	if rig then
		rig.dormant = true
		rig.closure = math.clamp(closure, 0, 1)
		rig.twitch = math.clamp(twitch, 0, 1)
		rig.clock = clock
	end
end

-- A shell the Chimera took `age` seconds ago: the modules lock in over FORM_SECONDS, then the body
-- settles into its look. nil: fully formed (a shell that was already up when this client first saw it).
function ShellRig.setAssembly(model: Model, age: number?)
	local rig = rigs[model]
	if rig then
		rig.dormant = false
		rig.age = if age then math.max(age, 0) else math.huge
	end
end

local function smooth(p: number): number
	return p * p * (3 - 2 * p)
end

-- Fast, overshooting a little as it slams into place.
local function slam(p: number): number
	local q = p - 1
	return 1 + 2.4 * q * q * q + 1.4 * q * q
end

local function moduleAlpha(rig: Rig, name: string): number
	if rig.dormant then
		return rig.closure
	end
	local p = (rig.age - START[name]) / SEAT_SECONDS
	if p >= 1 then
		return 1
	elseif p <= 0 then
		return PRIMED
	end
	return PRIMED + (1 - PRIMED) * smooth(p)
end

local function panelAlpha(rig: Rig, p: Panel): number
	if rig.dormant then
		if rig.twitch > 0 then
			return math.max(0, rig.closure + math.sin(rig.clock * 27 + p.wobble) * 0.05 * rig.twitch)
		end
		return rig.closure
	end
	local t = (rig.age - p.start) / SWING_SECONDS
	if t >= 1 then
		return 1
	elseif t <= 0 then
		return PRIMED
	end
	return PRIMED + (1 - PRIMED) * slam(t)
end

-- A panel's pose in its module's space: k = 1 hanging open, 0 locked (a little below 0 while it slams).
local function panelAt(p: Panel, alpha: number): CFrame
	if alpha == 1 then
		return p.locked
	end
	local k = 1 - alpha
	local swing = p.def.swing
	return CFrame.new(p.def.push * k) * p.locked * p.hinge * CFrame.Angles(swing.X * k, swing.Y * k, swing.Z * k) * p.unhinge
end

local function sagged(name: string, k: number): CFrame
	local sag = SAG[name]
	if not sag or k <= 0 then
		return CFrame.identity
	end
	local rot = sag.rot * k
	return CFrame.new(sag.pos * k) * CFrame.Angles(rot.X, rot.Y, rot.Z)
end

local function deployAlpha(rig: Rig): number
	if rig.dormant then
		return 0
	end
	return smooth(math.clamp((rig.age - DEPLOY_AT) / DEPLOY_SECONDS, 0, 1))
end

local function animating(rig: Rig): boolean
	if rig.dormant then
		return rig.twitch > 0 or rig.look == "booting"
	end
	return rig.age < FORM_SECONDS + SETTLE_SECONDS
end

--------------------------------------------------------------------------------------------------------
-- Looks.

local function paint(rig: Rig, part: BasePart, material: Enum.Material, color: Color3, transparency: number)
	local cache = rig.painted[part]
	if cache[1] ~= material then
		part.Material = material
		cache[1] = material
	end
	if cache[2] ~= color then
		part.Color = color
		cache[2] = color
	end
	if cache[3] ~= transparency then
		part.Transparency = transparency
		cache[3] = transparency
	end
end

local function lerp(a: number, b: number, t: number): number
	return a + (b - a) * t
end

-- A frame while the shell boots: a ragged red flicker that grows with the boot.
local function bootGlow(rig: Rig): Color3
	local c = rig.clock
	local flicker = 0.5 + 0.5 * math.sin(c * 31) * math.sin(c * 13 + 0.7)
	return GLOW_LOW:Lerp(GLOW_HOT, rig.twitch * (0.35 + 0.65 * flicker))
end

-- A module's frame during the take: hot and flickering until the module locks, a flash as it locks,
-- then the steady glow.
local function formGlow(rig: Rig, name: string): Color3
	local since = rig.age - LOCK_AT[name]
	if since < 0 then
		return GLOW:Lerp(GLOW_HOT, 0.6 + 0.4 * math.sin(rig.age * 41 + START[name] * 9))
	elseif since < FLASH_SECONDS then
		local f = 1 - since / FLASH_SECONDS
		return GLOW:Lerp(GLOW_FLASH, f * f)
	end
	return GLOW
end

local function apply(rig: Rig)
	local look, amount = rig.look, rig.amount
	local cloak = look == "cloaked" or look == "exposed"
	local hullT, hullColor = 1, CLOAK_COLOR
	if look == "cloaked" then
		-- Phase Weave: a balanced cloak whose shimmer grows with speed.
		hullT = 0.82 - 0.3 * amount
	elseif look == "exposed" then
		hullT, hullColor = 0.25 + 0.25 * amount, EXPOSED_COLOR
	end

	-- Where the take is: forming (modules locking, drawn as a bare powered body), then settling (fading
	-- into the look), then settled.
	local forming, settle = false, 1
	if not rig.dormant and rig.age < FORM_SECONDS + SETTLE_SECONDS then
		forming = rig.age < FORM_SECONDS
		settle = math.clamp((rig.age - FORM_SECONDS) / SETTLE_SECONDS, 0, 1)
	end
	local unpowered = look == "dormant" or (rig.dormant and look ~= "booting")

	-- The hull: Phase Weave's shimmer, or nothing.
	for _, part in rig.hullList do
		if cloak then
			paint(rig, part, FORCE_FIELD, hullColor, lerp(1, hullT, settle))
		else
			paint(rig, part, METAL, ARMOR, 1)
		end
	end

	-- Panels and tail armour: solid, see-through on the Chimera's own view, gone under the cloak.
	local armorT = if cloak then 1 elseif look == "owner" then 0.35 else 0
	armorT = lerp(0, armorT, settle)
	for _, p in rig.panels do
		paint(rig, p.part, METAL, TONES[p.def.tone], armorT)
	end
	for _, part in rig.tailArmor do
		paint(rig, part, METAL, ARMOR, armorT)
	end

	-- Frames: dark when unpowered, glowing red once the Chimera is in (showing through the seams). The
	-- Chimera's own see-through body keeps only a trace of the glow, or it would look red all over.
	local frameT = if cloak then 1 elseif look == "owner" then 0.8 else 0
	frameT = lerp(0, frameT, settle)
	for name, frame in rig.frames do
		if unpowered then
			paint(rig, frame, METAL, FRAME_OFF, 0)
		elseif rig.dormant then
			paint(rig, frame, NEON, bootGlow(rig), 0)
		elseif forming then
			paint(rig, frame, NEON, formGlow(rig, name), 0)
		else
			paint(rig, frame, NEON, GLOW, frameT)
		end
	end

	-- Eyes: dark until the visor locks, then they ignite (with one flicker).
	for _, eye in rig.eyes do
		if unpowered then
			paint(rig, eye, PLASTIC, EYE_OFF, 0)
		elseif rig.dormant then
			paint(rig, eye, NEON, EYE_ON, 0)
		elseif forming then
			local since = rig.age - EYES_AT
			local lit = since >= 0 and not (since > 0.05 and since < 0.1)
			paint(rig, eye, if lit then NEON else PLASTIC, if lit then EYE_ON else EYE_OFF, 0)
		else
			local eyeT = if look == "cloaked" then 1 elseif look == "exposed" then 0.5 else 0
			paint(rig, eye, NEON, EYE_ON, lerp(0, eyeT, settle))
		end
	end

	-- Module parts: only on a Revealed shell and the Chimera's own view, once they've slid out.
	local showModules = (look == "revealed" or look == "owner") and deployAlpha(rig) > 0
	for _, part in rig.moduleParts do
		local t = if showModules then (if look == "owner" then 0.3 else 0) else 1
		paint(rig, part, NEON, MODULE_COLOR, t)
	end
end

-- How the body is drawn. `amount` (0..1) scales the cloak shimmer: 0 still, 1 at full speed.
function ShellRig.setLook(model: Model, look: Look, amount: number?)
	local rig = rigs[model]
	if not rig then
		return
	end
	rig.look = look
	rig.amount = math.clamp(amount or 0, 0, 1)
	apply(rig)
end

--------------------------------------------------------------------------------------------------------
-- Posing.

-- feet: CFrame at the shell's feet, facing where it looks. phase: walk-cycle angle (radians).
-- stride: 0..1 for how big the steps are. t: clock for idle motion. action: an attack, assimilation or
-- leap channel in progress, which overrides the arms.
function ShellRig.pose(model: Model, feet: CFrame, phase: number, stride: number, t: number, action: Action?)
	local rig = rigs[model]
	if not rig then
		return
	end
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

	-- Each module's place: an unformed torso slumps, the head bows and the arms sag.
	local torsoK = 1 - moduleAlpha(rig, "Torso")
	local body = feet * CFrame.new(0, 2 + bob - SLUMP_DROP * torsoK, 0) * CFrame.Angles(-(hunch + SLUMP * torsoK), 0, 0)
	local at = rig.modulesAt
	at.Torso = body * CFrame.new(0, 1, 0)
	at.Head = body * CFrame.new(0, 2, 0) * sagged("Head", 1 - moduleAlpha(rig, "Head")) * CFrame.new(0, 0.6, 0)
	at.LeftLeg = feet * CFrame.new(-0.5, 2 + bob, 0) * CFrame.Angles(swing, 0, 0) * CFrame.new(0, -1, 0)
	at.RightLeg = feet * CFrame.new(0.5, 2 + bob, 0) * CFrame.Angles(-swing, 0, 0) * CFrame.new(0, -1, 0)
	at.LeftArm = body * CFrame.new(-1.5, 1.5, 0) * CFrame.Angles(armL, 0, 0) * sagged("LeftArm", 1 - moduleAlpha(rig, "LeftArm")) * CFrame.new(0, -0.5, 0)
	at.RightArm = body * CFrame.new(1.5, 1.5, 0) * CFrame.Angles(armR, 0, 0) * sagged("RightArm", 1 - moduleAlpha(rig, "RightArm")) * CFrame.new(0, -0.5, 0)

	local cframes = rig.cframes
	local i = 0
	local function put(cf: CFrame)
		i += 1
		cframes[i] = cf
	end
	for _, name in MODULE_ORDER do
		put(at[name])
		put(at[name] * rig.frameAt[name])
	end

	-- The tail hangs limp on an unformed shell and rises as the torso locks.
	local sway = math.sin(t * 1.7) * 0.25 * (1 - torsoK)
	local c = feet * CFrame.new(0, 2.4 + bob, 0.5) * CFrame.Angles(lerp(-0.35, 0.35, torsoK), sway, 0)
	local tail1 = c * CFrame.new(0, 0, 0.7)
	c = c * CFrame.new(0, 0, 1.4) * CFrame.Angles(lerp(-0.3, 0.3, torsoK), sway, 0)
	local tail2 = c * CFrame.new(0, 0, 0.65)
	c = c * CFrame.new(0, 0, 1.3) * CFrame.Angles(lerp(-0.3, 0.3, torsoK), sway, 0)
	local tail3 = c * CFrame.new(0, 0, 0.6)
	put(tail1)
	put(tail1)
	put(tail2)
	put(tail2)
	put(tail3)
	put(tail3)

	for _, p in rig.panels do
		put(at[p.def.module] * panelAt(p, panelAlpha(rig, p)))
	end

	local head = at.Head
	put(head * CFrame.new(-0.32, 0.1, -0.61))
	put(head * CFrame.new(0.32, 0.1, -0.61))

	-- Module parts slide out of the body as it finishes forming.
	local parts = rig.moduleParts
	if parts.ClawL then
		local k = 1 - deployAlpha(rig)
		put(at.LeftArm * CFrame.new(0, -1.1 + 0.55 * k, -0.6 + 0.45 * k) * CFrame.Angles(-0.4, 0, 0))
		put(at.RightArm * CFrame.new(0, -1.1 + 0.55 * k, -0.6 + 0.45 * k) * CFrame.Angles(-0.4, 0, 0))
		put(body * CFrame.new(0, 1.4 - 0.5 * k, 0.75 - 0.3 * k))
		put(body * CFrame.new(1.25, 2.25 - 0.35 * k, -0.1))
		put(body * CFrame.new(0, 0.8, 0.85 - 0.3 * k))
	end

	if model:IsDescendantOf(workspace) then
		workspace:BulkMoveTo(rig.parts, cframes, Enum.BulkMoveMode.FireCFrameChanged)
	else
		for index, part in rig.parts do
			part.CFrame = cframes[index]
		end
	end
	-- Repaint every frame while the look is changing, and once more as it finishes, so it ends exactly on
	-- the look rather than on the last frame before.
	local changing = animating(rig)
	if changing or rig.changing then
		apply(rig)
	end
	rig.changing = changing
end

-- Merc clients make the bodies they perceive solid, so they bump into the shell and their aim lands on
-- it (the server still decides every hit). Only the hull collides.
function ShellRig.setSolid(model: Model, solid: boolean)
	local rig = rigs[model]
	if not rig then
		return
	end
	for _, part in rig.parts do
		local name = part.Name
		if name == "Torso" or name == "Head" or name == "LeftLeg" or name == "RightLeg" then
			part.CanCollide = solid
		end
		if not MODULE_NAMES[name] then
			part.CanQuery = solid
		end
	end
end

-- For tests: where this body is in its assembly.
function ShellRig.describe(model: Model): { [string]: any }?
	local rig = rigs[model]
	if not rig then
		return nil
	end
	if rig.dormant then
		return { stage = if rig.twitch > 0 then "booting" else "dormant", closure = math.floor(rig.closure * 100) / 100, look = rig.look }
	end
	local stage = if rig.age < FORM_SECONDS then "forming" elseif rig.age < FORM_SECONDS + SETTLE_SECONDS then "settling" else "formed"
	return { stage = stage, age = if rig.age == math.huge then nil else math.floor(rig.age * 100) / 100, look = rig.look }
end

return ShellRig
