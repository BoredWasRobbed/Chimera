-- Builds the dark-metal map kit for Axiom Data Vault into ServerStorage.MapKit: wall panels to line halls,
-- floors, ceilings, doorway frames, light fixtures, desks and computers, server-room gear, industrial
-- props and signs. A kit, not a map: nothing is placed in the world.
--
-- A one-time generator, not game code: Rojo syncs it to ServerStorage.DevTools and nothing requires it
-- at runtime. Running it REPLACES ServerStorage.MapKit. Run it in Edit mode from the command bar (the
-- clone skips the module cache):
--   require(game.ServerStorage.DevTools.BuildMapKit:Clone())()
-- To browse every piece in the world, build the gallery (Workspace.MapKitGallery, far from the map;
-- delete it before saving the place):
--   require(game.ServerStorage.DevTools.BuildMapKit:Clone()).gallery()
--
-- Every piece is a Model built on a 4-stud grid (most are 8 wide). Its pivot (WorldPivot) is where it
-- mounts, and its LookVector (-Z) is its front, the side people see or use:
--   Mount "Wall"      bottom centre of the back, on the wall's face; the front faces into the room
--   Mount "Floor"     bottom centre, on the floor
--   Mount "Desk"      bottom centre, on a desk top (desks are 2.8 high)
--   Mount "Ceiling"   top centre, on the ceiling; the piece hangs down
--   Mount "Doorway"   bottom centre of the opening, on the wall's centre line (frames fit 2-thick walls)
-- Attribute PlaceIn says where it goes under the map contract (src/shared/FacilityMap.luau):
--   Map/Geometry, Map/Props, or Facility/Lights/<RoomId> for light fixtures. A light's glowing part is
--   named "Fixture": Blackout turns it off and mercs can shoot it out.
-- Only the big parts of a piece collide (backings, desk tops, cabinets); trim, bolts, cables and screens
-- don't, so mercs and shells slide along walls without snagging. Everything still blocks sight and shots.
-- Screens are SurfaceGuis named "Display" that ignore lighting; edit their TextLabels to change the text.
-- Pieces scale cleanly with Model:ScaleTo if a room needs another size.
local ChangeHistoryService = game:GetService("ChangeHistoryService")
local ServerStorage = game:GetService("ServerStorage")

local MAT = Enum.Material

local COL = {
	plate = Color3.fromRGB(42, 45, 51), -- main panel steel
	dark = Color3.fromRGB(25, 27, 31), -- backings, frames, recesses
	black = Color3.fromRGB(12, 13, 15), -- voids and grille holes
	edge = Color3.fromRGB(70, 75, 84), -- trims, bolts, rails that catch the light
	worn = Color3.fromRGB(36, 34, 33), -- corroded pipes and barrels
	hazard = Color3.fromRGB(190, 145, 30),
	hazardDark = Color3.fromRGB(20, 20, 22),
	screen = Color3.fromRGB(6, 11, 15),
	rubber = Color3.fromRGB(18, 18, 20),
	fabric = Color3.fromRGB(33, 35, 41),
	paper = Color3.fromRGB(150, 150, 142),
	cyan = Color3.fromRGB(80, 200, 255),
	red = Color3.fromRGB(255, 55, 45),
	amber = Color3.fromRGB(255, 150, 50),
	green = Color3.fromRGB(90, 255, 140),
	lamp = Color3.fromRGB(205, 220, 240),
	text = Color3.fromRGB(205, 210, 215),
}

local SCREEN = {
	ink = Color3.fromRGB(110, 230, 200),
	dim = Color3.fromRGB(50, 120, 110),
	bg = Color3.fromRGB(7, 16, 20),
}

--------------------------------------------------------------------------------------------------------
-- Part helpers. A builder places parts relative to an origin, so one piece can reuse another.

type Builder = {
	parent: Instance,
	origin: CFrame,
	box: (name: string, size: Vector3, at: Vector3 | CFrame, color: Color3, material: Enum.Material?, solid: boolean?) -> BasePart,
	cyl: (name: string, length: number, diameter: number, at: CFrame, color: Color3, material: Enum.Material?, solid: boolean?) -> BasePart,
	ball: (name: string, diameter: number, at: Vector3, color: Color3, material: Enum.Material?) -> BasePart,
	wedge: (name: string, size: Vector3, at: Vector3 | CFrame, color: Color3, material: Enum.Material?, solid: boolean?) -> BasePart,
	sub: (offset: CFrame) -> Builder,
}

-- Cylinders run along their X axis; these turn X onto Y or Z.
local ALONG_Y = CFrame.Angles(0, 0, math.pi / 2)
local ALONG_Z = CFrame.Angles(0, math.pi / 2, 0)

local function toCFrame(at: Vector3 | CFrame): CFrame
	return if typeof(at) == "Vector3" then CFrame.new(at) else at
end

local function newBuilder(parent: Instance, origin: CFrame): Builder
	local b = {} :: Builder
	b.parent = parent
	b.origin = origin

	local function finish(p: BasePart, name: string, size: Vector3, cf: CFrame, color: Color3, material: Enum.Material?, solid: boolean?): BasePart
		p.Name = name
		p.Size = size
		p.CFrame = origin * cf
		p.Color = color
		p.Material = material or MAT.Metal
		p.Anchored = true
		p.CanCollide = solid == true
		p.CanTouch = false
		p.TopSurface = Enum.SurfaceType.Smooth
		p.BottomSurface = Enum.SurfaceType.Smooth
		-- Small details don't need shadows; it keeps a lined hall cheap to light.
		if size.X * size.Y * size.Z < 0.5 or p.Material == MAT.Neon then
			p.CastShadow = false
		end
		p.Parent = parent
		return p
	end

	function b.box(name, size, at, color, material, solid)
		return finish(Instance.new("Part"), name, size, toCFrame(at), color, material, solid)
	end

	function b.cyl(name, length, diameter, at, color, material, solid)
		local p = Instance.new("Part")
		p.Shape = Enum.PartType.Cylinder
		return finish(p, name, Vector3.new(length, diameter, diameter), at, color, material, solid)
	end

	function b.ball(name, diameter, at, color, material)
		local p = Instance.new("Part")
		p.Shape = Enum.PartType.Ball
		return finish(p, name, Vector3.one * diameter, CFrame.new(at), color, material, false)
	end

	function b.wedge(name, size, at, color, material, solid)
		return finish(Instance.new("WedgePart"), name, size, toCFrame(at), color, material, solid)
	end

	function b.sub(offset)
		return newBuilder(parent, origin * offset)
	end

	return b
end

--------------------------------------------------------------------------------------------------------
-- Surface graphics: hazard stripes and screens.

local function faceSize(size: Vector3, face: Enum.NormalId): (number, number)
	if face == Enum.NormalId.Top or face == Enum.NormalId.Bottom then
		-- A top or bottom SurfaceGui runs its X across the part's Z.
		return size.Z, size.X
	elseif face == Enum.NormalId.Left or face == Enum.NormalId.Right then
		return size.Z, size.Y
	end
	return size.X, size.Y
end

-- Yellow/black stripe pairs across a square tile (2 or 4 per tile). A 45-degree gradient across square
-- tiles lines up from one tile to the next because the pattern repeats every half diagonal.
local function stripes(pairs: number): ColorSequence
	local points = {}
	local n = pairs * 2
	for i = 0, n - 1 do
		local color = if i % 2 == 0 then COL.hazard else COL.hazardDark
		table.insert(points, ColorSequenceKeypoint.new(if i == 0 then 0 else i / n + 0.001, color))
		table.insert(points, ColorSequenceKeypoint.new((i + 1) / n, color))
	end
	return ColorSequence.new(points)
end
local STRIPES_FINE, STRIPES_WIDE = stripes(4), stripes(2)

local function hazard(p: BasePart, face: Enum.NormalId?)
	local f = face or Enum.NormalId.Front
	local w, h = faceSize(p.Size, f)
	local gui = Instance.new("SurfaceGui")
	gui.Name = "Hazard"
	gui.Face = f
	gui.LightInfluence = 1
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 20
	local alongWidth = w >= h
	local n = math.max(1, math.round(if alongWidth then w / h else h / w))
	local side = math.min(w, h)
	for i = 1, n do
		local tile = Instance.new("Frame")
		tile.BorderSizePixel = 0
		tile.BackgroundColor3 = Color3.new(1, 1, 1)
		tile.Size = if alongWidth then UDim2.fromScale(1 / n, 1) else UDim2.fromScale(1, 1 / n)
		tile.Position = if alongWidth then UDim2.fromScale((i - 1) / n, 0) else UDim2.fromScale(0, (i - 1) / n)
		local gradient = Instance.new("UIGradient")
		gradient.Rotation = 45
		gradient.Color = if side >= 1.5 then STRIPES_FINE else STRIPES_WIDE
		gradient.Parent = tile
		tile.Parent = gui
	end
	gui.Parent = p
end

local function label(parent: Instance, text: string, pos: UDim2, size: UDim2, color: Color3, align: Enum.TextXAlignment?, font: Enum.Font?): TextLabel
	local t = Instance.new("TextLabel")
	t.Name = "Text"
	t.BackgroundTransparency = 1
	t.Position = pos
	t.Size = size
	t.Text = text
	t.TextColor3 = color
	t.TextScaled = true
	t.Font = font or Enum.Font.Code
	t.TextXAlignment = align or Enum.TextXAlignment.Left
	t.TextYAlignment = Enum.TextYAlignment.Top
	t.Parent = parent
	return t
end

local function rect(parent: Instance, pos: UDim2, size: UDim2, color: Color3, transparency: number?): Frame
	local f = Instance.new("Frame")
	f.BorderSizePixel = 0
	f.Position = pos
	f.Size = size
	f.BackgroundColor3 = color
	f.BackgroundTransparency = transparency or 0
	f.Parent = parent
	return f
end

local LOG_LINES = {
	"AXIOM DATA VAULT // NODE 07\n> integrity scan ..... OK\n> sector B2 .......... OK\n> cold storage ....... OK\n> uplink ............ ERR\n> retry 3/3 _",
	"AXIOM DV // ARCHIVE 3\n> mount /vault/07 ..... OK\n> checksum ......... 0x3F9A\n> index 88% ...........\n> unknown process: PID 0\n> _",
	"MAINT LOG 11-12\n> coolant pressure  4.1 bar\n> fan bank C ......... OK\n> fan bank D ...... DEGRADED\n> ticket #4471 open\n> _",
}

-- Screen kinds: "log", "camera", "graph", "alert", "map", "off". The SurfaceGui is named "Display".
local function screen(p: BasePart, kind: string, seed: number?)
	p.Material = MAT.SmoothPlastic
	p.Color = COL.screen
	p.Transparency = 0
	p.Reflectance = 0
	if kind == "off" then
		return
	end
	local rng = Random.new(seed or 7)
	local gui = Instance.new("SurfaceGui")
	gui.Name = "Display"
	gui.Face = Enum.NormalId.Front
	gui.LightInfluence = 0
	gui.Brightness = 1.2
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 60
	local bg = rect(gui, UDim2.new(), UDim2.fromScale(1, 1), SCREEN.bg)
	bg.Name = "Background"
	if kind == "log" then
		local padding = Instance.new("UIPadding")
		padding.PaddingLeft = UDim.new(0.04, 0)
		padding.PaddingTop = UDim.new(0.05, 0)
		padding.Parent = bg
		label(bg, LOG_LINES[rng:NextInteger(1, #LOG_LINES)], UDim2.new(), UDim2.fromScale(0.94, 0.9), SCREEN.ink)
	elseif kind == "camera" then
		bg.BackgroundColor3 = Color3.fromRGB(62, 74, 70)
		local grad = Instance.new("UIGradient")
		grad.Color = ColorSequence.new(Color3.fromRGB(255, 255, 255), Color3.fromRGB(110, 110, 110))
		grad.Rotation = 90
		grad.Parent = bg
		-- A dim corridor in perspective: floor and ceiling lines meeting at a far doorway.
		rect(bg, UDim2.fromScale(0.42, 0.34), UDim2.fromScale(0.16, 0.34), Color3.fromRGB(4, 6, 6))
		for _, x in { 0.2, 0.8 } do
			rect(bg, UDim2.fromScale(x - 0.005, 0.1), UDim2.fromScale(0.01, 0.8), Color3.fromRGB(40, 48, 45))
		end
		rect(bg, UDim2.fromScale(0, 0.68), UDim2.fromScale(1, 0.32), Color3.fromRGB(28, 34, 32))
		local cam = rng:NextInteger(1, 24)
		label(bg, string.format("CAM %02d", cam), UDim2.fromScale(0.04, 0.05), UDim2.fromScale(0.3, 0.12), Color3.fromRGB(220, 230, 225))
		label(bg, "● REC", UDim2.fromScale(0.72, 0.05), UDim2.fromScale(0.24, 0.12), COL.red, Enum.TextXAlignment.Right)
		label(bg, string.format("02:%02d:%02d", rng:NextInteger(0, 59), rng:NextInteger(0, 59)), UDim2.fromScale(0.04, 0.84), UDim2.fromScale(0.3, 0.1), Color3.fromRGB(200, 210, 205))
	elseif kind == "graph" then
		label(bg, "THERMAL LOAD", UDim2.fromScale(0.05, 0.05), UDim2.fromScale(0.6, 0.12), SCREEN.ink)
		local bars = 8
		for i = 1, bars do
			local h = rng:NextNumber(0.2, 0.65)
			local color = if h > 0.58 then COL.amber else SCREEN.ink
			rect(bg, UDim2.fromScale(0.06 + (i - 1) * 0.11, 0.9 - h), UDim2.fromScale(0.08, h), color, 0.15)
		end
		rect(bg, UDim2.fromScale(0.05, 0.9), UDim2.fromScale(0.9, 0.01), SCREEN.dim)
	elseif kind == "alert" then
		bg.BackgroundColor3 = Color3.fromRGB(28, 5, 5)
		rect(bg, UDim2.fromScale(0, 0.1), UDim2.fromScale(1, 0.04), COL.red)
		rect(bg, UDim2.fromScale(0, 0.86), UDim2.fromScale(1, 0.04), COL.red)
		local t = label(bg, "UNAUTHORIZED PROCESS\nDETECTED", UDim2.fromScale(0.06, 0.3), UDim2.fromScale(0.88, 0.4), COL.red, Enum.TextXAlignment.Center, Enum.Font.GothamBlack)
		t.TextYAlignment = Enum.TextYAlignment.Center
	elseif kind == "map" then
		label(bg, "FACILITY STATUS", UDim2.fromScale(0.04, 0.04), UDim2.fromScale(0.5, 0.1), SCREEN.ink)
		local rooms = {
			{ 0.38, 0.32, 0.24, 0.36 }, -- the Core
			{ 0.44, 0.72, 0.12, 0.18 },
			{ 0.42, 0.16, 0.16, 0.12 },
			{ 0.66, 0.42, 0.18, 0.16 },
			{ 0.08, 0.38, 0.26, 0.24 },
			{ 0.86, 0.3, 0.1, 0.4 },
		}
		for i, r in rooms do
			local f = rect(bg, UDim2.fromScale(r[1], r[2]), UDim2.fromScale(r[3], r[4]), SCREEN.ink, 0.9)
			local stroke = Instance.new("UIStroke")
			stroke.Color = if i == 4 then COL.red else SCREEN.ink
			stroke.Thickness = 2
			stroke.Parent = f
		end
	end
	gui.Parent = p
end

--------------------------------------------------------------------------------------------------------
-- Pieces. Each builder draws into b with the piece's pivot at b.origin.

local function bolt(b: Builder, x: number, y: number, z: number)
	b.cyl("Bolt", 0.1, 0.22, CFrame.new(x, y, z) * ALONG_Z, COL.edge, MAT.Metal)
end

-- Wall panels: backing on the wall face, ribs at both edges, a diamond-plate kickplate, a mid rail and
-- a cornice, with a lower and an upper plate between the ribs. Variants change the upper plate.
-- `upperOnly` pieces stack on top of a full panel for taller rooms: no kickplate or mid rail.
local function wallPanel(W: number, H: number, variant: string, upperOnly: boolean?)
	return function(b: Builder)
		local inner = W - 1
		local upper = not upperOnly
		b.box("Backing", Vector3.new(W, H, 0.4), Vector3.new(0, H / 2, -0.2), COL.dark, MAT.Metal, true)
		for _, side in { -1, 1 } do
			b.box("Rib", Vector3.new(0.5, H, 0.4), Vector3.new(side * (W / 2 - 0.25), H / 2, -0.6), COL.dark, MAT.Metal)
			b.box("RibFace", Vector3.new(0.12, H, 0.05), Vector3.new(side * (W / 2 - 0.25), H / 2, -0.825), COL.edge, MAT.Metal)
		end
		b.box("Cornice", Vector3.new(W, 0.7, 0.45), Vector3.new(0, H - 0.35, -0.625), COL.dark, MAT.Metal)
		b.box("CorniceLip", Vector3.new(W, 0.12, 0.5), Vector3.new(0, H - 0.76, -0.6), COL.edge, MAT.Metal)

		local plateTop = H - 0.82
		local plateBottom = 0
		if upper then
			b.box("Kickplate", Vector3.new(W, 1.2, 0.35), Vector3.new(0, 0.6, -0.575), COL.plate, MAT.DiamondPlate)
			b.box("KickLip", Vector3.new(W, 0.1, 0.4), Vector3.new(0, 1.25, -0.6), COL.edge, MAT.Metal)
			b.box("MidRail", Vector3.new(W, 0.4, 0.35), Vector3.new(0, 4.4, -0.575), COL.dark, MAT.Metal)
			b.box("MidRailLine", Vector3.new(W, 0.06, 0.05), Vector3.new(0, 4.4, -0.775), COL.edge, MAT.Metal)
			local lower = variant == "Hazard"
			local plate = b.box("LowerPlate", Vector3.new(inner, 2.9, 0.2), Vector3.new(0, 1.3 + 1.45, -0.5), COL.plate, MAT.Metal)
			if lower then
				plate.Material = MAT.SmoothPlastic
				hazard(plate)
			else
				for _, x in { -inner / 2 + 0.35, inner / 2 - 0.35 } do
					for _, y in { 1.65, 3.85 } do
						bolt(b, x, y, -0.62)
					end
				end
			end
			plateBottom = 4.6
		end

		local span = plateTop - plateBottom
		local mid = (plateTop + plateBottom) / 2
		if variant == "Ribbed" then
			local count = math.floor(inner / 0.8)
			local pitch = inner / count
			for i = 1, count do
				local x = -inner / 2 + pitch * (i - 0.5)
				b.box("Slat", Vector3.new(pitch * 0.55, span, 0.25), Vector3.new(x, mid, -0.525), COL.plate, MAT.Metal)
			end
			b.box("Band", Vector3.new(inner, 0.5, 0.3), Vector3.new(0, mid, -0.65), COL.dark, MAT.Metal)
			b.box("BandLine", Vector3.new(inner, 0.08, 0.05), Vector3.new(0, mid, -0.82), COL.edge, MAT.Metal)
		else
			b.box("UpperPlate", Vector3.new(inner, span, 0.2), Vector3.new(0, mid, -0.5), COL.plate, MAT.Metal)
			for _, x in { -inner / 2 + 0.35, inner / 2 - 0.35 } do
				for _, y in { plateBottom + 0.35, plateTop - 0.35 } do
					bolt(b, x, y, -0.62)
				end
			end
			-- Panel seams split the tall plate into smaller sheets.
			local sheets = math.max(1, math.round(span / 4))
			for i = 1, sheets - 1 do
				b.box("Seam", Vector3.new(inner, 0.1, 0.04), Vector3.new(0, plateBottom + span * i / sheets, -0.615), COL.black, MAT.Metal)
			end
		end

		if variant == "Vent" then
			local vw, vh, vy = math.min(4, inner - 1), 2.4, math.min(plateBottom + 3.6, mid)
			b.box("VentHole", Vector3.new(vw, vh, 0.05), Vector3.new(0, vy, -0.62), COL.black, MAT.SmoothPlastic)
			for i = 1, 6 do
				local y = vy - vh / 2 + vh * (i - 0.5) / 6
				b.box("Louver", Vector3.new(vw - 0.1, 0.1, 0.4), CFrame.new(0, y, -0.75) * CFrame.Angles(math.rad(-40), 0, 0), COL.plate, MAT.Metal)
			end
			for _, side in { -1, 1 } do
				b.box("VentFrame", Vector3.new(0.2, vh + 0.4, 0.3), Vector3.new(side * (vw / 2 + 0.1), vy, -0.75), COL.edge, MAT.Metal)
				b.box("VentFrame", Vector3.new(vw + 0.6, 0.2, 0.3), Vector3.new(0, vy + side * (vh / 2 + 0.1), -0.75), COL.edge, MAT.Metal)
			end
		elseif variant == "Pipes" then
			for i, pipe in { { -2.4, 0.7 }, { -1.4, 0.45 } } do
				local x, d = pipe[1] * W / 8, pipe[2]
				b.cyl("Pipe", H, d, CFrame.new(x, H / 2, -0.75 - d / 2) * ALONG_Y, COL.worn, MAT.Metal)
				for _, y in { 2.4, H - 2.4 } do
					b.cyl("Flange", 0.3, d + 0.25, CFrame.new(x, y, -0.75 - d / 2) * ALONG_Y, COL.dark, MAT.Metal)
				end
				if i == 1 then
					b.cyl("Band", 0.6, d + 0.04, CFrame.new(x, math.min(7, H - 4), -0.75 - d / 2) * ALONG_Y, COL.hazard, MAT.Metal)
				end
			end
			for _, y in { 3.4, H - 3.4 } do
				b.box("PipeBracket", Vector3.new(2.2 * W / 8, 0.25, 0.9), Vector3.new(-1.9 * W / 8, y, -0.95), COL.edge, MAT.Metal)
			end
		elseif variant == "Screen" then
			local sy = math.min(7.2, mid)
			b.box("ScreenBezel", Vector3.new(3.8, 2.6, 0.2), Vector3.new(0, sy, -0.7), COL.dark, MAT.Metal)
			local s = b.box("Screen", Vector3.new(3.4, 2.2, 0.05), Vector3.new(0, sy, -0.825), COL.screen, MAT.SmoothPlastic)
			screen(s, "log", W + H)
			b.box("StatusLight", Vector3.new(0.3, 0.12, 0.05), Vector3.new(1.55, sy - 1.45, -0.725), COL.cyan, MAT.Neon)
		end
	end
end

local function wallCap(W: number)
	return function(b: Builder)
		b.box("Cap", Vector3.new(W, 1, 0.9), Vector3.new(0, 0.5, -0.45), COL.dark, MAT.Metal)
		b.box("CapLip", Vector3.new(W, 0.15, 1.05), Vector3.new(0, 0.075, -0.525), COL.edge, MAT.Metal)
	end
end

local function pillar(H: number)
	return function(b: Builder)
		b.box("Column", Vector3.new(1.6, H, 1.6), Vector3.new(0, H / 2, 0), COL.dark, MAT.Metal, true)
		b.box("Plinth", Vector3.new(2.1, 1.2, 2.1), Vector3.new(0, 0.6, 0), COL.plate, MAT.DiamondPlate)
		b.box("Capital", Vector3.new(2.1, 0.8, 2.1), Vector3.new(0, H - 0.4, 0), COL.plate, MAT.Metal)
		for _, x in { -1, 1 } do
			for _, z in { -1, 1 } do
				b.box("Angle", Vector3.new(0.3, H - 2, 0.3), Vector3.new(x * 0.8, H / 2 + 0.2, z * 0.8), COL.edge, MAT.Metal)
			end
		end
		for _, y in { H * 0.35, H * 0.7 } do
			b.box("Band", Vector3.new(1.8, 0.3, 1.8), Vector3.new(0, y, 0), COL.plate, MAT.Metal)
		end
	end
end

-- Floors (0.2 thick overlays that sit on the graybox floor).
local function floorPlate(b: Builder)
	b.box("Plate", Vector3.new(8, 0.2, 8), Vector3.new(0, 0.1, 0), Color3.fromRGB(34, 36, 40), MAT.DiamondPlate, true)
	b.box("Seam", Vector3.new(8, 0.03, 0.15), Vector3.new(0, 0.215, 3.925), COL.black, MAT.Metal)
	b.box("Seam", Vector3.new(0.15, 0.03, 7.85), Vector3.new(3.925, 0.215, -0.075), COL.black, MAT.Metal)
end

local function floorGrate(b: Builder)
	b.box("Pit", Vector3.new(7.2, 0.05, 7.2), Vector3.new(0, 0.025, 0), COL.black, MAT.SmoothPlastic, true)
	for _, side in { -1, 1 } do
		b.box("Frame", Vector3.new(8, 0.2, 0.4), Vector3.new(0, 0.1, side * 3.8), COL.dark, MAT.Metal, true)
		b.box("Frame", Vector3.new(0.4, 0.2, 7.2), Vector3.new(side * 3.8, 0.1, 0), COL.dark, MAT.Metal, true)
	end
	for i = 1, 12 do
		b.box("Slat", Vector3.new(0.25, 0.15, 7.2), Vector3.new(-3.6 + 7.2 * (i - 0.5) / 12, 0.125, 0), COL.plate, MAT.Metal)
	end
	for _, z in { -1.2, 1.2 } do
		b.box("CrossBar", Vector3.new(7.2, 0.1, 0.15), Vector3.new(0, 0.1, z), COL.edge, MAT.Metal)
	end
	-- The pit doesn't stop anything falling in: a flat invisible top keeps mercs and shells level.
	local top = b.box("Walkway", Vector3.new(7.2, 0.05, 7.2), Vector3.new(0, 0.175, 0), COL.black, MAT.SmoothPlastic, true)
	top.Transparency = 1
	top.CastShadow = false
	top.CanQuery = false
end

local function floorHazard(b: Builder)
	local p = b.box("Stripe", Vector3.new(8, 0.22, 1), Vector3.new(0, 0.11, 0), COL.hazard, MAT.SmoothPlastic, true)
	hazard(p, Enum.NormalId.Top)
end

-- Ceilings (the pivot is on the ceiling; pieces hang down).
local function ceilingPanel(b: Builder)
	b.box("Panel", Vector3.new(8, 0.3, 8), Vector3.new(0, -0.15, 0), COL.dark, MAT.Metal, true)
	b.box("Groove", Vector3.new(8, 0.04, 0.12), Vector3.new(0, -0.32, 0), COL.black, MAT.Metal)
	b.box("Groove", Vector3.new(0.12, 0.04, 8), Vector3.new(0, -0.32, 0), COL.black, MAT.Metal)
	b.box("Edge", Vector3.new(8, 0.06, 0.2), Vector3.new(0, -0.33, 3.9), COL.edge, MAT.Metal)
	b.box("Edge", Vector3.new(0.2, 0.06, 7.8), Vector3.new(3.9, -0.33, -0.1), COL.edge, MAT.Metal)
end

local function ceilingBeam(b: Builder)
	b.box("TopFlange", Vector3.new(8, 0.25, 1.2), Vector3.new(0, -0.125, 0), COL.dark, MAT.Metal, true)
	b.box("Web", Vector3.new(8, 1.5, 0.25), Vector3.new(0, -1, 0), COL.dark, MAT.Metal, true)
	b.box("BottomFlange", Vector3.new(8, 0.25, 1.2), Vector3.new(0, -1.875, 0), COL.plate, MAT.Metal, true)
	for _, x in { -3, -1, 1, 3 } do
		for _, z in { -0.4, 0.4 } do
			b.cyl("Rivet", 0.08, 0.18, CFrame.new(x, -2.03, z) * ALONG_Y, COL.edge, MAT.Metal)
		end
	end
end

local function ceilingDuct(b: Builder)
	for _, x in { -3, 3 } do
		for _, z in { -1, 1 } do
			b.box("Hanger", Vector3.new(0.12, 1, 0.12), Vector3.new(x, -0.5, z * 1.3), COL.edge, MAT.Metal)
		end
		b.box("Strap", Vector3.new(0.2, 0.15, 2.8), Vector3.new(x, -2.68, 0), COL.edge, MAT.Metal)
	end
	b.box("Duct", Vector3.new(8, 1.6, 2.4), Vector3.new(0, -1.8, 0), COL.plate, MAT.Metal, true)
	for _, x in { -3.85, 3.85 } do
		b.box("Ring", Vector3.new(0.3, 1.75, 2.55), Vector3.new(x, -1.8, 0), COL.dark, MAT.Metal)
	end
	b.box("Grille", Vector3.new(1.8, 0.05, 1.4), Vector3.new(0, -2.62, 0), COL.black, MAT.SmoothPlastic)
	for i = 1, 4 do
		b.box("GrilleBar", Vector3.new(0.08, 0.06, 1.4), Vector3.new(-0.9 + 1.8 * i / 5, -2.65, 0), COL.edge, MAT.Metal)
	end
end

local function cableTray(b: Builder)
	for _, x in { -3, 3 } do
		for _, z in { -1, 1 } do
			b.box("Rod", Vector3.new(0.1, 1.5, 0.1), Vector3.new(x, -0.75, z * 1.05), COL.edge, MAT.Metal)
		end
	end
	b.box("Tray", Vector3.new(8, 0.1, 2.1), Vector3.new(0, -1.55, 0), COL.dark, MAT.Metal, true)
	for _, z in { -1, 1 } do
		b.box("Side", Vector3.new(8, 0.4, 0.08), Vector3.new(0, -1.35, z * 1.05), COL.plate, MAT.Metal)
	end
	local cables = { { -0.6, 0.35, COL.rubber }, { -0.15, 0.3, COL.rubber }, { 0.3, 0.35, Color3.fromRGB(70, 22, 22) }, { 0.7, 0.25, COL.rubber } }
	for _, c in cables do
		b.cyl("Cable", 8, c[2], CFrame.new(0, -1.5 + c[2] / 2, c[1]), c[3], MAT.SmoothPlastic)
	end
end

-- Light fixtures (Facility/Lights/<RoomId>). The part named Fixture glows and holds the light.
local function fixture(p: BasePart, kind: string, range: number, brightness: number, face: Enum.NormalId?)
	p.Name = "Fixture"
	p.Material = MAT.Neon
	p.Color = COL.lamp
	local light: Light
	if kind == "Spot" then
		local s = Instance.new("SpotLight")
		s.Angle = 110
		s.Face = face or Enum.NormalId.Bottom
		light = s
	elseif kind == "Surface" then
		local s = Instance.new("SurfaceLight")
		s.Angle = 140
		s.Face = face or Enum.NormalId.Bottom
		light = s
	else
		light = Instance.new("PointLight")
	end
	light.Range = range
	light.Brightness = brightness
	light.Color = COL.lamp
	light.Shadows = false
	light.Parent = p
end

local function lightStrip(b: Builder)
	b.box("Housing", Vector3.new(5, 0.35, 1.5), Vector3.new(0, -0.175, 0), COL.dark, MAT.Metal)
	for _, z in { -0.7, 0.7 } do
		b.box("Lip", Vector3.new(5, 0.25, 0.1), Vector3.new(0, -0.45, z), COL.edge, MAT.Metal)
	end
	local glow = b.box("Fixture", Vector3.new(4.4, 0.12, 0.9), Vector3.new(0, -0.41, 0), COL.lamp, MAT.Neon)
	fixture(glow, "Surface", 24, 2)
	for _, x in { -1.5, 0, 1.5 } do
		b.box("Guard", Vector3.new(0.08, 0.08, 1.4), Vector3.new(x, -0.55, 0), COL.edge, MAT.Metal)
	end
end

local function lightCage(b: Builder)
	local y = 10
	b.box("Mount", Vector3.new(1.6, 2.2, 0.2), Vector3.new(0, y, -0.1), COL.dark, MAT.Metal)
	b.box("Base", Vector3.new(1.1, 1.3, 0.35), Vector3.new(0, y, -0.375), COL.plate, MAT.Metal)
	local bulb = b.box("Fixture", Vector3.new(0.7, 1, 0.45), Vector3.new(0, y, -0.75), COL.lamp, MAT.Neon)
	fixture(bulb, "Point", 18, 1.5)
	for _, x in { -0.45, 0, 0.45 } do
		b.box("CageBar", Vector3.new(0.07, 1.4, 0.07), Vector3.new(x, y, -1.05), COL.edge, MAT.Metal)
	end
	for _, dy in { -0.7, 0.7 } do
		b.box("CageRing", Vector3.new(1, 0.07, 0.75), Vector3.new(0, y + dy, -0.7), COL.edge, MAT.Metal)
	end
end

local function lightPendant(b: Builder)
	b.box("Canopy", Vector3.new(0.8, 0.2, 0.8), Vector3.new(0, -0.1, 0), COL.dark, MAT.Metal)
	b.cyl("Rod", 3, 0.12, CFrame.new(0, -1.6, 0) * ALONG_Y, COL.edge, MAT.Metal)
	b.cyl("Shade", 0.9, 2.6, CFrame.new(0, -3.45, 0) * ALONG_Y, COL.dark, MAT.Metal)
	b.cyl("ShadeTop", 0.3, 1.2, CFrame.new(0, -2.9, 0) * ALONG_Y, COL.plate, MAT.Metal)
	local disc = b.box("Fixture", Vector3.new(1.6, 0.1, 1.6), Vector3.new(0, -3.93, 0), COL.lamp, MAT.Neon)
	fixture(disc, "Spot", 30, 2.5)
end

-- Doorway frames around a wall opening W wide and H high in a 2-thick wall lined on both sides.
local function doorFrame(W: number, H: number)
	return function(b: Builder)
		local D = 4 -- wall (2) + panels on both sides (0.85 each), plus a little proud
		for _, side in { -1, 1 } do
			local x = side * (W / 2 + 0.6)
			b.box("Jamb", Vector3.new(1.2, H, D), Vector3.new(x, H / 2, 0), COL.dark, MAT.Metal, true)
			for _, face in { -1, 1 } do
				local stripe = b.box("JambStripe", Vector3.new(0.9, H - 0.4, 0.05), Vector3.new(x, H / 2, face * (D / 2 + 0.025)), COL.hazard, MAT.SmoothPlastic)
				hazard(stripe, if face < 0 then Enum.NormalId.Front else Enum.NormalId.Back)
				b.box("JambEdge", Vector3.new(0.15, H, 0.1), Vector3.new(side * (W / 2 + 0.075), H / 2, face * (D / 2 - 0.05)), COL.edge, MAT.Metal)
			end
			-- Liners inside the opening leave a slot down the middle for the sliding door.
			for _, face in { -1, 1 } do
				b.box("Liner", Vector3.new(0.15, H, 1.4), Vector3.new(side * (W / 2 - 0.075), H / 2, face * 1.15), COL.plate, MAT.Metal)
			end
		end
		b.box("Header", Vector3.new(W + 2.4, 1.6, D), Vector3.new(0, H + 0.8, 0), COL.dark, MAT.Metal, true)
		for _, face in { -1, 1 } do
			b.box("HeaderPlate", Vector3.new(W + 1.6, 0.9, 0.08), Vector3.new(0, H + 0.85, face * (D / 2 + 0.04)), COL.plate, MAT.Metal)
			b.box("HeaderLine", Vector3.new(W + 2.4, 0.1, 0.1), Vector3.new(0, H + 0.05, face * (D / 2 - 0.05)), COL.edge, MAT.Metal)
		end
		b.box("Soffit", Vector3.new(W, 0.15, 1.4), Vector3.new(0, H - 0.075, -1.15), COL.plate, MAT.Metal)
		b.box("Soffit", Vector3.new(W, 0.15, 1.4), Vector3.new(0, H - 0.075, 1.15), COL.plate, MAT.Metal)
		b.box("Threshold", Vector3.new(W, 0.1, D), Vector3.new(0, 0.05, 0), COL.plate, MAT.DiamondPlate, true)
	end
end

-- Office: desks and computers. Desk tops are 2.8 high; desk-mounted pieces pivot on the top.
local DESK_H = 2.8

local function desk(b: Builder)
	b.box("Top", Vector3.new(8, 0.25, 4), Vector3.new(0, DESK_H - 0.125, 0), COL.plate, MAT.Metal, true)
	b.box("FrontLip", Vector3.new(8, 0.2, 0.12), Vector3.new(0, DESK_H - 0.25, -2.0), COL.edge, MAT.Metal)
	b.box("SidePanel", Vector3.new(0.3, DESK_H - 0.25, 3.8), Vector3.new(-3.8, (DESK_H - 0.25) / 2, 0), COL.dark, MAT.Metal, true)
	b.box("ModestyPanel", Vector3.new(7.3, 1.6, 0.15), Vector3.new(0, 1.55, 1.75), COL.dark, MAT.Metal, true)
	-- Drawer pedestal on the right.
	b.box("Pedestal", Vector3.new(2.2, DESK_H - 0.25, 3.6), Vector3.new(2.85, (DESK_H - 0.25) / 2, 0.05), COL.dark, MAT.Metal, true)
	for i = 1, 3 do
		local y = 0.45 + (i - 1) * 0.75
		b.box("Drawer", Vector3.new(2, 0.65, 0.08), Vector3.new(2.85, y, -1.79), COL.plate, MAT.Metal)
		b.box("Handle", Vector3.new(0.8, 0.1, 0.1), Vector3.new(2.85, y + 0.15, -1.87), COL.edge, MAT.Metal)
	end
	b.box("Foot", Vector3.new(0.5, 0.1, 4), Vector3.new(-3.8, 0.05, 0), COL.black, MAT.Metal)
end

local function monitor(kind: string, seed: number)
	return function(b: Builder)
		b.box("Base", Vector3.new(1, 0.08, 0.7), Vector3.new(0, 0.04, 0.1), COL.dark, MAT.Metal)
		b.box("Neck", Vector3.new(0.22, 0.95, 0.15), Vector3.new(0, 0.55, 0.3), COL.dark, MAT.Metal)
		b.box("Housing", Vector3.new(2.3, 1.3, 0.25), Vector3.new(0, 1.5, 0.3), COL.dark, MAT.Metal)
		b.box("Bezel", Vector3.new(2.6, 1.6, 0.12), Vector3.new(0, 1.5, 0.12), COL.black, MAT.Metal)
		local s = b.box("Screen", Vector3.new(2.42, 1.42, 0.04), Vector3.new(0, 1.52, 0.04), COL.screen, MAT.SmoothPlastic)
		screen(s, kind, seed)
		b.box("PowerLight", Vector3.new(0.08, 0.04, 0.03), Vector3.new(1.1, 0.75, 0.05), if kind == "off" then COL.amber else COL.cyan, MAT.Neon)
	end
end

local function keyboard(b: Builder)
	b.box("Keyboard", Vector3.new(1.9, 0.1, 0.65), Vector3.new(0, 0.05, 0), COL.dark, MAT.SmoothPlastic)
	b.box("Keys", Vector3.new(1.75, 0.04, 0.5), Vector3.new(0, 0.12, 0.02), COL.black, MAT.SmoothPlastic)
end

local function mouse(b: Builder)
	b.box("Pad", Vector3.new(0.9, 0.02, 0.8), Vector3.new(0, 0.01, 0), COL.rubber, MAT.Fabric)
	b.box("Mouse", Vector3.new(0.25, 0.1, 0.4), Vector3.new(0, 0.07, 0), COL.dark, MAT.SmoothPlastic)
end

local function tower(b: Builder)
	b.box("Case", Vector3.new(0.9, 2, 2), Vector3.new(0, 1, 0), COL.dark, MAT.Metal, true)
	b.box("Front", Vector3.new(0.8, 1.9, 0.06), Vector3.new(0, 1, -1.02), COL.black, MAT.Metal)
	b.box("LedStrip", Vector3.new(0.06, 1.5, 0.04), Vector3.new(-0.3, 1.05, -1.06), COL.cyan, MAT.Neon)
	b.box("Power", Vector3.new(0.18, 0.18, 0.04), Vector3.new(0.15, 1.75, -1.06), COL.edge, MAT.Metal)
	for i = 1, 3 do
		b.box("Vent", Vector3.new(0.5, 0.05, 0.04), Vector3.new(0.15, 0.4 + i * 0.18, -1.06), COL.dark, MAT.Metal)
	end
end

local function laptop(b: Builder)
	b.box("Base", Vector3.new(1.7, 0.08, 1.15), Vector3.new(0, 0.04, 0), COL.dark, MAT.Metal)
	b.box("Keys", Vector3.new(1.5, 0.02, 0.5), Vector3.new(0, 0.09, -0.1), COL.black, MAT.SmoothPlastic)
	local hinge = CFrame.new(0, 0.08, 0.55) * CFrame.Angles(math.rad(18), 0, 0)
	b.box("Lid", Vector3.new(1.7, 1.1, 0.05), hinge * CFrame.new(0, 0.55, 0), COL.dark, MAT.Metal)
	local s = b.box("Screen", Vector3.new(1.55, 0.95, 0.02), hinge * CFrame.new(0, 0.56, -0.035), COL.screen, MAT.SmoothPlastic)
	screen(s, "alert", 3)
end

local function mug(b: Builder)
	b.cyl("Mug", 0.4, 0.32, CFrame.new(0, 0.2, 0) * ALONG_Y, Color3.fromRGB(32, 34, 38), MAT.SmoothPlastic)
	b.box("Handle", Vector3.new(0.08, 0.22, 0.14), Vector3.new(0.2, 0.22, 0), Color3.fromRGB(32, 34, 38), MAT.SmoothPlastic)
	b.cyl("Coffee", 0.02, 0.26, CFrame.new(0, 0.36, 0) * ALONG_Y, Color3.fromRGB(30, 18, 12), MAT.SmoothPlastic)
end

local function paperStack(b: Builder)
	b.box("Tray", Vector3.new(1.2, 0.25, 1.5), Vector3.new(0, 0.125, 0), COL.dark, MAT.Metal)
	for i = 1, 3 do
		b.box("Paper", Vector3.new(0.9, 0.05, 1.2), CFrame.new(0.03 * i, 0.22 + i * 0.05, 0) * CFrame.Angles(0, math.rad(i * 4 - 6), 0), COL.paper, MAT.SmoothPlastic)
	end
	b.box("Folder", Vector3.new(0.95, 0.06, 1.25), CFrame.new(-0.6, 0.03, 0.4) * CFrame.Angles(0, math.rad(25), 0), Color3.fromRGB(60, 28, 24), MAT.SmoothPlastic)
end

local function chair(b: Builder)
	for i = 0, 4 do
		local a = i * math.pi * 2 / 5
		b.box("Leg", Vector3.new(0.18, 0.12, 1), CFrame.Angles(0, a, 0) * CFrame.new(0, 0.2, -0.5), COL.dark, MAT.Metal)
		b.ball("Wheel", 0.22, (CFrame.Angles(0, a, 0) * CFrame.new(0, 0.11, -0.95)).Position, COL.rubber, MAT.SmoothPlastic)
	end
	b.cyl("Column", 1.1, 0.22, CFrame.new(0, 0.8, 0) * ALONG_Y, COL.edge, MAT.Metal)
	b.box("Seat", Vector3.new(1.8, 0.35, 1.8), Vector3.new(0, 1.5, 0), COL.fabric, MAT.Fabric, true)
	b.box("SeatPan", Vector3.new(1.6, 0.12, 1.6), Vector3.new(0, 1.27, 0), COL.dark, MAT.Metal)
	b.box("Spine", Vector3.new(0.35, 1.2, 0.15), Vector3.new(0, 1.9, 0.92), COL.dark, MAT.Metal)
	b.box("Back", Vector3.new(1.7, 1.8, 0.3), CFrame.new(0, 2.85, 0.95) * CFrame.Angles(math.rad(8), 0, 0), COL.fabric, MAT.Fabric)
	for _, x in { -1, 1 } do
		b.box("ArmPost", Vector3.new(0.12, 0.6, 0.12), Vector3.new(x * 0.95, 1.85, 0.1), COL.dark, MAT.Metal)
		b.box("ArmPad", Vector3.new(0.25, 0.1, 1), Vector3.new(x * 0.95, 2.18, 0.05), COL.rubber, MAT.SmoothPlastic)
	end
end

local function workstation(b: Builder)
	desk(b)
	local top = CFrame.new(0, DESK_H, 0)
	monitor("log", 1)(b.sub(top * CFrame.new(-1.75, 0, 0.9) * CFrame.Angles(0, math.rad(-12), 0)))
	monitor("camera", 2)(b.sub(top * CFrame.new(1.25, 0, 0.9) * CFrame.Angles(0, math.rad(12), 0)))
	keyboard(b.sub(top * CFrame.new(-0.3, 0, -0.6)))
	mouse(b.sub(top * CFrame.new(1.2, 0, -0.6)))
	mug(b.sub(top * CFrame.new(3.2, 0, -0.9)))
	paperStack(b.sub(top * CFrame.new(-3.1, 0, -0.4)))
	tower(b.sub(CFrame.new(-2.5, 0, 0.6)))
	chair(b.sub(CFrame.new(-0.3, 0, -3.2) * CFrame.Angles(0, math.pi + math.rad(10), 0)))
end

local function console(b: Builder)
	b.box("Cabinet", Vector3.new(8, 2.4, 2.4), Vector3.new(0, 1.2, 0.2), COL.dark, MAT.Metal, true)
	b.box("ToeKick", Vector3.new(7.8, 0.4, 0.2), Vector3.new(0, 0.2, -1.0), COL.black, MAT.Metal)
	b.box("FrontPanel", Vector3.new(7.6, 1.6, 0.06), Vector3.new(0, 1.4, -1.03), COL.plate, MAT.Metal)
	for _, x in { -2.6, 0, 2.6 } do
		b.box("PanelSeam", Vector3.new(0.06, 1.6, 0.04), Vector3.new(x, 1.4, -1.07), COL.black, MAT.Metal)
	end
	-- The wedge's slope faces the operator (-Z): low at the front, high at the back.
	b.wedge("Slope", Vector3.new(8, 1, 2.4), Vector3.new(0, 2.9, 0.2), COL.dark, MAT.Metal, true)
	local angle = math.atan2(1, 2.4)
	local deck = b.box("ControlDeck", Vector3.new(7.6, 0.04, 2.5), CFrame.new(0, 2.92, 0.2) * CFrame.Angles(-angle, 0, 0), COL.plate, MAT.Metal)
	local gui = Instance.new("SurfaceGui")
	gui.Name = "Buttons"
	gui.Face = Enum.NormalId.Top
	gui.LightInfluence = 0
	gui.Brightness = 1
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 30
	local rng = Random.new(11)
	local palette = { COL.green, COL.amber, COL.cyan, COL.red, Color3.fromRGB(40, 44, 50), Color3.fromRGB(40, 44, 50) }
	for row = 0, 2 do
		for col = 0, 15 do
			if col ~= 5 and col ~= 10 then
				rect(gui, UDim2.fromScale(0.12 + row * 0.18, 0.03 + col * 0.06), UDim2.fromScale(0.1, 0.035), palette[rng:NextInteger(1, #palette)], 0.1)
			end
		end
	end
	for i = 0, 2 do
		rect(gui, UDim2.fromScale(0.72, 0.06 + i * 0.32), UDim2.fromScale(0.14, 0.22), Color3.fromRGB(30, 34, 40))
	end
	gui.Parent = deck
	b.box("Riser", Vector3.new(8, 2, 0.5), Vector3.new(0, 4.4, 1.15), COL.dark, MAT.Metal)
	b.box("RiserCap", Vector3.new(8.2, 0.15, 0.7), Vector3.new(0, 5.45, 1.1), COL.edge, MAT.Metal)
	for i, kind in { "graph", "map", "camera" } do
		local x = (i - 2) * 2.6
		b.box("Bezel", Vector3.new(2.4, 1.6, 0.06), Vector3.new(x, 4.4, 0.87), COL.black, MAT.Metal)
		local s = b.box("Screen", Vector3.new(2.2, 1.4, 0.04), Vector3.new(x, 4.4, 0.82), COL.screen, MAT.SmoothPlastic)
		screen(s, kind, 20 + i)
	end
end

local function wallMonitor(kind: string)
	return function(b: Builder)
		local y = 8
		b.box("Bracket", Vector3.new(1.2, 1.2, 0.5), Vector3.new(0, y, -0.25), COL.dark, MAT.Metal)
		b.box("Housing", Vector3.new(6.4, 3.8, 0.3), Vector3.new(0, y, -0.65), COL.dark, MAT.Metal)
		b.box("Frame", Vector3.new(6.6, 0.15, 0.4), Vector3.new(0, y + 1.95, -0.7), COL.edge, MAT.Metal)
		b.box("Frame", Vector3.new(6.6, 0.15, 0.4), Vector3.new(0, y - 1.95, -0.7), COL.edge, MAT.Metal)
		local s = b.box("Screen", Vector3.new(6, 3.4, 0.05), Vector3.new(0, y, -0.825), COL.screen, MAT.SmoothPlastic)
		screen(s, kind, 31)
	end
end

local function filingCabinet(b: Builder)
	b.box("Body", Vector3.new(1.8, 4.4, 2.6), Vector3.new(0, 2.2, 0), COL.dark, MAT.Metal, true)
	for i = 1, 4 do
		local y = 0.15 + (i - 0.5) * 1.05
		b.box("Drawer", Vector3.new(1.6, 0.95, 0.08), Vector3.new(0, y, -1.34), COL.plate, MAT.Metal)
		b.box("Handle", Vector3.new(0.6, 0.1, 0.12), Vector3.new(0, y + 0.1, -1.42), COL.edge, MAT.Metal)
		b.box("Tag", Vector3.new(0.45, 0.18, 0.02), Vector3.new(0, y + 0.32, -1.39), COL.paper, MAT.SmoothPlastic)
	end
end

local function locker(b: Builder)
	b.box("Body", Vector3.new(3.2, 7, 1.8), Vector3.new(0, 3.6, 0), COL.dark, MAT.Metal, true)
	for _, x in { -1, 1 } do
		b.box("Foot", Vector3.new(0.2, 0.2, 1.6), Vector3.new(x * 1.4, 0.1, 0), COL.black, MAT.Metal)
		local dx = x * 0.78
		b.box("Door", Vector3.new(1.5, 6.6, 0.08), Vector3.new(dx, 3.6, -0.94), COL.plate, MAT.Metal)
		b.box("Handle", Vector3.new(0.1, 0.8, 0.15), Vector3.new(dx - x * 0.55, 3.6, -1.02), COL.edge, MAT.Metal)
		for i = 1, 4 do
			b.box("Slit", Vector3.new(0.9, 0.08, 0.02), Vector3.new(dx, 6.2 - i * 0.22, -0.99), COL.black, MAT.Metal)
		end
		b.box("NameTag", Vector3.new(0.6, 0.25, 0.02), Vector3.new(dx, 5.1, -0.99), COL.paper, MAT.SmoothPlastic)
	end
end

local function shelf(b: Builder)
	for _, x in { -2.9, 2.9 } do
		for _, z in { -0.9, 0.9 } do
			b.box("Post", Vector3.new(0.2, 7, 0.2), Vector3.new(x, 3.5, z), COL.edge, MAT.Metal)
		end
	end
	local rng = Random.new(5)
	for i, y in { 0.4, 2.4, 4.4, 6.4 } do
		b.box("Shelf", Vector3.new(6, 0.12, 2), Vector3.new(0, y, 0), COL.dark, MAT.Metal, true)
		b.box("ShelfLip", Vector3.new(6, 0.25, 0.06), Vector3.new(0, y + 0.05, -1.0), COL.plate, MAT.Metal)
		if i < 4 then
			local x = -2.6
			while x < 2.2 do
				local w = rng:NextNumber(0.9, 1.6)
				local h = rng:NextNumber(0.7, 1.4)
				if rng:NextNumber() < 0.8 then
					local color = if rng:NextNumber() < 0.3 then Color3.fromRGB(70, 60, 40) else COL.plate
					b.box("Bin", Vector3.new(w, h, 1.5), Vector3.new(x + w / 2, y + 0.06 + h / 2, 0.1), color, MAT.Metal)
					b.box("BinLabel", Vector3.new(0.4, 0.2, 0.02), Vector3.new(x + w / 2, y + 0.06 + h * 0.7, -0.66), COL.paper, MAT.SmoothPlastic)
				end
				x += w + 0.15
			end
		end
	end
	b.box("BackBrace", Vector3.new(5.8, 0.1, 0.1), CFrame.new(0, 3.4, 0.95) * CFrame.Angles(0, 0, math.atan2(6, 5.8)), COL.edge, MAT.Metal)
end

-- Server room.
local function serverRack(seed: number)
	return function(b: Builder)
		b.box("Body", Vector3.new(2.8, 8, 4), Vector3.new(0, 4, 0), COL.black, MAT.Metal, true)
		for _, x in { -1.3, 1.3 } do
			b.box("Rail", Vector3.new(0.2, 8, 0.15), Vector3.new(x, 4, -2.05), COL.dark, MAT.Metal)
		end
		b.box("TopCap", Vector3.new(2.9, 0.3, 4.1), Vector3.new(0, 7.85, 0), COL.dark, MAT.Metal)
		b.box("Plinth", Vector3.new(2.9, 0.3, 4.1), Vector3.new(0, 0.15, 0), COL.dark, MAT.Metal)
		local rng = Random.new(seed)
		-- Server units: lit bezels as parts, the LEDs on a SurfaceGui that ignores lighting.
		local front = b.box("Units", Vector3.new(2.4, 7.2, 0.05), Vector3.new(0, 4.0, -2.0), COL.dark, MAT.Metal)
		local leds = Instance.new("SurfaceGui")
		leds.Name = "Leds"
		leds.Face = Enum.NormalId.Front
		leds.LightInfluence = 0
		leds.Brightness = 1.5
		leds.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
		leds.PixelsPerStud = 40
		local y = 0.4 + 0.15
		while y < 7.6 do
			local units = if rng:NextNumber() < 0.25 then 2 else 1
			local h = 0.45 * units
			if y + h > 7.6 then
				break
			end
			if rng:NextNumber() < 0.88 then
				b.box("Server", Vector3.new(2.3, h - 0.06, 0.12), Vector3.new(0, y + h / 2, -2.06), COL.plate, MAT.Metal)
				b.box("Grip", Vector3.new(0.08, h - 0.16, 0.1), Vector3.new(-1.05, y + h / 2, -2.15), COL.edge, MAT.Metal)
				local sy = 1 - (y + h / 2 - 0.4) / 7.2
				for i = 1, rng:NextInteger(2, 5) do
					local roll = rng:NextNumber()
					local color = if roll < 0.55 then COL.green elseif roll < 0.85 then COL.cyan elseif roll < 0.95 then COL.amber else COL.red
					rect(leds, UDim2.new(0.62 + i * 0.06, 0, sy, -2), UDim2.fromOffset(4, 4), color)
				end
			end
			y += h
		end
		leds.Parent = front
		-- The LEDs sit on a pane just in front of the server faces.
		front.CFrame = front.CFrame * CFrame.new(0, 0, -0.2)
		front.Transparency = 1
		b.box("Back", Vector3.new(2.4, 7.2, 0.05), Vector3.new(0, 4, -2.01), COL.black, MAT.Metal)
		for i = 1, 5 do
			b.box("SideRib", Vector3.new(0.05, 7.4, 0.12), Vector3.new(1.42, 4, -2 + i * 0.66), COL.dark, MAT.Metal)
			b.box("SideRib", Vector3.new(0.05, 7.4, 0.12), Vector3.new(-1.42, 4, -2 + i * 0.66), COL.dark, MAT.Metal)
		end
		b.box("Status", Vector3.new(2.2, 0.08, 0.04), Vector3.new(0, 7.55, -2.12), COL.cyan, MAT.Neon)
	end
end

local function coolingUnit(b: Builder)
	b.box("Body", Vector3.new(6, 8, 3), Vector3.new(0, 4, 0), COL.plate, MAT.Metal, true)
	b.box("Plinth", Vector3.new(6.1, 0.5, 3.1), Vector3.new(0, 0.25, 0), COL.dark, MAT.Metal)
	b.box("Top", Vector3.new(6.1, 0.4, 3.1), Vector3.new(0, 7.8, 0), COL.dark, MAT.Metal)
	for _, x in { -1.45, 1.45 } do
		b.box("GrilleHole", Vector3.new(2.6, 4, 0.05), Vector3.new(x, 3.2, -1.51), COL.black, MAT.SmoothPlastic)
		for i = 1, 10 do
			b.box("Louver", Vector3.new(2.5, 0.08, 0.3), CFrame.new(x, 1.2 + i * 0.38, -1.6) * CFrame.Angles(math.rad(-35), 0, 0), COL.dark, MAT.Metal)
		end
		b.box("GrilleFrame", Vector3.new(2.8, 0.2, 0.2), Vector3.new(x, 5.3, -1.6), COL.edge, MAT.Metal)
		b.box("GrilleFrame", Vector3.new(2.8, 0.2, 0.2), Vector3.new(x, 1.1, -1.6), COL.edge, MAT.Metal)
	end
	b.box("PanelSeam", Vector3.new(0.08, 7, 0.04), Vector3.new(0, 4, -1.52), COL.black, MAT.Metal)
	b.box("Bezel", Vector3.new(1.6, 1, 0.08), Vector3.new(-1.45, 6.4, -1.54), COL.black, MAT.Metal)
	local s = b.box("Screen", Vector3.new(1.4, 0.8, 0.04), Vector3.new(-1.45, 6.4, -1.58), COL.screen, MAT.SmoothPlastic)
	screen(s, "graph", 9)
	b.box("Indicator", Vector3.new(0.25, 0.25, 0.04), Vector3.new(1.0, 6.4, -1.53), COL.green, MAT.Neon)
	b.box("Indicator", Vector3.new(0.25, 0.25, 0.04), Vector3.new(1.4, 6.4, -1.53), COL.amber, MAT.Neon)
	b.cyl("Pipe", 8, 0.5, CFrame.new(2.4, 12, 0.6) * ALONG_Y, COL.worn, MAT.Metal)
	b.cyl("Pipe", 8, 0.5, CFrame.new(1.6, 12, 0.6) * ALONG_Y, COL.worn, MAT.Metal)
end

local function cableBundle(b: Builder)
	for _, c in { { -0.3, 0.5 }, { 0.15, 0.4 }, { 0.5, 0.35 } } do
		b.cyl("Cable", 8, c[2], CFrame.new(0, c[2] / 2, c[1]), COL.rubber, MAT.SmoothPlastic)
	end
	for _, x in { -2.5, 1.5 } do
		b.box("Tie", Vector3.new(0.12, 0.56, 1.35), Vector3.new(x, 0.27, 0.1), COL.edge, MAT.Metal)
	end
end

-- Industrial.
local function pipeRun(b: Builder)
	local pipes = { { y = 11, d = 1.0, z = -1.1 }, { y = 12.3, d = 0.6, z = -0.85 }, { y = 9.9, d = 0.5, z = -0.8 } }
	for i, p in pipes do
		b.cyl("Pipe", 8, p.d, CFrame.new(0, p.y, p.z), if i == 2 then COL.dark else COL.worn, if i == 2 then MAT.Metal else MAT.Metal)
		for _, x in { -3.85, 3.85 } do
			b.cyl("Flange", 0.3, p.d + 0.3, CFrame.new(x, p.y, p.z), COL.dark, MAT.Metal)
		end
	end
	b.cyl("Band", 0.7, 1.04, CFrame.new(-1.5, 11, -1.1), COL.hazard, MAT.Metal)
	for _, x in { -2, 2 } do
		b.box("Strut", Vector3.new(0.3, 3.4, 0.3), Vector3.new(x, 11.1, -0.15), COL.dark, MAT.Metal)
		for _, p in pipes do
			b.box("Arm", Vector3.new(0.25, 0.2, -p.z), Vector3.new(x, p.y - p.d / 2 - 0.1, p.z / 2), COL.edge, MAT.Metal)
		end
	end
	-- Pressure gauge on the big pipe.
	b.cyl("GaugeStem", 0.5, 0.15, CFrame.new(1, 11, -1.7) * ALONG_Z, COL.edge, MAT.Metal)
	b.cyl("Gauge", 0.15, 0.7, CFrame.new(1, 11, -2.0) * ALONG_Z, COL.dark, MAT.Metal)
	b.cyl("GaugeFace", 0.02, 0.56, CFrame.new(1, 11, -2.08) * ALONG_Z, COL.paper, MAT.SmoothPlastic)
	b.box("Needle", Vector3.new(0.04, 0.24, 0.02), CFrame.new(1, 11, -2.1) * CFrame.Angles(0, 0, math.rad(-35)) * CFrame.new(0, 0.1, 0), COL.red, MAT.SmoothPlastic)
end

local function pipeVertical(b: Builder)
	for i, p in { { x = -0.6, d = 0.9 }, { x = 0.6, d = 0.6 } } do
		b.cyl("Pipe", 16, p.d, CFrame.new(p.x, 8, -0.25 - p.d / 2 - 0.3) * ALONG_Y, if i == 1 then COL.worn else COL.dark, if i == 1 then MAT.Metal else MAT.Metal)
		for _, y in { 0.15, 15.85, 6 } do
			b.cyl("Flange", 0.3, p.d + 0.3, CFrame.new(p.x, y, -0.25 - p.d / 2 - 0.3) * ALONG_Y, COL.dark, MAT.Metal)
		end
	end
	for _, y in { 3, 12 } do
		b.box("Bracket", Vector3.new(2.2, 0.3, 1.5), Vector3.new(0, y, -0.75), COL.edge, MAT.Metal)
	end
end

local function junctionBox(b: Builder)
	local y = 4.5
	b.box("Box", Vector3.new(2.4, 3, 0.8), Vector3.new(0, y, -0.4), COL.plate, MAT.Metal, true)
	b.box("Door", Vector3.new(2.1, 2.7, 0.06), Vector3.new(0, y, -0.83), COL.dark, MAT.Metal)
	b.box("Latch", Vector3.new(0.12, 0.4, 0.1), Vector3.new(0.85, y, -0.9), COL.edge, MAT.Metal)
	local warn = b.box("Warning", Vector3.new(0.8, 0.7, 0.02), Vector3.new(0, y + 0.6, -0.87), COL.hazard, MAT.SmoothPlastic)
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Front
	gui.LightInfluence = 1
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 60
	local t = label(gui, "HV", UDim2.new(), UDim2.fromScale(1, 1), COL.hazardDark, Enum.TextXAlignment.Center, Enum.Font.GothamBlack)
	t.TextYAlignment = Enum.TextYAlignment.Center
	gui.Parent = warn
	b.box("Indicator", Vector3.new(0.2, 0.2, 0.04), Vector3.new(-0.75, y - 1.05, -0.88), COL.amber, MAT.Neon)
	b.cyl("Conduit", 16 - y - 1.5, 0.4, CFrame.new(0.5, (16 + y + 1.5) / 2, -0.35) * ALONG_Y, COL.dark, MAT.Metal)
	b.cyl("Conduit", y - 1.5, 0.4, CFrame.new(-0.5, (y - 1.5) / 2, -0.35) * ALONG_Y, COL.dark, MAT.Metal)
end

local function crate(b: Builder)
	b.box("Core", Vector3.new(3.8, 3.8, 3.8), Vector3.new(0, 2, 0), COL.plate, MAT.DiamondPlate, true)
	for _, x in { -1, 1 } do
		for _, z in { -1, 1 } do
			b.box("EdgeV", Vector3.new(0.4, 4, 0.4), Vector3.new(x * 1.8, 2, z * 1.8), COL.dark, MAT.Metal)
			b.box("EdgeX", Vector3.new(4, 0.4, 0.4), Vector3.new(0, 2 + x * 1.8, z * 1.8), COL.dark, MAT.Metal)
			b.box("EdgeZ", Vector3.new(0.4, 0.4, 4), Vector3.new(x * 1.8, 2 + z * 1.8, 0), COL.dark, MAT.Metal)
		end
	end
	local stencil = b.box("Stencil", Vector3.new(2.8, 1.2, 0.02), Vector3.new(0, 2.2, -1.91), COL.plate, MAT.Metal)
	stencil.Transparency = 1
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Front
	gui.LightInfluence = 1
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 40
	label(gui, "AXIOM\nDV-07 / B2", UDim2.new(), UDim2.fromScale(1, 1), Color3.fromRGB(120, 115, 100), Enum.TextXAlignment.Center, Enum.Font.GothamBlack).TextTransparency = 0.45
	gui.Parent = stencil
end

local function crateStack(b: Builder)
	crate(b.sub(CFrame.new(-2.05, 0, 0)))
	crate(b.sub(CFrame.new(2.05, 0, 0.3) * CFrame.Angles(0, math.rad(-6), 0)))
	crate(b.sub(CFrame.new(-0.8, 4, 0.1) * CFrame.Angles(0, math.rad(14), 0)))
end

local function barrel(b: Builder)
	b.cyl("Drum", 3.4, 2.2, CFrame.new(0, 1.7, 0) * ALONG_Y, COL.worn, MAT.Metal, true)
	for _, y in { 0.08, 1.15, 2.25, 3.32 } do
		b.cyl("Rib", 0.15, 2.3, CFrame.new(0, y, 0) * ALONG_Y, COL.dark, MAT.Metal)
	end
	b.cyl("Band", 0.6, 2.22, CFrame.new(0, 2.75, 0) * ALONG_Y, COL.hazard, MAT.Metal)
	b.cyl("Lid", 0.05, 1.9, CFrame.new(0, 3.42, 0) * ALONG_Y, COL.dark, MAT.Metal)
	b.cyl("Cap", 0.1, 0.35, CFrame.new(0.5, 3.47, 0.3) * ALONG_Y, COL.edge, MAT.Metal)
end

local function railing(b: Builder)
	for _, x in { -3.85, 0, 3.85 } do
		b.box("Post", Vector3.new(0.3, 3.5, 0.3), Vector3.new(x, 1.75, 0), COL.dark, MAT.Metal, true)
	end
	local top = b.box("TopRail", Vector3.new(8, 0.25, 0.35), Vector3.new(0, 3.55, 0), COL.hazard, MAT.Metal, true)
	top.Color = Color3.fromRGB(150, 115, 30)
	b.box("MidRail", Vector3.new(8, 0.2, 0.2), Vector3.new(0, 1.9, 0), COL.dark, MAT.Metal, true)
	b.box("KickPlate", Vector3.new(8, 0.5, 0.1), Vector3.new(0, 0.25, 0), COL.plate, MAT.Metal, true)
end

-- Signs (wall-mounted, centred 7 up). Edit the TextLabel to change what they say.
local function sign(text: string, size: Vector3, plateColor: Color3, textColor: Color3, stripe: boolean)
	return function(b: Builder)
		local y = 7
		b.box("Backer", size + Vector3.new(0.3, 0.3, 0), Vector3.new(0, y, -size.Z / 2), COL.dark, MAT.Metal)
		local plate = b.box("Plate", Vector3.new(size.X, size.Y, 0.05), Vector3.new(0, y, -size.Z - 0.025), plateColor, MAT.SmoothPlastic)
		local gui = Instance.new("SurfaceGui")
		gui.Name = "SignText"
		gui.Face = Enum.NormalId.Front
		gui.LightInfluence = 1
		gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
		gui.PixelsPerStud = 50
		local pad = Instance.new("UIPadding")
		pad.PaddingLeft = UDim.new(0.06, 0)
		pad.PaddingRight = UDim.new(0.06, 0)
		pad.PaddingTop = UDim.new(0.12, 0)
		pad.PaddingBottom = UDim.new(if stripe then 0.3 else 0.12, 0)
		pad.Parent = gui
		local t = label(gui, text, UDim2.new(), UDim2.fromScale(1, 1), textColor, Enum.TextXAlignment.Center, Enum.Font.GothamBlack)
		t.TextYAlignment = Enum.TextYAlignment.Center
		gui.Parent = plate
		if stripe then
			local s = b.box("Stripe", Vector3.new(size.X, size.Y * 0.18, 0.04), Vector3.new(0, y - size.Y * 0.41, -size.Z - 0.07), COL.hazard, MAT.SmoothPlastic)
			hazard(s)
		end
		for _, x in { -1, 1 } do
			bolt(b, x * (size.X / 2 + 0.02), y + size.Y / 2 + 0.02, -size.Z - 0.05)
			bolt(b, x * (size.X / 2 + 0.02), y - size.Y / 2 - 0.02, -size.Z - 0.05)
		end
	end
end

--------------------------------------------------------------------------------------------------------
-- The kit list: category, name, mount, where it goes in the place, and the builder.

local GEOM, PROPS, LIGHTS = "Map/Geometry", "Map/Props", "Facility/Lights/<RoomId>"

local KIT = {
	{ "Walls", "WallPanel_8x16_Plate", "Wall", GEOM, wallPanel(8, 16, "Plate") },
	{ "Walls", "WallPanel_8x16_Ribbed", "Wall", GEOM, wallPanel(8, 16, "Ribbed") },
	{ "Walls", "WallPanel_8x16_Vent", "Wall", GEOM, wallPanel(8, 16, "Vent") },
	{ "Walls", "WallPanel_8x16_Pipes", "Wall", GEOM, wallPanel(8, 16, "Pipes") },
	{ "Walls", "WallPanel_8x16_Screen", "Wall", GEOM, wallPanel(8, 16, "Screen") },
	{ "Walls", "WallPanel_8x16_Hazard", "Wall", GEOM, wallPanel(8, 16, "Hazard") },
	{ "Walls", "WallPanel_4x16_Plate", "Wall", GEOM, wallPanel(4, 16, "Plate") },
	{ "Walls", "WallPanel_8x12_Plate", "Wall", GEOM, wallPanel(8, 12, "Plate") },
	{ "Walls", "WallPanel_8x12_Ribbed", "Wall", GEOM, wallPanel(8, 12, "Ribbed") },
	{ "Walls", "WallPanel_8x12_Vent", "Wall", GEOM, wallPanel(8, 12, "Vent") },
	{ "Walls", "WallPanel_4x12_Plate", "Wall", GEOM, wallPanel(4, 12, "Plate") },
	{ "Walls", "WallUpper_8x8", "Wall", GEOM, wallPanel(8, 8, "Plate", true) },
	{ "Walls", "WallUpper_8x8_Ribbed", "Wall", GEOM, wallPanel(8, 8, "Ribbed", true) },
	{ "Walls", "WallCap_8", "Wall", GEOM, wallCap(8) },
	{ "Walls", "Pillar_16", "Floor", GEOM, pillar(16) },
	{ "Walls", "Pillar_12", "Floor", GEOM, pillar(12) },

	{ "Floors", "FloorPlate_8x8", "Floor", GEOM, floorPlate },
	{ "Floors", "FloorGrate_8x8", "Floor", GEOM, floorGrate },
	{ "Floors", "FloorHazard_8x1", "Floor", GEOM, floorHazard },

	{ "Ceilings", "CeilingPanel_8x8", "Ceiling", GEOM, ceilingPanel },
	{ "Ceilings", "CeilingBeam_8", "Ceiling", GEOM, ceilingBeam },
	{ "Ceilings", "CeilingDuct_8", "Ceiling", GEOM, ceilingDuct },
	{ "Ceilings", "CableTray_8", "Ceiling", GEOM, cableTray },

	{ "Doorways", "DoorFrame_8x10", "Doorway", GEOM, doorFrame(8, 10) },
	{ "Doorways", "DoorFrame_12x10", "Doorway", GEOM, doorFrame(12, 10) },
	{ "Doorways", "DoorFrame_24x12", "Doorway", GEOM, doorFrame(24, 12) },
	{ "Doorways", "DoorFrame_24x14", "Doorway", GEOM, doorFrame(24, 14) },

	{ "Lights", "Light_CeilingStrip", "Ceiling", LIGHTS, lightStrip },
	{ "Lights", "Light_WallCage", "Wall", LIGHTS, lightCage },
	{ "Lights", "Light_Pendant", "Ceiling", LIGHTS, lightPendant },

	{ "Office", "Desk_8x4", "Floor", PROPS, desk },
	{ "Office", "Workstation_8x4", "Floor", PROPS, workstation },
	{ "Office", "Monitor_Log", "Desk", PROPS, monitor("log", 4) },
	{ "Office", "Monitor_Camera", "Desk", PROPS, monitor("camera", 5) },
	{ "Office", "Monitor_Graph", "Desk", PROPS, monitor("graph", 6) },
	{ "Office", "Monitor_Alert", "Desk", PROPS, monitor("alert", 7) },
	{ "Office", "Monitor_Off", "Desk", PROPS, monitor("off", 8) },
	{ "Office", "Keyboard", "Desk", PROPS, keyboard },
	{ "Office", "Mouse", "Desk", PROPS, mouse },
	{ "Office", "Laptop", "Desk", PROPS, laptop },
	{ "Office", "Mug", "Desk", PROPS, mug },
	{ "Office", "PaperTray", "Desk", PROPS, paperStack },
	{ "Office", "PCTower", "Floor", PROPS, tower },
	{ "Office", "OfficeChair", "Floor", PROPS, chair },
	{ "Office", "ControlConsole_8", "Floor", PROPS, console },
	{ "Office", "WallMonitor_Map", "Wall", PROPS, wallMonitor("map") },
	{ "Office", "WallMonitor_Camera", "Wall", PROPS, wallMonitor("camera") },
	{ "Office", "FilingCabinet", "Floor", PROPS, filingCabinet },
	{ "Office", "Locker_Double", "Floor", PROPS, locker },
	{ "Office", "StorageShelf_6", "Floor", PROPS, shelf },

	{ "ServerRoom", "ServerRack_A", "Floor", PROPS, serverRack(1) },
	{ "ServerRoom", "ServerRack_B", "Floor", PROPS, serverRack(2) },
	{ "ServerRoom", "CoolingUnit", "Floor", PROPS, coolingUnit },
	{ "ServerRoom", "CableBundle_8", "Floor", PROPS, cableBundle },

	{ "Industrial", "PipeRun_8", "Wall", PROPS, pipeRun },
	{ "Industrial", "PipeVertical_16", "Wall", PROPS, pipeVertical },
	{ "Industrial", "JunctionBox", "Wall", PROPS, junctionBox },
	{ "Industrial", "Crate_4", "Floor", PROPS, crate },
	{ "Industrial", "CrateStack", "Floor", PROPS, crateStack },
	{ "Industrial", "Barrel", "Floor", PROPS, barrel },
	{ "Industrial", "Railing_8", "Floor", PROPS, railing },

	{ "Signs", "Sign_Sector", "Wall", PROPS, sign("SECTOR 07", Vector3.new(4, 1.6, 0.15), COL.dark, COL.text, true) },
	{ "Signs", "Sign_Direction", "Wall", PROPS, sign("<  THE CORE", Vector3.new(5, 1, 0.15), COL.dark, COL.text, false) },
	{ "Signs", "Sign_Warning", "Wall", PROPS, sign("DANGER\nHIGH VOLTAGE", Vector3.new(3, 2, 0.12), COL.hazard, COL.hazardDark, false) },
	{ "Signs", "Sign_Restricted", "Wall", PROPS, sign("RESTRICTED\nAUTHORIZED STAFF ONLY", Vector3.new(4, 1.6, 0.12), Color3.fromRGB(110, 22, 20), COL.text, false) },
}

local CATEGORY_ORDER = { "Walls", "Floors", "Ceilings", "Doorways", "Lights", "Office", "ServerRoom", "Industrial", "Signs" }

local function buildPiece(entry): Model
	local model = Instance.new("Model")
	model.Name = entry[2]
	model:SetAttribute("KitCategory", entry[1])
	model:SetAttribute("Mount", entry[3])
	model:SetAttribute("PlaceIn", entry[4])
	entry[5](newBuilder(model, CFrame.identity))
	model.WorldPivot = CFrame.identity
	return model
end

local function build(): string
	local recording = ChangeHistoryService:TryBeginRecording("Build map kit")
	local old = ServerStorage:FindFirstChild("MapKit")
	if old then
		old:Destroy()
	end
	local root = Instance.new("Folder")
	root.Name = "MapKit"
	root:SetAttribute("Note", "Dark-metal kit pieces. Built by ServerStorage.DevTools.BuildMapKit; see its header for mounts and pivots.")
	local folders = {}
	for _, name in CATEGORY_ORDER do
		local f = Instance.new("Folder")
		f.Name = name
		f.Parent = root
		folders[name] = f
	end
	root.Parent = ServerStorage
	local pieces, parts = 0, 0
	for _, entry in KIT do
		local model = buildPiece(entry)
		for _, d in model:GetDescendants() do
			if d:IsA("BasePart") then
				parts += 1
			end
		end
		model.Parent = folders[entry[1]]
		pieces += 1
		if pieces % 8 == 0 then
			task.wait()
		end
	end
	if recording then
		ChangeHistoryService:FinishRecording(recording, Enum.FinishRecordingOperation.Commit)
	end
	return `map kit built: {pieces} pieces, {parts} parts in ServerStorage.MapKit`
end

-- Lays a copy of every piece out in rows (one per category) on a lit floor at `origin`, far from the map.
-- Wall pieces get a backdrop wall, ceiling pieces a slab to hang from. Delete Workspace.MapKitGallery
-- before saving the place.
local function gallery(origin: Vector3?): string
	local kit = ServerStorage:FindFirstChild("MapKit")
	if not kit then
		build()
		kit = ServerStorage:FindFirstChild("MapKit")
	end
	local base = origin or Vector3.new(0, 0, 700)
	local old = workspace:FindFirstChild("MapKitGallery")
	if old then
		old:Destroy()
	end
	local root = Instance.new("Folder")
	root.Name = "MapKitGallery"
	root.Parent = workspace
	local g = newBuilder(root, CFrame.new(base))
	local rowZ = 0
	for _, category in CATEGORY_ORDER do
		local folder = (kit :: Instance):FindFirstChild(category)
		if folder then
			local x = 0
			local deepest = 0
			for _, model in folder:GetChildren() do
				local copy = (model :: Model):Clone()
				local cf, size = copy:GetBoundingBox()
				local offset = copy:GetPivot():ToObjectSpace(cf)
				local width = size.X
				local mount = copy:GetAttribute("Mount")
				local y = if mount == "Ceiling" then 18 elseif mount == "Desk" then 2.8 else 0
				-- Wall pieces sit on the backdrop; doorways straddle it; the rest stand just in front of it.
				local z = if mount == "Wall" or mount == "Doorway" then rowZ else rowZ - 1 - (offset.Z + size.Z / 2)
				if mount == "Desk" then
					g.box("Plinth", Vector3.new(width + 1, 2.8, size.Z + 1), Vector3.new(x + width / 2 + 0.5, 1.4, z + offset.Z), COL.dark, MAT.Metal)
				end
				copy:PivotTo(CFrame.new(base + Vector3.new(x + width / 2 - offset.X + 0.5, y, z)))
				copy.Parent = root
				x += width + 4
				deepest = math.max(deepest, size.Z)
			end
			g.box("Floor", Vector3.new(x + 8, 1, deepest + 14), Vector3.new(x / 2, -0.5, rowZ - 4), Color3.fromRGB(30, 31, 34), MAT.Concrete)
			g.box("Backdrop", Vector3.new(x + 8, 18, 1), Vector3.new(x / 2, 9, rowZ + 0.5), Color3.fromRGB(36, 37, 40), MAT.Concrete)
			g.box("CeilingSlab", Vector3.new(x + 8, 1, deepest + 14), Vector3.new(x / 2, 18.5, rowZ - 4), Color3.fromRGB(30, 31, 34), MAT.Concrete)
			for lx = 0, x, 12 do
				local lamp = g.box("GalleryLight", Vector3.new(1, 0.2, 1), Vector3.new(lx, 14, rowZ - 9), COL.lamp, MAT.SmoothPlastic)
				lamp.Transparency = 1
				local light = Instance.new("PointLight")
				light.Range = 26
				light.Brightness = 1
				light.Parent = lamp
			end
			rowZ -= deepest + 18
			task.wait()
		end
	end
	return `gallery built at {base}`
end

return setmetatable({ build = build, gallery = gallery, KIT = KIT }, {
	__call = function()
		return build()
	end,
})
