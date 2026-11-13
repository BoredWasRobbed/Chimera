-- Builds the dark-metal map kit for Axiom Data Vault into ServerStorage.MapKit: wall panels to line halls,
-- floors, ceilings, doorway frames, light fixtures, desks and computers, server-room gear, industrial props,
-- signs, and contract-ready versions of the gameplay pieces (Mainframe Terminal, security camera, door,
-- emergency beacon). A kit, not a map: nothing is placed in the world.
--
-- A one-time generator, not game code: Rojo syncs it to ServerStorage.DevTools and nothing requires it at
-- runtime. It needs ReplicatedStorage.Shared.ScreenFeeds (synced by Rojo) to draw screen previews. Run it in
-- Edit mode from the command bar (the clone skips the module cache):
--   require(game.ServerStorage.DevTools.BuildMapKit:Clone())()            rebuilds ServerStorage.MapKit
--   require(game.ServerStorage.DevTools.BuildMapKit:Clone()).gallery()    lays every piece out in
--       Workspace.MapKitGallery, far from the map (delete it before saving the place)
--   require(game.ServerStorage.DevTools.BuildMapKit:Clone()).audit()      checks every piece, and a sample
--       hallway built from them, for Z-fighting (coplanar faces that overlap)
--
-- Every piece is a Model on a 4-stud grid (most are 8 wide). Its pivot (WorldPivot) is where it mounts and
-- its LookVector (-Z) is its front, the side people see or use:
--   Mount "Wall"      bottom centre of the back, on the wall's face (at floor level); the front faces the room.
--                     On a lined wall, mount props on a panel's sheets: 0.52 in front of the wall's face.
--   Mount "Floor"     bottom centre, on the floor
--   Mount "Desk"      bottom centre, on a desk top (desks are 2.8 high)
--   Mount "Ceiling"   top centre, on the ceiling; the piece hangs down
--   Mount "Doorway"   bottom centre of the opening, on the wall's centre line (frames fit 2-thick walls)
-- Attribute PlaceIn says where it goes under the map contract (src/shared/FacilityMap.luau). Light fixtures go
-- in Facility/Lights/<RoomId> (their glowing part is named Fixture: Blackout turns it off and mercs can shoot
-- it out). The Gameplay pieces carry the contract's attributes with placeholder ids: set them when placing.
--
-- Live pieces (src/client/FacilityScreens drives them from the match's real state, by CollectionService tag):
--   KitScreen     screens; attribute Feed picks what they show (see src/shared/ScreenFeeds), CameraId for
--                 Camera feeds. Change Feed on a placed screen to change its feed.
--   KitLeds       rack LEDs and console buttons; KitStatus status lights (attribute StatusMode);
--   KitDoorLight  the light strips on doorframes; KitSign signs (attribute SignMode: Room, Through, Lockdown)
-- Only the big parts of a piece collide (backings, desk tops, cabinets), so nothing snags a merc or a shell.
-- Everything still blocks sight and shots. Fonts: Zekton for signs and headings, Roboto Mono for data.
-- Pieces scale cleanly with Model:ScaleTo.
--
-- Textures: PS1-style pixel art (256 px tiles shown at 1024) from tools/mapkit/textures (make_textures.py),
-- uploaded as image assets. A build makes each one a MaterialVariant in MaterialService (AxiomSteel,
-- AxiomTread, AxiomWorn, AxiomRubber, AxiomCardboard, AxiomLeather, AxiomHazard), and kit parts use the one
-- for their material. The textures are grey, so part colours still set the tone; a part shows its plain
-- colour if its texture can't load.
local ChangeHistoryService = game:GetService("ChangeHistoryService")
local CollectionService = game:GetService("CollectionService")
local MaterialService = game:GetService("MaterialService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

-- Copies of ScreenFeeds and the Fonts it requires, so edits since the last run show up (no module cache).
local function loadFeeds(): any
	local shared = ReplicatedStorage:FindFirstChild("Shared")
	local feeds = shared and shared:FindFirstChild("ScreenFeeds")
	local fonts = shared and shared:FindFirstChild("Fonts")
	assert(feeds and fonts, "ReplicatedStorage.Shared.ScreenFeeds or Fonts is missing: connect Rojo first")
	local folder = Instance.new("Folder")
	fonts:Clone().Parent = folder
	local copy = feeds:Clone()
	copy.Parent = folder
	return require(copy) :: any
end
local Feeds = loadFeeds()
local FONT = Feeds.FONTS

local MAT = Enum.Material

local COL = {
	plate = Color3.fromRGB(42, 45, 51), -- main panel steel
	sheet = Color3.fromRGB(47, 50, 57), -- raised sheets on the panels
	dark = Color3.fromRGB(25, 27, 31), -- backings, frames, recesses
	black = Color3.fromRGB(12, 13, 15), -- voids and grille holes
	edge = Color3.fromRGB(72, 77, 86), -- trims, bolts, rails that catch the light
	worn = Color3.fromRGB(62, 58, 54), -- old pipes and drums, under the rust texture
	hazard = Color3.fromRGB(190, 145, 30),
	hazardDark = Color3.fromRGB(20, 20, 22),
	screen = Color3.fromRGB(6, 11, 15),
	rubber = Color3.fromRGB(18, 18, 20),
	leather = Color3.fromRGB(26, 27, 31),
	paper = Color3.fromRGB(150, 150, 142),
	cardboard = Color3.fromRGB(112, 90, 62),
	glass = Color3.fromRGB(34, 46, 54),
	pcb = Color3.fromRGB(14, 28, 22),
	cyan = Color3.fromRGB(80, 200, 255),
	red = Color3.fromRGB(255, 55, 45),
	amber = Color3.fromRGB(255, 150, 50),
	green = Color3.fromRGB(90, 255, 140),
	lamp = Color3.fromRGB(205, 220, 240),
	text = Color3.fromRGB(205, 210, 215),
	stencil = Color3.fromRGB(150, 156, 162),
	off = Color3.fromRGB(35, 35, 38),
}

-- Wall panel depths (studs in front of the wall's face). Every layer differs, so no two faces fight.
local Z_BACK, Z_PLATE, Z_SHEET, Z_RAIL, Z_KICK, Z_RIB, Z_CORNICE = 0.3, 0.46, 0.52, 0.62, 0.66, 0.84, 0.94
local RIB_W, CORNICE_H, KICK_H, RAIL_Y0, RAIL_Y1 = 0.6, 0.75, 1.2, 4.1, 4.6
local DESK_H = 2.8

------------------------------------------------------------------------------------------------------------
-- Textures (see the header). Every tile is 256 pixels across; StudsPerTile sets how many studs it covers,
-- so steel shows about 26 pixels per stud. Organic tiling shuffles the tiles of the textures without a
-- direction so their repeats don't line up; tread, cardboard and hazard stripes are regular patterns, so
-- they tile normally.
local ORGANIC, REGULAR = Enum.MaterialPattern.Organic, Enum.MaterialPattern.Regular

local TEXTURES = {
	{ name = "AxiomSteel", base = MAT.Metal, id = "rbxassetid://107470682287813", studs = 10, pattern = ORGANIC },
	{ name = "AxiomTread", base = MAT.DiamondPlate, id = "rbxassetid://126235072113949", studs = 8, pattern = REGULAR },
	{ name = "AxiomWorn", base = MAT.CorrodedMetal, id = "rbxassetid://87147878662557", studs = 8, pattern = ORGANIC },
	{ name = "AxiomRubber", base = MAT.Rubber, id = "rbxassetid://136086080050231", studs = 8, pattern = ORGANIC },
	{ name = "AxiomCardboard", base = MAT.Cardboard, id = "rbxassetid://73338777651301", studs = 6, pattern = REGULAR },
	{ name = "AxiomLeather", base = MAT.Leather, id = "rbxassetid://71087948830884", studs = 4, pattern = ORGANIC },
	-- SmoothPlastic is used everywhere, so this one only goes on parts hazard() paints.
	{ name = "AxiomHazard", base = MAT.SmoothPlastic, id = "rbxassetid://118755043930389", studs = 6, pattern = REGULAR, only = true },
}

-- Base material -> the MaterialVariant kit parts of that material use.
local VARIANTS: { [Enum.Material]: string } = {}
local HAZARD_VARIANT: string? = nil
-- Old pipes and drums take the rust texture; without it they stay plain metal.
local WORN = MAT.Metal

local function ensureMaterials()
	table.clear(VARIANTS)
	HAZARD_VARIANT = nil
	WORN = MAT.Metal
	for _, t in TEXTURES do
		if t.id ~= "" then
			local variant = MaterialService:FindFirstChild(t.name)
			if not (variant and variant:IsA("MaterialVariant")) then
				variant = Instance.new("MaterialVariant")
				variant.Name = t.name
			end
			local v = variant :: MaterialVariant
			v.BaseMaterial = t.base
			v.ColorMap = t.id
			v.StudsPerTile = t.studs
			v.MaterialPattern = t.pattern
			v.Parent = MaterialService
			if t.only then
				HAZARD_VARIANT = t.name
			else
				VARIANTS[t.base] = t.name
			end
			if t.base == MAT.CorrodedMetal then
				WORN = MAT.CorrodedMetal
			end
		end
	end
end

------------------------------------------------------------------------------------------------------------
-- Part helpers. A builder places parts relative to an origin, so one piece can reuse another.

type Builder = {
	parent: Instance,
	origin: CFrame,
	box: (string, Vector3, Vector3 | CFrame, Color3, Enum.Material?, boolean?) -> BasePart,
	cyl: (string, number, number, CFrame, Color3, Enum.Material?, boolean?) -> BasePart,
	ball: (string, number, Vector3, Color3, Enum.Material?) -> BasePart,
	wedge: (string, Vector3, Vector3 | CFrame, Color3, Enum.Material?, boolean?) -> BasePart,
	prism: (string, Vector3, Vector3, Vector3, number, Color3, Enum.Material?, boolean?) -> BasePart,
	bevel: (string, Vector3, CFrame, number, string, Color3, Enum.Material?, boolean?) -> BasePart,
	sub: (CFrame) -> Builder,
}

-- Cylinders run along their X axis; these turn X onto Y or Z.
local ALONG_Y = CFrame.Angles(0, 0, math.pi / 2)
local ALONG_Z = CFrame.Angles(0, math.pi / 2, 0)
local TURN = CFrame.Angles(0, math.pi, 0)

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
		p.MaterialVariant = VARIANTS[p.Material] or ""
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

	-- A triangular prism: the triangle's right angle is at `ra`, its legs run to `p1` and `p2`, and the
	-- prism runs `length` across the triangle's plane (half each way). Points are in the builder's space.
	function b.prism(name, ra, p1, p2, length, color, material, solid)
		local up, back = p1 - ra, ra - p2
		local yAxis, zAxis = up.Unit, back.Unit
		local cf = CFrame.fromMatrix((p1 + p2) / 2, yAxis:Cross(zAxis), yAxis, zAxis)
		return finish(Instance.new("WedgePart"), name, Vector3.new(length, up.Magnitude, back.Magnitude), cf, color, material, solid)
	end

	-- A box (at `at`, in the builder's space) whose two front (-Z) edges running along its local `axis`
	-- ("X" or "Y") are cut at 45 degrees by `c`. Returns the main part.
	function b.bevel(name, size, at, c, axis, color, material, solid)
		local X, Y, Z = size.X, size.Y, size.Z
		local main = b.box(name, Vector3.new(X, Y, Z - c), at * CFrame.new(0, 0, c / 2), color, material, solid)
		local extra = name .. "Bevel"
		if axis == "Y" then
			b.box(extra, Vector3.new(X - 2 * c, Y, c), at * CFrame.new(0, 0, -Z / 2 + c / 2), color, material, solid)
			for _, s in { -1, 1 } do
				b.prism(extra, at * Vector3.new(s * (X / 2 - c), 0, -Z / 2 + c), at * Vector3.new(s * (X / 2 - c), 0, -Z / 2), at * Vector3.new(s * X / 2, 0, -Z / 2 + c), Y, color, material)
			end
		else
			b.box(extra, Vector3.new(X, Y - 2 * c, c), at * CFrame.new(0, 0, -Z / 2 + c / 2), color, material, solid)
			for _, s in { -1, 1 } do
				b.prism(extra, at * Vector3.new(0, s * (Y / 2 - c), -Z / 2 + c), at * Vector3.new(0, s * (Y / 2 - c), -Z / 2), at * Vector3.new(0, s * Y / 2, -Z / 2 + c), X, color, material)
			end
		end
		return main
	end

	function b.sub(offset)
		return newBuilder(parent, origin * offset)
	end

	return b
end

-- A bolt head on a surface facing -Z at depth `surface` (negative: in front of the pivot).
local function bolt(b: Builder, x: number, y: number, surface: number, size: number?)
	b.cyl("Bolt", 0.05, size or 0.17, CFrame.new(x, y, surface - 0.025) * ALONG_Z, COL.edge, MAT.Metal)
end

local function tag(part: BasePart, name: string, attrs: { [string]: any }?): BasePart
	CollectionService:AddTag(part, name)
	for key, value in attrs or {} do
		part:SetAttribute(key, value)
	end
	return part
end

-- A status light the client recolours from the room's state (see FacilityScreens).
local function statusLight(b: Builder, size: Vector3, at: Vector3 | CFrame, mode: string?): BasePart
	return tag(b.box("StatusLight", size, at, COL.cyan, MAT.Neon), "KitStatus", { StatusMode = mode or "Room" })
end

------------------------------------------------------------------------------------------------------------
-- Surface graphics: hazard stripes, text, LEDs and screens.

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
local function stripes(count: number): ColorSequence
	local points = {}
	local n = count * 2
	for i = 0, n - 1 do
		local color = if i % 2 == 0 then COL.hazard else COL.hazardDark
		table.insert(points, ColorSequenceKeypoint.new(if i == 0 then 0 else i / n + 0.001, color))
		table.insert(points, ColorSequenceKeypoint.new((i + 1) / n, color))
	end
	return ColorSequence.new(points)
end
local STRIPES_FINE, STRIPES_WIDE = stripes(4), stripes(2)

local function hazard(p: BasePart, face: Enum.NormalId?)
	if HAZARD_VARIANT then
		-- The striped texture covers every face, tinted hazard yellow.
		p.Material = MAT.SmoothPlastic
		p.MaterialVariant = HAZARD_VARIANT
		p.Color = COL.hazard
		return
	end
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

-- One line (or a few) of text filling a part's face.
local function textGui(part: BasePart, value: string, color: Color3, opts: { [string]: any }?): TextLabel
	local o = opts or {}
	local gui = Instance.new("SurfaceGui")
	gui.Name = o.name or "SignText"
	gui.Face = o.face or Enum.NormalId.Front
	gui.LightInfluence = o.light or 1
	gui.Brightness = o.brightness or 1
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = o.pps or 60
	local label = Instance.new("TextLabel")
	label.Name = "Text"
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.FontFace = o.font or FONT.display
	label.Text = value
	label.TextColor3 = color
	label.TextTransparency = o.transparency or 0
	label.TextScaled = true
	label.TextWrapped = true
	label.TextXAlignment = o.align or Enum.TextXAlignment.Center
	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(o.padX or 0.06, 0)
	pad.PaddingRight = UDim.new(o.padX or 0.06, 0)
	pad.PaddingTop = UDim.new(o.padY or 0.12, 0)
	pad.PaddingBottom = UDim.new(o.padY or 0.12, 0)
	pad.Parent = label
	label.Parent = gui
	gui.Parent = part
	return label
end

-- LEDs drawn on a (usually transparent) pane; the client blinks them with network load. Each dot is
-- { x, y (scale), colour (1 green, 2 cyan, 3 amber, 4 red), width multiplier }.
local function leds(part: BasePart, dots: { { number } }, face: Enum.NormalId?, px: number?)
	local gui = Instance.new("SurfaceGui")
	gui.Name = "Leds"
	gui.Face = face or Enum.NormalId.Front
	gui.LightInfluence = 0
	gui.Brightness = 1.6
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 40
	local size = px or 4
	for _, dot in dots do
		local f = Instance.new("Frame")
		f.BorderSizePixel = 0
		f.Position = UDim2.new(dot[1], -size / 2, dot[2], -size / 2)
		f.Size = UDim2.fromOffset(size * (dot[4] or 1), size)
		f.BackgroundColor3 = ({ COL.green, COL.cyan, COL.amber, COL.red })[dot[3]] or COL.green
		f.Parent = gui
	end
	gui.Parent = part
	tag(part, "KitLeds")
end

-- Preview data for screens, read from the open place when it has a facility.
local SAMPLE: any = nil
local SAMPLE_CTX: { [string]: any } = {}

local function placeFacts(): { [string]: any }
	local facts = {}
	local map, facility = workspace:FindFirstChild("Map"), workspace:FindFirstChild("Facility")
	local roomsFolder = facility and facility:FindFirstChild("Rooms")
	if roomsFolder then
		local rooms = {}
		for _, bounds in roomsFolder:GetChildren() do
			if bounds:IsA("BasePart") then
				local cf, size = bounds.CFrame, bounds.Size
				local x0, z0, x1, z1 = math.huge, math.huge, -math.huge, -math.huge
				for _, sx in { -1, 1 } do
					for _, sz in { -1, 1 } do
						local p = cf:PointToWorldSpace(Vector3.new(sx * size.X / 2, 0, sz * size.Z / 2))
						x0, z0, x1, z1 = math.min(x0, p.X), math.min(z0, p.Z), math.max(x1, p.X), math.max(z1, p.Z)
					end
				end
				rooms[bounds.Name] = { id = bounds.Name, name = bounds:GetAttribute("DisplayName") or bounds.Name, wing = bounds:GetAttribute("Wing") or "", dark = false, emergency = false, rect = { x0, z0, x1, z1 } }
			end
		end
		if next(rooms) then
			facts.rooms = rooms
			if rooms.SF_RACKHALL then
				rooms.SF_RACKHALL.dark = true
			end
		end
	end
	local terms = map and map:FindFirstChild("Terminals")
	if terms then
		local list = {}
		for _, model in terms:GetChildren() do
			local id = model:GetAttribute("TerminalId")
			if type(id) == "string" then
				local room = model:GetAttribute("Room") or ""
				local info = facts.rooms and facts.rooms[room]
				local pivot = model:GetPivot().Position
				local name = string.gsub(model:GetAttribute("DisplayName") or id, " terminal$", "")
				table.insert(list, { id = id, name = name, room = room, wing = if info then info.wing else "", progress = 0, done = false, locked = false, pos = Vector2.new(pivot.X, pivot.Z) })
			end
		end
		table.sort(list, function(a, b)
			return a.id < b.id
		end)
		if #list > 0 then
			facts.terminals = list
		end
	end
	local cams = facility and facility:FindFirstChild("Cameras")
	if cams then
		local list = {}
		for _, model in cams:GetChildren() do
			local id = model:GetAttribute("CameraId")
			if type(id) == "string" then
				table.insert(list, { id = id, name = model:GetAttribute("DisplayName") or id, room = model:GetAttribute("Room") or "", broken = id == "MT_BOILER" })
			end
		end
		table.sort(list, function(a, b)
			return a.id < b.id
		end)
		if #list > 0 then
			facts.cameras = list
		end
	end
	local docks = map and map:FindFirstChild("Docks")
	if docks then
		local counts = {}
		for _, model in docks:GetChildren() do
			local room = model:GetAttribute("Room")
			if type(room) == "string" then
				counts[room] = (counts[room] or 0) + 1
			end
		end
		facts.docks = counts
	end
	return facts
end

local function prepareSample()
	SAMPLE = Feeds.sample(placeFacts())
	local roomId = if SAMPLE.rooms.SF_RACKHALL then "SF_RACKHALL" else SAMPLE.roomOrder[1]
	local room = SAMPLE.rooms[roomId]
	local busy = nil
	for _, t in SAMPLE.terminals do
		if t.operator then
			busy = t.id
		end
	end
	local pos = nil
	if room and room.rect then
		pos = Vector2.new((room.rect[1] + room.rect[3]) / 2, (room.rect[2] + room.rect[4]) / 2)
	end
	SAMPLE_CTX = { room = roomId, wing = room and room.wing, roomName = room and room.name, terminalId = busy, pos = pos }
end

-- A live screen: tagged KitScreen with its Feed; drawn here with sample data so the kit previews look right.
local function kitScreen(b: Builder, size: Vector3, at: Vector3 | CFrame, feed: string): BasePart
	local p = b.box("Screen", size, at, COL.screen, MAT.SmoothPlastic)
	p.CastShadow = false
	local gui = Instance.new("SurfaceGui")
	gui.Name = "Display"
	gui.Face = Enum.NormalId.Front
	gui.LightInfluence = 0
	gui.Brightness = 1.3
	gui.Parent = p
	tag(p, "KitScreen", { Feed = feed })
	if feed == "Camera" then
		p:SetAttribute("CameraId", "")
	end
	local ctx = table.clone(SAMPLE_CTX)
	ctx.width = Feeds.HEIGHT * size.X / size.Y
	ctx.seed = Feeds.hash(b.parent.Name .. tostring(toCFrame(at).Position))
	Feeds.mount(gui, feed, ctx).update(SAMPLE)
	return p
end

------------------------------------------------------------------------------------------------------------
-- Walls

-- Raised sheets in a panel's recess between y0 and y1, with bolts at their top corners.
local function sheets(b: Builder, half: number, y0: number, y1: number): { BasePart }
	local n = math.max(1, math.round((y1 - y0) / 3.6))
	local gap = 0.14
	local h = (y1 - y0 - 0.24 - gap * (n - 1)) / n
	local list = {}
	for i = 1, n do
		local ya = y0 + 0.12 + (i - 1) * (h + gap)
		list[i] = b.box("Sheet", Vector3.new(2 * half - 0.24, h, Z_SHEET - Z_PLATE), Vector3.new(0, ya + h / 2, -(Z_PLATE + Z_SHEET) / 2), COL.sheet, MAT.Metal)
		for _, s in { -1, 1 } do
			bolt(b, s * (half - 0.36), ya + h - 0.26, -Z_SHEET)
		end
	end
	return list
end

-- An 8- or 4-wide wall panel: a backing on the wall, chamfered ribs at both edges, a cornice, and (unless
-- it's an upper panel that stacks on another) a diamond-plate kickplate and a mid rail with a status light.
-- Variants: Plate, Ribbed, Vent, Pipes, Screen (a live screen), Hazard, Access.
local function wallPanel(W: number, H: number, variant: string, upperOnly: boolean?, feed: string?)
	return function(b: Builder)
		local half = W / 2 - RIB_W
		local top = H - CORNICE_H
		local base = if upperOnly then 0 else RAIL_Y1
		b.box("Backing", Vector3.new(W, H, Z_BACK), Vector3.new(0, H / 2, -Z_BACK / 2), COL.dark, MAT.Metal, true)
		for _, side in { -1, 1 } do
			local x = side * (W / 2 - RIB_W / 2)
			b.bevel("Rib", Vector3.new(RIB_W, top, Z_RIB - Z_BACK), CFrame.new(x, top / 2, -(Z_BACK + Z_RIB) / 2), 0.14, "Y", COL.dark, MAT.Metal)
			local y0 = if upperOnly then 0.3 else KICK_H + 0.25
			b.box("RibStrip", Vector3.new(0.12, top - 0.25 - y0, 0.03), Vector3.new(x, (y0 + top - 0.25) / 2, -(Z_RIB + 0.015)), COL.edge, MAT.Metal)
		end
		b.bevel("Cornice", Vector3.new(W - 0.14, CORNICE_H, Z_CORNICE - Z_BACK), CFrame.new(0, H - CORNICE_H / 2, -(Z_BACK + Z_CORNICE) / 2), 0.15, "X", COL.dark, MAT.Metal)
		b.box("CorniceLine", Vector3.new(W - 0.2, 0.06, 0.03), Vector3.new(0, H - CORNICE_H / 2, -(Z_CORNICE + 0.015)), COL.edge, MAT.Metal)

		if not upperOnly then
			b.bevel("Kickplate", Vector3.new(2 * half, KICK_H, Z_KICK - Z_BACK), CFrame.new(0, KICK_H / 2, -(Z_BACK + Z_KICK) / 2), 0.08, "X", COL.plate, MAT.DiamondPlate)
			b.bevel("MidRail", Vector3.new(2 * half, RAIL_Y1 - RAIL_Y0, Z_RAIL - Z_BACK), CFrame.new(0, (RAIL_Y0 + RAIL_Y1) / 2, -(Z_BACK + Z_RAIL) / 2), 0.08, "X", COL.dark, MAT.Metal)
			b.box("RailLine", Vector3.new(2 * half - 0.2, 0.06, 0.03), Vector3.new(0, RAIL_Y0 + 0.2, -(Z_RAIL + 0.015)), COL.edge, MAT.Metal)
			statusLight(b, Vector3.new(0.36, 0.1, 0.04), Vector3.new(half - 0.5, RAIL_Y0 + 0.36, -(Z_RAIL + 0.02)))
			b.box("LowerRecess", Vector3.new(2 * half, RAIL_Y0 - KICK_H, Z_PLATE - Z_BACK), Vector3.new(0, (KICK_H + RAIL_Y0) / 2, -(Z_BACK + Z_PLATE) / 2), COL.dark, MAT.Metal)
			local lower = b.box("Sheet", Vector3.new(2 * half - 0.24, RAIL_Y0 - KICK_H - 0.24, Z_SHEET - Z_PLATE), Vector3.new(0, (KICK_H + RAIL_Y0) / 2, -(Z_PLATE + Z_SHEET) / 2), COL.sheet, MAT.Metal)
			if variant == "Hazard" then
				lower.Color = COL.hazard
				lower.Material = MAT.SmoothPlastic
				hazard(lower)
			else
				for _, s in { -1, 1 } do
					for _, y in { KICK_H + 0.38, RAIL_Y0 - 0.38 } do
						bolt(b, s * (half - 0.36), y, -Z_SHEET)
					end
				end
			end
			if variant == "Vent" then
				for i = 1, 4 do
					b.box("Slot", Vector3.new(2 * half - 1.6, 0.1, 0.03), Vector3.new(0, KICK_H + 0.9 + (i - 1) * 0.26, -(Z_SHEET + 0.015)), COL.black, MAT.Metal)
				end
			elseif variant == "Plate" or variant == "Pipes" then
				b.box("ServiceTag", Vector3.new(0.6, 0.3, 0.02), Vector3.new(-half + 0.9, RAIL_Y0 - 0.75, -(Z_SHEET + 0.01)), COL.paper, MAT.SmoothPlastic)
			end
		end

		b.box("Recess", Vector3.new(2 * half, top - base, Z_PLATE - Z_BACK), Vector3.new(0, (base + top) / 2, -(Z_BACK + Z_PLATE) / 2), if variant == "Ribbed" then COL.black else COL.dark, MAT.Metal)
		local mid = (base + top) / 2
		if variant == "Ribbed" then
			local count = math.max(2, math.floor(2 * half / 0.7))
			local pitch = 2 * half / count
			for i = 1, count do
				b.box("Slat", Vector3.new(pitch * 0.55, top - base - 0.2, 0.14), Vector3.new(-half + pitch * (i - 0.5), mid, -(Z_PLATE + 0.07)), COL.sheet, MAT.Metal)
			end
			b.bevel("Band", Vector3.new(2 * half, 0.5, 0.24), CFrame.new(0, mid, -(Z_PLATE + 0.02 + 0.12)), 0.06, "X", COL.dark, MAT.Metal)
			b.box("BandLine", Vector3.new(2 * half - 0.2, 0.06, 0.03), Vector3.new(0, mid, -(Z_PLATE + 0.26 + 0.015)), COL.edge, MAT.Metal)
		else
			local list = sheets(b, half, base, top)
			if variant == "Hazard" and list[#list] then
				textGui(list[#list], "CAUTION\nHIGH VOLTAGE", COL.stencil, { transparency = 0.35, padX = 0.18, padY = 0.32 })
			end
		end

		if variant == "Vent" then
			local vw, vh = math.min(4, 2 * half - 1.2), 2.4
			local vy = math.min(base + 3.8, mid)
			b.box("VentHole", Vector3.new(vw, vh, 0.04), Vector3.new(0, vy, -(Z_SHEET + 0.02)), COL.black, MAT.Metal)
			for i = 1, 7 do
				b.box("Louver", Vector3.new(vw - 0.05, 0.08, 0.22), CFrame.new(0, vy - vh / 2 + vh * (i - 0.5) / 7, -(Z_SHEET + 0.11)) * CFrame.Angles(math.rad(-40), 0, 0), COL.sheet, MAT.Metal)
			end
			for _, s in { -1, 1 } do
				b.box("VentFrame", Vector3.new(vw + 0.4, 0.2, 0.22), Vector3.new(0, vy + s * (vh / 2 + 0.1), -(Z_SHEET + 0.11)), COL.edge, MAT.Metal)
				b.box("VentFrame", Vector3.new(0.2, vh, 0.22), Vector3.new(s * (vw / 2 + 0.1), vy, -(Z_SHEET + 0.11)), COL.edge, MAT.Metal)
			end
		elseif variant == "Pipes" then
			for i, pipe in { { -1.6, 0.7 }, { -0.6, 0.45 } } do
				local x, d = pipe[1] * W / 8, pipe[2]
				local z = -(0.75 + d / 2)
				b.cyl("Pipe", H - 0.05, d, CFrame.new(x, (H - 0.05) / 2, z) * ALONG_Y, COL.worn, WORN)
				for _, y in { 0.9, H - 1.6 } do
					b.cyl("Flange", 0.18, d + 0.22, CFrame.new(x, y, z) * ALONG_Y, COL.dark, MAT.Metal)
				end
				for _, y in { 3.0, top - 2.2 } do
					b.cyl("Clamp", 0.22, d + 0.12, CFrame.new(x, y, z) * ALONG_Y, COL.edge, MAT.Metal)
					b.box("Standoff", Vector3.new(0.26, 0.16, 0.75 - Z_SHEET), Vector3.new(x, y, -(Z_SHEET + 0.75) / 2), COL.edge, MAT.Metal)
				end
				if i == 1 then
					b.cyl("Band", 0.6, d + 0.04, CFrame.new(x, math.min(7, H - 4), z) * ALONG_Y, COL.hazard, MAT.Metal)
				end
			end
		elseif variant == "Screen" then
			local sy = math.min(7.4, mid)
			b.bevel("ScreenHousing", Vector3.new(3.9, 2.7, 0.26), CFrame.new(0, sy, -(Z_SHEET + 0.13)), 0.1, "Y", COL.dark, MAT.Metal)
			kitScreen(b, Vector3.new(3.5, 2.3, 0.03), Vector3.new(0, sy + 0.05, -(Z_SHEET + 0.26 + 0.015)), feed or "Status")
			b.box("Hood", Vector3.new(4.1, 0.1, 0.5), Vector3.new(0, sy + 1.4, -(Z_SHEET + 0.25)), COL.dark, MAT.Metal)
			b.box("Grille", Vector3.new(1.6, 0.12, 0.02), Vector3.new(-0.6, sy - 1.22, -(Z_SHEET + 0.26 + 0.01)), COL.black, MAT.Metal)
			statusLight(b, Vector3.new(0.2, 0.08, 0.02), Vector3.new(1.4, sy - 1.22, -(Z_SHEET + 0.26 + 0.01)))
		elseif variant == "Access" then
			local dy = base + 2.0
			for _, s in { -1, 1 } do
				b.box("HatchFrame", Vector3.new(3.0, 0.15, 0.14), Vector3.new(0, dy + s * 1.775, -(Z_SHEET + 0.07)), COL.edge, MAT.Metal)
				b.box("HatchFrame", Vector3.new(0.15, 3.4, 0.14), Vector3.new(s * 1.425, dy, -(Z_SHEET + 0.07)), COL.edge, MAT.Metal)
			end
			local hatch = b.box("Hatch", Vector3.new(2.7, 3.4, 0.08), Vector3.new(0, dy, -(Z_SHEET + 0.04)), COL.plate, MAT.Metal)
			textGui(hatch, "ACCESS 07\nAUTHORIZED ONLY", COL.stencil, { transparency = 0.3, padX = 0.16, padY = 0.36 })
			for _, y in { dy - 1.1, dy + 1.1 } do
				b.cyl("Hinge", 0.5, 0.12, CFrame.new(-1.32, y, -(Z_SHEET + 0.12)) * ALONG_Y, COL.edge, MAT.Metal)
			end
			b.box("HandleSlot", Vector3.new(0.16, 0.8, 0.02), Vector3.new(1.0, dy, -(Z_SHEET + 0.09)), COL.black, MAT.Metal)
			b.box("Handle", Vector3.new(0.08, 0.6, 0.1), Vector3.new(1.0, dy, -(Z_SHEET + 0.15)), COL.edge, MAT.Metal)
			b.box("Keypad", Vector3.new(0.5, 0.7, 0.08), Vector3.new(half - 0.62, dy + 0.4, -(Z_SHEET + 0.04)), COL.dark, MAT.Metal)
			statusLight(b, Vector3.new(0.3, 0.06, 0.02), Vector3.new(half - 0.62, dy + 0.62, -(Z_SHEET + 0.09)))
			b.box("Keys", Vector3.new(0.34, 0.3, 0.02), Vector3.new(half - 0.62, dy + 0.3, -(Z_SHEET + 0.09)), COL.edge, MAT.SmoothPlastic)
		end
	end
end

local function wallCap(W: number)
	return function(b: Builder)
		b.bevel("Cap", Vector3.new(W - 0.14, 1, 1.02), CFrame.new(0, 0.5, -0.51), 0.18, "X", COL.dark, MAT.Metal)
		b.box("CapLine", Vector3.new(W - 0.2, 0.06, 0.03), Vector3.new(0, 0.5, -1.035), COL.edge, MAT.Metal)
	end
end

local function pillar(H: number)
	return function(b: Builder)
		b.box("Plinth", Vector3.new(2.3, 0.9, 2.3), Vector3.new(0, 0.45, 0), COL.plate, MAT.DiamondPlate, true)
		b.box("PlinthStep", Vector3.new(2.0, 0.3, 2.0), Vector3.new(0, 1.05, 0), COL.dark, MAT.Metal)
		b.box("Column", Vector3.new(1.6, H - 2.0, 1.6), Vector3.new(0, 0.9 + (H - 2.0) / 2 + 0.1, 0), COL.dark, MAT.Metal, true)
		local band = b.box("HazardBand", Vector3.new(1.9, 1.4, 1.9), Vector3.new(0, 1.9, 0), COL.hazard, MAT.SmoothPlastic)
		for _, face in { Enum.NormalId.Front, Enum.NormalId.Back, Enum.NormalId.Left, Enum.NormalId.Right } do
			hazard(band, face)
		end
		for _, x in { -1, 1 } do
			for _, z in { -1, 1 } do
				b.box("Angle", Vector3.new(0.34, H - 3.7, 0.34), Vector3.new(x * 0.74, 2.6 + (H - 3.7) / 2, z * 0.74), COL.edge, MAT.Metal)
			end
		end
		for _, y in { H * 0.45, H * 0.75 } do
			b.box("Band", Vector3.new(1.98, 0.3, 1.98), Vector3.new(0, y, 0), COL.plate, MAT.Metal)
		end
		b.box("CapitalStep", Vector3.new(2.0, 0.3, 2.0), Vector3.new(0, H - 0.95, 0), COL.dark, MAT.Metal)
		b.box("Capital", Vector3.new(2.3, 0.8, 2.3), Vector3.new(0, H - 0.4, 0), COL.plate, MAT.Metal, true)
	end
end

------------------------------------------------------------------------------------------------------------
-- Floors (overlays about 0.2 thick that sit on the graybox floor)

local function floorPlate(b: Builder)
	b.box("Underlay", Vector3.new(7.96, 0.16, 7.96), Vector3.new(0, 0.08, 0), COL.black, MAT.Metal, true)
	b.box("Plate", Vector3.new(7.9, 0.18, 7.9), Vector3.new(0, 0.11, 0), Color3.fromRGB(34, 36, 40), MAT.DiamondPlate, true)
	for _, x in { -3.55, 3.55 } do
		for _, z in { -3.55, 3.55 } do
			b.cyl("Bolt", 0.05, 0.2, CFrame.new(x, 0.225, z) * ALONG_Y, COL.edge, MAT.Metal)
		end
	end
end

local function floorGrate(b: Builder)
	b.box("Pit", Vector3.new(7.2, 0.03, 7.2), Vector3.new(0, 0.015, 0), COL.black, MAT.SmoothPlastic, true)
	for _, z in { -1.7, 1.5 } do
		b.cyl("Pipe", 7.2, 0.09, CFrame.new(0, 0.075, z), COL.worn, WORN)
	end
	b.cyl("Cable", 7.2, 0.07, CFrame.new(0, 0.065, 0.35), Color3.fromRGB(70, 22, 22), MAT.Rubber)
	for _, z in { -2.6, -0.8, 0.9, 2.6 } do
		b.box("Support", Vector3.new(7.2, 0.04, 0.14), Vector3.new(0, 0.12, z), COL.dark, MAT.Metal)
	end
	for i = 1, 14 do
		b.box("Slat", Vector3.new(0.2, 0.06, 7.2), Vector3.new(-3.6 + 7.2 * (i - 0.5) / 14, 0.17, 0), COL.plate, MAT.Metal, true)
	end
	for _, s in { -1, 1 } do
		b.box("Frame", Vector3.new(8, 0.2, 0.4), Vector3.new(0, 0.1, s * 3.8), COL.dark, MAT.Metal, true)
		b.box("Frame", Vector3.new(0.4, 0.2, 7.2), Vector3.new(s * 3.8, 0.1, 0), COL.dark, MAT.Metal, true)
	end
	for _, x in { -3.8, 3.8 } do
		for _, z in { -3.8, 3.8 } do
			b.cyl("Bolt", 0.05, 0.18, CFrame.new(x, 0.225, z) * ALONG_Y, COL.edge, MAT.Metal)
		end
	end
end

local function floorHazard(b: Builder)
	local p = b.box("Stripe", Vector3.new(7.84, 0.28, 1), Vector3.new(0, 0.14, 0), COL.hazard, MAT.SmoothPlastic, true)
	hazard(p, Enum.NormalId.Top)
	for _, s in { -1, 1 } do
		b.box("Edge", Vector3.new(7.84, 0.24, 0.08), Vector3.new(0, 0.12, s * 0.54), COL.rubber, MAT.Rubber)
	end
end

local function floorHatch(b: Builder)
	for _, s in { -1, 1 } do
		b.box("Frame", Vector3.new(4.2, 0.24, 0.3), Vector3.new(0, 0.12, s * 1.95), COL.dark, MAT.Metal, true)
		b.box("Frame", Vector3.new(0.3, 0.24, 3.6), Vector3.new(s * 1.95, 0.12, 0), COL.dark, MAT.Metal, true)
	end
	b.box("Hatch", Vector3.new(3.6, 0.2, 3.6), Vector3.new(0, 0.12, 0), Color3.fromRGB(30, 32, 36), MAT.DiamondPlate, true)
	b.box("HandleWell", Vector3.new(1.0, 0.02, 0.34), Vector3.new(0, 0.23, -1.2), COL.black, MAT.Metal)
	b.box("Handle", Vector3.new(0.8, 0.05, 0.08), Vector3.new(0, 0.265, -1.2), COL.edge, MAT.Metal)
	for _, x in { -1, 1 } do
		b.cyl("Hinge", 0.6, 0.14, CFrame.new(x, 0.24, 1.75), COL.edge, MAT.Metal)
	end
	for _, x in { -1.95, 1.95 } do
		for _, z in { -1.95, 1.95 } do
			b.cyl("Bolt", 0.05, 0.16, CFrame.new(x, 0.265, z) * ALONG_Y, COL.edge, MAT.Metal)
		end
	end
end

------------------------------------------------------------------------------------------------------------
-- Ceilings (the pivot is on the ceiling; pieces hang down)

local function ceilingPanel(b: Builder)
	b.box("Underlay", Vector3.new(7.96, 0.2, 7.96), Vector3.new(0, -0.1, 0), COL.black, MAT.Metal, true)
	b.box("Panel", Vector3.new(7.9, 0.26, 7.9), Vector3.new(0, -0.15, 0), COL.dark, MAT.Metal, true)
	for _, z in { -2, 2 } do
		b.box("Rib", Vector3.new(7.9, 0.05, 0.16), Vector3.new(0, -0.305, z), COL.plate, MAT.Metal)
	end
	for _, x in { -3.55, 3.55 } do
		for _, z in { -3.55, 3.55 } do
			b.cyl("Bolt", 0.05, 0.18, CFrame.new(x, -0.305, z) * ALONG_Y, COL.edge, MAT.Metal)
		end
	end
end

local function ceilingBeam(b: Builder)
	b.box("TopFlange", Vector3.new(8, 0.25, 1.2), Vector3.new(0, -0.125, 0), COL.dark, MAT.Metal, true)
	b.box("Web", Vector3.new(8, 1.5, 0.24), Vector3.new(0, -1, 0), COL.dark, MAT.Metal, true)
	b.box("BottomFlange", Vector3.new(8, 0.25, 1.2), Vector3.new(0, -1.875, 0), COL.plate, MAT.Metal, true)
	for _, s in { -1, 1 } do
		b.prism("Fillet", Vector3.new(0, -0.25, s * 0.12), Vector3.new(0, -0.37, s * 0.12), Vector3.new(0, -0.25, s * 0.24), 8, COL.dark, MAT.Metal)
		b.prism("Fillet", Vector3.new(0, -1.75, s * 0.12), Vector3.new(0, -1.63, s * 0.12), Vector3.new(0, -1.75, s * 0.24), 8, COL.dark, MAT.Metal)
	end
	for _, x in { -3, -1, 1, 3 } do
		for _, z in { -0.4, 0.4 } do
			b.cyl("Rivet", 0.05, 0.18, CFrame.new(x, -2.025, z) * ALONG_Y, COL.edge, MAT.Metal)
		end
	end
end

local function ceilingDuct(b: Builder)
	b.box("Duct", Vector3.new(8, 1.6, 2.4), Vector3.new(0, -1.8, 0), Color3.fromRGB(52, 55, 60), MAT.Metal, true)
	for _, x in { -3.85, 3.85 } do
		b.box("Flange", Vector3.new(0.3, 0.15, 2.7), Vector3.new(x, -0.925, 0), COL.dark, MAT.Metal)
		b.box("Flange", Vector3.new(0.3, 0.15, 2.7), Vector3.new(x, -2.675, 0), COL.dark, MAT.Metal)
		for _, s in { -1, 1 } do
			b.box("Flange", Vector3.new(0.3, 1.6, 0.15), Vector3.new(x, -1.8, s * 1.275), COL.dark, MAT.Metal)
		end
	end
	for _, x in { -2.5, 2.5 } do
		for _, s in { -1, 1 } do
			b.cyl("Rod", 2.6, 0.1, CFrame.new(x, -1.3, s * 1.45) * ALONG_Y, COL.edge, MAT.Metal)
		end
		b.box("Trapeze", Vector3.new(0.3, 0.15, 3.2), Vector3.new(x, -2.675, 0), COL.edge, MAT.Metal)
	end
	b.box("Grille", Vector3.new(1.8, 0.03, 1.4), Vector3.new(0, -2.615, 0), COL.black, MAT.Metal)
	for i = 1, 5 do
		b.box("GrilleBar", Vector3.new(0.08, 0.04, 1.4), Vector3.new(-0.9 + 1.8 * i / 6, -2.65, 0), COL.edge, MAT.Metal)
	end
end

local function cableTray(b: Builder)
	for _, s in { -1, 1 } do
		b.box("Rail", Vector3.new(8, 0.4, 0.08), Vector3.new(0, -1.4, s * 1.04), COL.plate, MAT.Metal)
	end
	for i = 0, 7 do
		b.box("Rung", Vector3.new(0.12, 0.06, 2.0), Vector3.new(-3.5 + i, -1.57, 0), COL.dark, MAT.Metal, true)
	end
	for _, x in { -3, 3 } do
		b.box("Support", Vector3.new(0.2, 0.12, 2.5), Vector3.new(x, -1.66, 0), COL.edge, MAT.Metal)
		for _, s in { -1, 1 } do
			b.cyl("Rod", 1.6, 0.1, CFrame.new(x, -0.8, s * 1.18) * ALONG_Y, COL.edge, MAT.Metal)
		end
	end
	local cables = { { -0.62, 0.34, COL.rubber }, { -0.2, 0.3, COL.rubber }, { 0.24, 0.34, Color3.fromRGB(70, 22, 22) }, { 0.66, 0.24, Color3.fromRGB(26, 40, 70) } }
	for _, c in cables do
		b.cyl("Cable", 8, c[2], CFrame.new(0, -1.54 + c[2] / 2, c[1]), c[3], MAT.Rubber)
	end
end

local function ceilingPipes(b: Builder)
	local pipes = { { z = -0.6, d = 0.8, color = COL.worn }, { z = 0.35, d = 0.55, color = COL.dark }, { z = 1.1, d = 0.4, color = Color3.fromRGB(28, 44, 60) } }
	for _, x in { -2.5, 2.5 } do
		for _, s in { -1, 1 } do
			b.cyl("Rod", 1.9, 0.1, CFrame.new(x, -0.95, s * 1.45) * ALONG_Y, COL.edge, MAT.Metal)
		end
		b.box("Trapeze", Vector3.new(0.25, 0.14, 3.1), Vector3.new(x, -1.97, 0), COL.edge, MAT.Metal)
	end
	for _, p in pipes do
		local y = -1.9 + p.d / 2
		b.cyl("Pipe", 8, p.d, CFrame.new(0, y, p.z), p.color, if p.color == COL.worn then WORN else MAT.Metal)
		for _, x in { -3.88, 3.88 } do
			b.cyl("Flange", 0.2, p.d + 0.24, CFrame.new(x, y, p.z), COL.dark, MAT.Metal)
		end
		for _, x in { -2.5, 2.5 } do
			b.cyl("Clamp", 0.18, p.d + 0.12, CFrame.new(x, y, p.z), COL.edge, MAT.Metal)
		end
	end
end

------------------------------------------------------------------------------------------------------------
-- Light fixtures (Facility/Lights/<RoomId>). The part named Fixture glows and holds the light.

local function fixture(p: BasePart, kind: string, range: number, brightness: number)
	p.Name = "Fixture"
	p.Material = MAT.Neon
	p.Color = COL.lamp
	local light: Light
	if kind == "Spot" then
		local s = Instance.new("SpotLight")
		s.Angle = 110
		s.Face = Enum.NormalId.Bottom
		light = s
	elseif kind == "Surface" then
		local s = Instance.new("SurfaceLight")
		s.Angle = 140
		s.Face = Enum.NormalId.Bottom
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
	b.box("Mount", Vector3.new(5.2, 0.12, 1.7), Vector3.new(0, -0.06, 0), COL.dark, MAT.Metal)
	b.bevel("Housing", Vector3.new(5.0, 1.5, 0.4), CFrame.new(0, -0.32, 0) * CFrame.Angles(-math.pi / 2, 0, 0), 0.15, "X", COL.dark, MAT.Metal)
	for _, x in { -2.6, 2.6 } do
		b.box("EndCap", Vector3.new(0.2, 0.5, 1.4), Vector3.new(x, -0.37, 0), COL.plate, MAT.Metal)
	end
	local glow = b.box("Fixture", Vector3.new(4.6, 0.06, 1.0), Vector3.new(0, -0.55, 0), COL.lamp, MAT.Neon)
	fixture(glow, "Surface", 24, 2)
	for _, x in { -1.5, 0, 1.5 } do
		b.box("Guard", Vector3.new(0.06, 0.06, 1.3), Vector3.new(x, -0.64, 0), COL.edge, MAT.Metal)
	end
end

local function lightCage(b: Builder)
	local y = 10
	b.cyl("Base", 0.18, 1.3, CFrame.new(0, y, -0.09) * ALONG_Z, COL.dark, MAT.Metal)
	b.cyl("Collar", 0.25, 1.0, CFrame.new(0, y, -0.305) * ALONG_Z, COL.plate, MAT.Metal)
	local glow = b.ball("Fixture", 0.75, Vector3.new(0, y, -0.72), COL.lamp, MAT.Neon)
	fixture(glow, "Point", 18, 1.5)
	for _, s in { -1, 1 } do
		b.box("CageBar", Vector3.new(0.06, 0.06, 0.62), Vector3.new(0, y + s * 0.5, -0.74), COL.edge, MAT.Metal)
		b.box("CageBar", Vector3.new(0.06, 0.06, 0.62), Vector3.new(s * 0.5, y, -0.74), COL.edge, MAT.Metal)
	end
	b.box("CageFront", Vector3.new(1.06, 0.06, 0.06), Vector3.new(0, y, -1.08), COL.edge, MAT.Metal)
	b.box("CageFront", Vector3.new(0.06, 1.06, 0.06), Vector3.new(0, y, -1.1), COL.edge, MAT.Metal)
end

local function lightPendant(b: Builder)
	b.cyl("Canopy", 0.15, 0.8, CFrame.new(0, -0.075, 0) * ALONG_Y, COL.dark, MAT.Metal)
	b.cyl("Cable", 2.85, 0.06, CFrame.new(0, -1.575, 0) * ALONG_Y, COL.rubber, MAT.Rubber)
	b.cyl("ShadeTop", 0.3, 0.9, CFrame.new(0, -3.15, 0) * ALONG_Y, COL.plate, MAT.Metal)
	b.cyl("Shade", 0.4, 1.8, CFrame.new(0, -3.5, 0) * ALONG_Y, COL.dark, MAT.Metal)
	b.cyl("ShadeRim", 0.35, 2.6, CFrame.new(0, -3.875, 0) * ALONG_Y, COL.dark, MAT.Metal)
	local disc = b.box("Fixture", Vector3.new(1.4, 0.06, 1.4), Vector3.new(0, -4.08, 0), COL.lamp, MAT.Neon)
	fixture(disc, "Spot", 30, 2.5)
end

------------------------------------------------------------------------------------------------------------
-- Doorway frames around a wall opening W wide and H high in a 2-thick wall lined on both sides. The frame
-- is 4 deep. On each face: chamfered jambs with hazard stripes and a door light (KitDoorLight, the nearest
-- door's state), and a header plate naming the room on the other side (KitSign, mode Through).

local function doorFrame(W: number, H: number)
	return function(b: Builder)
		local D, c = 4, 0.18
		for _, side in { -1, 1 } do
			local x = side * (W / 2 + 0.6)
			b.box("Jamb", Vector3.new(1.2, H, D - 0.8), Vector3.new(x, H / 2, 0), COL.dark, MAT.Metal, true)
			for _, face in { -1, 1 } do
				local f = b.sub(CFrame.new(x, 0, face * (D / 2 - 0.2)) * (if face > 0 then TURN else CFrame.identity))
				f.bevel("JambFace", Vector3.new(1.2, H, 0.4), CFrame.new(0, H / 2, 0), c, "Y", COL.dark, MAT.Metal, true)
				local stripe = f.box("JambStripe", Vector3.new(0.5, H - 1.2, 0.04), Vector3.new(0, H / 2 - 0.2, -0.22), COL.hazard, MAT.SmoothPlastic)
				hazard(stripe)
				local inward = side * face
				tag(f.box("DoorLight", Vector3.new(0.12, 1.4, 0.04), Vector3.new(inward * 0.34, H - 2.0, -0.22), COL.green, MAT.Neon), "KitDoorLight")
			end
		end
		b.box("Header", Vector3.new(W + 2.4, 2, D - 0.8), Vector3.new(0, H + 1, 0), COL.dark, MAT.Metal, true)
		for _, face in { -1, 1 } do
			local f = b.sub(CFrame.new(0, 0, face * (D / 2 - 0.2)) * (if face > 0 then TURN else CFrame.identity))
			f.bevel("HeaderFace", Vector3.new(W + 2.4, 2, 0.4), CFrame.new(0, H + 1, 0), c, "X", COL.dark, MAT.Metal, true)
			local width = math.min(W, 10) - 0.4
			local plate = f.box("HeaderPlate", Vector3.new(width, 0.86, 0.05), Vector3.new(0, H + 1.15, -0.225), COL.plate, MAT.Metal)
			textGui(plate, "THE CORE", COL.text, { padY = 0.18 })
			tag(plate, "KitSign", { SignMode = "Through" })
			for _, s in { -1, 1 } do
				bolt(f, s * (width / 2 - 0.15), H + 1.15, -0.25, 0.12)
			end
		end
		for _, side in { -1, 1 } do
			for _, face in { -1, 1 } do
				b.box("Liner", Vector3.new(0.12, H - 0.28, 1.4), Vector3.new(side * (W / 2 - 0.06), 0.28 + (H - 0.28) / 2, face * 1.15), COL.plate, MAT.Metal)
			end
		end
		for _, face in { -1, 1 } do
			b.box("Soffit", Vector3.new(W - 0.24, 0.12, 1.4), Vector3.new(0, H - 0.06, face * 1.15), COL.plate, MAT.Metal)
		end
		b.box("Threshold", Vector3.new(W - 0.16, 0.28, 3.36), Vector3.new(0, 0.14, 0), COL.plate, MAT.DiamondPlate, true)
		for _, face in { -1, 1 } do
			b.prism("Ramp", Vector3.new(0, 0, face * 1.68), Vector3.new(0, 0.28, face * 1.68), Vector3.new(0, 0, face * 1.96), W - 0.16, COL.plate, MAT.DiamondPlate, true)
		end
	end
end

------------------------------------------------------------------------------------------------------------
-- Office: desks and computers. Desk tops are 2.8 high; desk-mounted pieces pivot on the top.

local function desk(b: Builder)
	b.bevel("Top", Vector3.new(8, 0.22, 4), CFrame.new(0, DESK_H - 0.11, 0), 0.06, "X", COL.plate, MAT.Metal, true)
	b.box("Grommet", Vector3.new(0.5, 0.02, 0.5), Vector3.new(-3.2, DESK_H + 0.01, 1.45), COL.black, MAT.Rubber)
	-- A C-leg on the left.
	for _, z in { -1.6, 1.6 } do
		b.box("Post", Vector3.new(0.18, DESK_H - 0.34, 0.18), Vector3.new(-3.7, 0.12 + (DESK_H - 0.34) / 2, z), COL.dark, MAT.Metal, true)
	end
	b.box("Foot", Vector3.new(0.3, 0.12, 3.8), Vector3.new(-3.7, 0.06, 0), COL.dark, MAT.Metal, true)
	b.box("LegRail", Vector3.new(0.18, 0.14, 3.02), Vector3.new(-3.7, DESK_H - 0.29, 0), COL.dark, MAT.Metal)
	-- Drawer pedestal on the right.
	b.box("Plinth", Vector3.new(2.0, 0.08, 3.4), Vector3.new(2.75, 0.04, 0.1), COL.black, MAT.Metal)
	b.box("Pedestal", Vector3.new(2.2, DESK_H - 0.3, 3.6), Vector3.new(2.75, 0.08 + (DESK_H - 0.3) / 2, 0.05), COL.dark, MAT.Metal, true)
	for i = 1, 3 do
		local y = 0.22 + (i - 1) * 0.78 + 0.37
		b.box("Drawer", Vector3.new(2.04, 0.74, 0.06), Vector3.new(2.75, y, -1.78), COL.plate, MAT.Metal)
		b.box("PullSlot", Vector3.new(0.9, 0.1, 0.02), Vector3.new(2.75, y + 0.18, -1.82), COL.black, MAT.Metal)
		b.box("Pull", Vector3.new(0.9, 0.05, 0.08), Vector3.new(2.75, y + 0.26, -1.85), COL.edge, MAT.Metal)
	end
	b.cyl("Lock", 0.03, 0.12, CFrame.new(3.5, 2.1, -1.825) * ALONG_Z, COL.edge, MAT.Metal)
	-- Modesty panel, cable tray and cables.
	b.box("Modesty", Vector3.new(5.24, 1.6, 0.1), Vector3.new(-0.99, 1.7, 1.65), COL.dark, MAT.Metal)
	for _, y in { 1.3, 2.1 } do
		b.box("Groove", Vector3.new(4.8, 0.06, 0.02), Vector3.new(-0.99, y, 1.59), COL.black, MAT.Metal)
	end
	b.box("CableTray", Vector3.new(4.0, 0.06, 0.5), Vector3.new(-1.2, DESK_H - 0.5, 1.2), COL.plate, MAT.Metal)
	for _, x in { -3.3, -3.1 } do
		b.cyl("Cable", DESK_H - 0.2, 0.1, CFrame.new(x, (DESK_H - 0.2) / 2, 1.82) * ALONG_Y, COL.rubber, MAT.Rubber)
	end
end

local function monitor(feed: string)
	return function(b: Builder)
		b.box("Base", Vector3.new(1.1, 0.06, 0.75), Vector3.new(0, 0.03, 0.2), COL.dark, MAT.Metal)
		b.box("BasePad", Vector3.new(0.6, 0.04, 0.4), Vector3.new(0, 0.08, 0.25), COL.plate, MAT.Metal)
		b.box("Neck", Vector3.new(0.22, 0.95, 0.12), Vector3.new(0, 0.575, 0.38), COL.dark, MAT.Metal)
		b.cyl("Hinge", 0.32, 0.2, CFrame.new(0, 1.1, 0.38), COL.edge, MAT.Metal)
		b.box("Housing", Vector3.new(2.4, 1.5, 0.16), Vector3.new(0, 1.62, 0.22), COL.dark, MAT.Metal)
		b.box("Bulge", Vector3.new(1.2, 0.8, 0.1), Vector3.new(0, 1.6, 0.35), COL.dark, MAT.Metal)
		b.box("Bezel", Vector3.new(2.6, 0.11, 0.1), Vector3.new(0, 1.62 + 0.755, 0.11), COL.black, MAT.SmoothPlastic)
		b.box("Chin", Vector3.new(2.6, 0.16, 0.1), Vector3.new(0, 1.62 - 0.78, 0.11), COL.black, MAT.SmoothPlastic)
		for _, s in { -1, 1 } do
			b.box("Bezel", Vector3.new(0.08, 1.4, 0.1), Vector3.new(s * 1.26, 1.62, 0.11), COL.black, MAT.SmoothPlastic)
		end
		kitScreen(b, Vector3.new(2.44, 1.4, 0.06), Vector3.new(0, 1.62, 0.11), feed)
		b.box("PowerLight", Vector3.new(0.06, 0.03, 0.02), Vector3.new(1.1, 1.62 - 0.78, 0.05), if feed == "Off" then COL.amber else COL.cyan, MAT.Neon)
	end
end

-- A keyboard's keycaps drawn on a pane whose front faces up (spacebar row toward the user).
local function keys(part: BasePart, columns: number)
	local gui = Instance.new("SurfaceGui")
	gui.Name = "Keys"
	gui.Face = Enum.NormalId.Front
	gui.LightInfluence = 1
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 100
	for r = 1, 5 do
		local widths = {}
		if r < 5 then
			for _ = 1, columns do
				table.insert(widths, 1)
			end
		else
			for _ = 1, 4 do
				table.insert(widths, 1)
			end
			table.insert(widths, columns - 8)
			for _ = 1, 4 do
				table.insert(widths, 1)
			end
		end
		local x = 0
		for _, w in widths do
			local key = Instance.new("Frame")
			key.BorderSizePixel = 0
			key.BackgroundColor3 = Color3.fromRGB(52, 55, 61)
			key.Position = UDim2.new(x / columns, 1, (r - 1) / 5, 1)
			key.Size = UDim2.new(w / columns, -2, 1 / 5, -2)
			key.Parent = gui
			x += w
		end
	end
	gui.Parent = part
end

local function keyboard(b: Builder)
	b.box("Case", Vector3.new(1.9, 0.08, 0.68), Vector3.new(0, 0.04, 0), COL.dark, MAT.SmoothPlastic)
	local bed = b.box("KeyBed", Vector3.new(1.78, 0.56, 0.02), CFrame.new(0, 0.09, 0) * CFrame.Angles(math.pi / 2, 0, 0), COL.black, MAT.SmoothPlastic)
	keys(bed, 15)
end

local function mouse(b: Builder)
	b.box("Pad", Vector3.new(0.9, 0.02, 0.8), Vector3.new(0.05, 0.01, 0), COL.rubber, MAT.Rubber)
	b.box("Body", Vector3.new(0.24, 0.07, 0.3), Vector3.new(0, 0.055, 0.03), COL.dark, MAT.SmoothPlastic)
	b.wedge("Nose", Vector3.new(0.24, 0.07, 0.14), Vector3.new(0, 0.055, -0.19), COL.dark, MAT.SmoothPlastic)
	b.cyl("Wheel", 0.04, 0.07, CFrame.new(0, 0.095, -0.06), COL.edge, MAT.Rubber)
end

local function laptop(b: Builder)
	b.box("Base", Vector3.new(1.7, 0.06, 1.15), Vector3.new(0, 0.03, 0), COL.dark, MAT.Metal)
	local bed = b.box("KeyBed", Vector3.new(1.5, 0.5, 0.02), CFrame.new(0, 0.07, 0.03) * CFrame.Angles(math.pi / 2, 0, 0), COL.black, MAT.SmoothPlastic)
	keys(bed, 14)
	b.box("Touchpad", Vector3.new(0.5, 0.02, 0.26), Vector3.new(0, 0.07, -0.39), Color3.fromRGB(34, 36, 40), MAT.SmoothPlastic)
	b.cyl("Hinge", 1.5, 0.1, CFrame.new(0, 0.07, 0.56), COL.dark, MAT.Metal)
	local hinge = CFrame.new(0, 0.07, 0.55) * CFrame.Angles(math.rad(18), 0, 0)
	b.box("Lid", Vector3.new(1.7, 1.1, 0.05), hinge * CFrame.new(0, 0.58, 0), COL.dark, MAT.Metal)
	kitScreen(b, Vector3.new(1.55, 0.95, 0.02), hinge * CFrame.new(0, 0.6, -0.035), "Log")
end

local function mug(b: Builder)
	local color = Color3.fromRGB(32, 34, 38)
	b.cyl("Mug", 0.4, 0.32, CFrame.new(0, 0.2, 0) * ALONG_Y, color, MAT.SmoothPlastic)
	b.cyl("Coffee", 0.02, 0.26, CFrame.new(0, 0.37, 0) * ALONG_Y, Color3.fromRGB(30, 18, 12), MAT.SmoothPlastic)
	b.box("Handle", Vector3.new(0.06, 0.22, 0.07), Vector3.new(0.27, 0.2, 0), color, MAT.SmoothPlastic)
	b.box("Handle", Vector3.new(0.12, 0.05, 0.04), Vector3.new(0.21, 0.305, 0), color, MAT.SmoothPlastic)
	b.box("Handle", Vector3.new(0.12, 0.05, 0.04), Vector3.new(0.21, 0.095, 0), color, MAT.SmoothPlastic)
end

local function paperTray(b: Builder)
	b.box("Tray", Vector3.new(1.2, 0.04, 1.5), Vector3.new(0, 0.02, 0), COL.dark, MAT.Metal)
	for _, s in { -1, 1 } do
		b.box("TrayWall", Vector3.new(0.04, 0.22, 1.5), Vector3.new(s * 0.58, 0.15, 0), COL.dark, MAT.Metal)
	end
	b.box("TrayBack", Vector3.new(1.12, 0.22, 0.04), Vector3.new(0, 0.15, 0.73), COL.dark, MAT.Metal)
	for i = 1, 3 do
		b.box("Paper", Vector3.new(0.9, 0.02, 1.2), CFrame.new(0.02 * i, 0.04 + i * 0.03, 0) * CFrame.Angles(0, math.rad(i * 3 - 6), 0), COL.paper, MAT.SmoothPlastic)
	end
	b.cyl("Pen", 0.7, 0.05, CFrame.new(0.95, 0.025, -0.3) * CFrame.Angles(0, math.rad(-30), 0), COL.black, MAT.SmoothPlastic)
end

-- A PC tower open on its left side behind a tinted window, with its parts lit inside.
local function pcTower(b: Builder)
	for _, x in { -0.35, 0.35 } do
		for _, z in { -0.85, 0.85 } do
			b.cyl("Foot", 0.08, 0.14, CFrame.new(x, 0.04, z) * ALONG_Y, COL.rubber, MAT.Rubber)
		end
	end
	b.box("Side", Vector3.new(0.06, 2.0, 2.0), Vector3.new(0.42, 1.08, 0), COL.dark, MAT.Metal, true)
	b.box("Top", Vector3.new(0.84, 0.06, 2.0), Vector3.new(-0.03, 2.05, 0), COL.dark, MAT.Metal, true)
	b.box("Bottom", Vector3.new(0.84, 0.06, 2.0), Vector3.new(-0.03, 0.11, 0), COL.dark, MAT.Metal, true)
	b.box("Back", Vector3.new(0.84, 1.88, 0.06), Vector3.new(-0.03, 1.08, 0.97), COL.dark, MAT.Metal, true)
	local front = b.box("Front", Vector3.new(0.84, 1.88, 0.06), Vector3.new(-0.03, 1.08, -0.97), COL.black, MAT.Metal, true)
	local window = b.box("Window", Vector3.new(0.02, 1.88, 1.88), Vector3.new(-0.44, 1.08, 0), COL.glass, MAT.Glass)
	window.Transparency = 0.45
	b.box("Board", Vector3.new(0.04, 1.6, 1.6), Vector3.new(0.35, 1.1, 0.05), COL.pcb, MAT.SmoothPlastic)
	b.box("Card", Vector3.new(0.3, 0.25, 1.2), Vector3.new(0.17, 0.8, -0.2), COL.black, MAT.Metal)
	b.box("CardGlow", Vector3.new(0.02, 0.04, 1.0), Vector3.new(0.01, 0.8, -0.2), COL.cyan, MAT.Neon)
	b.cyl("Fan", 0.12, 0.5, CFrame.new(0.25, 1.5, 0.15), COL.black, MAT.Metal)
	b.cyl("FanRing", 0.04, 0.56, CFrame.new(0.16, 1.5, 0.15), COL.cyan, MAT.Neon)
	-- Front panel: power button with a lit ring, a drive slot and a grille.
	b.cyl("PowerRing", 0.02, 0.24, CFrame.new(-0.03, 1.85, -1.01) * ALONG_Z, COL.cyan, MAT.Neon)
	b.cyl("Power", 0.025, 0.18, CFrame.new(-0.03, 1.85, -1.0325) * ALONG_Z, COL.edge, MAT.Metal)
	b.box("DriveSlot", Vector3.new(0.5, 0.06, 0.02), Vector3.new(-0.03, 1.6, -1.01), COL.edge, MAT.Metal)
	b.box("Grille", Vector3.new(0.6, 1.1, 0.02), Vector3.new(-0.03, 0.85, -1.01), COL.dark, MAT.Metal)
	for i = 1, 6 do
		b.box("GrilleBar", Vector3.new(0.6, 0.05, 0.03), Vector3.new(-0.03, 0.4 + i * 0.15, -1.035), COL.edge, MAT.Metal)
	end
	return front
end

local function chair(b: Builder)
	for i = 0, 4 do
		local a = i * math.pi * 2 / 5
		b.box("Leg", Vector3.new(0.16, 0.1, 0.8), CFrame.Angles(0, a, 0) * CFrame.new(0, 0.22, -0.55), COL.dark, MAT.Metal)
		b.ball("Caster", 0.2, (CFrame.Angles(0, a, 0) * CFrame.new(0, 0.1, -0.92)).Position, COL.rubber, MAT.Rubber)
	end
	b.cyl("Hub", 0.16, 0.35, CFrame.new(0, 0.22, 0) * ALONG_Y, COL.dark, MAT.Metal)
	b.cyl("Shroud", 0.45, 0.22, CFrame.new(0, 0.5, 0) * ALONG_Y, COL.black, MAT.SmoothPlastic)
	b.cyl("Gas", 0.55, 0.13, CFrame.new(0, 0.95, 0) * ALONG_Y, COL.edge, MAT.Metal)
	b.box("Mechanism", Vector3.new(0.8, 0.12, 0.8), Vector3.new(0, 1.2, 0), COL.dark, MAT.Metal)
	b.box("Lever", Vector3.new(0.4, 0.04, 0.05), Vector3.new(0.55, 1.18, -0.2), COL.edge, MAT.Metal)
	b.box("SeatPan", Vector3.new(1.8, 0.1, 1.8), Vector3.new(0, 1.31, 0), COL.dark, MAT.Metal)
	b.bevel("Cushion", Vector3.new(1.76, 0.26, 1.7), CFrame.new(0, 1.49, -0.02), 0.08, "X", COL.leather, MAT.Leather, true)
	b.box("Spine", Vector3.new(0.3, 1.5, 0.12), Vector3.new(0, 1.95, 0.98), COL.dark, MAT.Metal)
	b.bevel("Lumbar", Vector3.new(1.7, 1.0, 0.26), CFrame.new(0, 2.15, 0.86) * CFrame.Angles(math.rad(6), 0, 0), 0.07, "Y", COL.leather, MAT.Leather)
	b.bevel("Back", Vector3.new(1.6, 1.15, 0.24), CFrame.new(0, 3.12, 0.97) * CFrame.Angles(math.rad(12), 0, 0), 0.07, "Y", COL.leather, MAT.Leather)
	for _, x in { -1, 1 } do
		b.box("ArmPost", Vector3.new(0.1, 0.55, 0.1), Vector3.new(x * 0.98, 1.66, 0.1), COL.dark, MAT.Metal)
		b.box("ArmPad", Vector3.new(0.24, 0.08, 0.9), Vector3.new(x * 0.98, 1.975, 0.05), COL.rubber, MAT.Rubber)
	end
end

local function workstation(b: Builder)
	desk(b)
	local top = CFrame.new(0, DESK_H, 0)
	monitor("Camera")(b.sub(top * CFrame.new(-1.75, 0, 0.85) * CFrame.Angles(0, math.rad(-12), 0)))
	monitor("Terminals")(b.sub(top * CFrame.new(1.25, 0, 0.85) * CFrame.Angles(0, math.rad(12), 0)))
	keyboard(b.sub(top * CFrame.new(-0.3, 0, -0.75)))
	mouse(b.sub(top * CFrame.new(1.25, 0, -0.75)))
	mug(b.sub(top * CFrame.new(3.2, 0, -1.1)))
	paperTray(b.sub(top * CFrame.new(-3.0, 0, -0.5)))
	pcTower(b.sub(CFrame.new(-2.5, 0, 0.55)))
	chair(b.sub(CFrame.new(-0.3, 0, -3.2) * CFrame.Angles(0, math.pi + math.rad(10), 0)))
end

-- Buttons and indicator lamps on a deck: a grid of small LEDs the client blinks.
local function buttonDeck(part: BasePart, seed: number)
	local rng = Random.new(seed)
	local dots = {}
	for row = 0, 3 do
		for col = 0, 17 do
			if col % 6 ~= 5 then
				table.insert(dots, { 0.06 + row * 0.12, 0.04 + col * 0.053, rng:NextInteger(1, 4) })
			end
		end
	end
	leds(part, dots, Enum.NormalId.Top, 7)
end

local function console(b: Builder)
	b.box("ToeKick", Vector3.new(7.8, 0.1, 2.2), Vector3.new(0, 0.05, 0.3), COL.black, MAT.Metal)
	b.bevel("Cabinet", Vector3.new(8, 2.4, 2.4), CFrame.new(0, 1.3, 0.2), 0.12, "Y", COL.dark, MAT.Metal, true)
	for _, x in { -2.6, 0, 2.6 } do
		b.box("Door", Vector3.new(2.4, 1.9, 0.04), Vector3.new(x, 1.3, -1.02), COL.plate, MAT.Metal)
		for i = 1, 3 do
			b.box("Vent", Vector3.new(1.6, 0.08, 0.02), Vector3.new(x - 0.2, 1.75 + i * 0.12, -1.05), COL.black, MAT.Metal)
		end
		b.box("Handle", Vector3.new(0.08, 0.5, 0.1), Vector3.new(x + 1.0, 1.3, -1.09), COL.edge, MAT.Metal)
	end
	b.wedge("Deck", Vector3.new(8, 0.7, 2.0), Vector3.new(0, 2.85, 0), COL.dark, MAT.Metal, true)
	local angle = math.atan2(0.7, 2.0)
	local deckCF = CFrame.new(0, 2.85, 0) * CFrame.Angles(-angle, 0, 0) * CFrame.new(0, 0.02, 0)
	local deckPlate = b.box("ControlDeck", Vector3.new(7.6, 0.04, 2.0), deckCF, COL.plate, MAT.Metal)
	buttonDeck(deckPlate, 11)
	local surface = b.sub(deckCF * CFrame.new(0, 0.02, 0))
	for i, x in { -3.3, -2.9, 2.9, 3.3 } do
		surface.cyl("Knob", 0.12, 0.2, CFrame.new(x, 0.06, 0.55 - (i % 2) * 0.3) * ALONG_Y, COL.edge, MAT.Metal)
	end
	surface.cyl("StickBase", 0.06, 0.4, CFrame.new(2.0, 0.03, -0.45) * ALONG_Y, COL.black, MAT.Rubber)
	surface.cyl("Stick", 0.4, 0.07, CFrame.new(2.0, 0.26, -0.45) * ALONG_Y, COL.edge, MAT.Metal)
	surface.ball("StickTop", 0.16, Vector3.new(2.0, 0.5, -0.45), COL.red, MAT.SmoothPlastic)
	keyboard(b.sub(deckCF * CFrame.new(-0.6, 0.02, -0.35)))
	b.box("Riser", Vector3.new(8, 2.4, 0.5), Vector3.new(0, 3.7, 1.25), COL.dark, MAT.Metal)
	b.box("Hood", Vector3.new(8.2, 0.12, 1.1), Vector3.new(0, 4.96, 0.95), COL.dark, MAT.Metal)
	for i, feed in { "Status", "Map", "Camera" } do
		local x = (i - 2) * 2.62
		local y = 4.05
		for _, s in { -1, 1 } do
			b.box("Bezel", Vector3.new(2.5, 0.12, 0.07), Vector3.new(x, y + s * 0.785, 0.955), COL.black, MAT.SmoothPlastic)
			b.box("Bezel", Vector3.new(0.08, 1.45, 0.07), Vector3.new(x + s * 1.21, y, 0.955), COL.black, MAT.SmoothPlastic)
		end
		kitScreen(b, Vector3.new(2.34, 1.45, 0.04), Vector3.new(x, y, 0.98), feed)
	end
	for _, x in { -3.6, 3.6 } do
		statusLight(b, Vector3.new(0.4, 0.2, 0.4), Vector3.new(x, 5.12, 0.95))
	end
end

local function wallMonitor(feed: string)
	return function(b: Builder)
		local y = 8
		b.box("Mount", Vector3.new(1.6, 1.6, 0.1), Vector3.new(0, y, -0.05), COL.dark, MAT.Metal)
		for _, s in { -1, 1 } do
			bolt(b, s * 0.6, y + 0.6, -0.1, 0.12)
			bolt(b, s * 0.6, y - 0.6, -0.1, 0.12)
		end
		b.box("Arm", Vector3.new(0.4, 0.4, 0.5), Vector3.new(0, y, -0.35), COL.edge, MAT.Metal)
		b.bevel("Housing", Vector3.new(6.6, 3.9, 0.36), CFrame.new(0, y, -0.78), 0.1, "Y", COL.dark, MAT.Metal)
		for _, s in { -1, 1 } do
			b.box("Bezel", Vector3.new(6.4, 0.18, 0.06), Vector3.new(0, y + s * 1.86, -0.99), COL.black, MAT.SmoothPlastic)
			b.box("Bezel", Vector3.new(0.18, 3.54, 0.06), Vector3.new(s * 3.11, y, -0.99), COL.black, MAT.SmoothPlastic)
		end
		kitScreen(b, Vector3.new(6.04, 3.54, 0.04), Vector3.new(0, y, -0.98), feed)
		statusLight(b, Vector3.new(0.2, 0.06, 0.02), Vector3.new(2.8, y - 1.86, -1.03))
	end
end

local function filingCabinet(b: Builder)
	b.box("Plinth", Vector3.new(1.7, 0.1, 2.4), Vector3.new(0, 0.05, 0), COL.black, MAT.Metal)
	b.bevel("Body", Vector3.new(1.8, 4.4, 2.6), CFrame.new(0, 2.3, 0), 0.08, "Y", COL.dark, MAT.Metal, true)
	for i = 1, 4 do
		local y = 0.15 + (i - 0.5) * 1.07
		b.box("Drawer", Vector3.new(1.56, 0.98, 0.06), Vector3.new(0, y, -1.33), COL.plate, MAT.Metal)
		b.box("LabelHolder", Vector3.new(0.5, 0.2, 0.03), Vector3.new(0, y + 0.28, -1.375), COL.edge, MAT.Metal)
		b.box("Label", Vector3.new(0.42, 0.14, 0.02), Vector3.new(0, y + 0.28, -1.4), COL.paper, MAT.SmoothPlastic)
		b.box("Pull", Vector3.new(0.6, 0.1, 0.08), Vector3.new(0, y + 0.02, -1.4), COL.edge, MAT.Metal)
	end
end

local function locker(b: Builder)
	for _, x in { -1.4, 1.4 } do
		b.box("Foot", Vector3.new(0.2, 0.2, 1.6), Vector3.new(x, 0.1, 0), COL.black, MAT.Metal)
	end
	b.box("Body", Vector3.new(3.2, 6.8, 1.8), Vector3.new(0, 3.6, 0), COL.dark, MAT.Metal, true)
	b.wedge("Cap", Vector3.new(3.2, 0.4, 1.8), Vector3.new(0, 7.2, 0), COL.dark, MAT.Metal)
	for _, x in { -1, 1 } do
		local dx = x * 0.79
		b.box("Door", Vector3.new(1.52, 6.6, 0.06), Vector3.new(dx, 3.6, -0.93), COL.plate, MAT.Metal)
		for i = 1, 5 do
			b.box("Slit", Vector3.new(0.9, 0.06, 0.02), Vector3.new(dx, 6.55 - i * 0.16, -0.97), COL.black, MAT.Metal)
			b.box("Slit", Vector3.new(0.9, 0.06, 0.02), Vector3.new(dx, 0.55 + i * 0.16, -0.97), COL.black, MAT.Metal)
		end
		b.box("Handle", Vector3.new(0.08, 0.7, 0.1), Vector3.new(dx - x * 0.6, 3.6, -1.01), COL.edge, MAT.Metal)
		b.box("NameTag", Vector3.new(0.5, 0.22, 0.02), Vector3.new(dx, 5.1, -0.97), COL.paper, MAT.SmoothPlastic)
	end
	b.box("Hasp", Vector3.new(0.14, 0.3, 0.06), Vector3.new(-0.3, 3.6, -0.99), COL.edge, MAT.Metal)
	b.box("Padlock", Vector3.new(0.18, 0.2, 0.1), Vector3.new(-0.33, 3.3, -1.07), COL.hazard, MAT.Metal)
end

local function shelf(b: Builder)
	for _, x in { -1, 1 } do
		for _, z in { -1, 1 } do
			b.box("Post", Vector3.new(0.2, 7, 0.04), Vector3.new(x * 2.9, 3.5, z * 0.98), COL.edge, MAT.Metal)
			b.box("Post", Vector3.new(0.04, 7, 0.16), Vector3.new(x * 2.98, 3.5, z * 0.88), COL.edge, MAT.Metal)
		end
	end
	local rng = Random.new(5)
	for level, y in { 0.4, 2.4, 4.4, 6.4 } do
		b.box("Shelf", Vector3.new(5.6, 0.08, 1.84), Vector3.new(0, y, 0), COL.dark, MAT.Metal, true)
		for _, s in { -1, 1 } do
			b.box("Lip", Vector3.new(5.6, 0.2, 0.04), Vector3.new(0, y - 0.02, s * 0.94), COL.plate, MAT.Metal)
		end
		if level < 4 then
			local x = -2.6
			while true do
				local w = math.min(rng:NextNumber(0.9, 1.5), 2.7 - x)
				if w < 0.6 then
					break
				end
				local h = rng:NextNumber(0.7, 1.3)
				local d = rng:NextNumber(1.1, 1.6)
				if rng:NextNumber() < 0.85 then
					if rng:NextNumber() < 0.5 then
						b.box("Box", Vector3.new(w, h, d), Vector3.new(x + w / 2, y + 0.04 + h / 2, 0.05), COL.cardboard, MAT.Cardboard)
						b.box("Tape", Vector3.new(w + 0.02, 0.03, 0.18), Vector3.new(x + w / 2, y + 0.04 + h + 0.015, 0.05), Color3.fromRGB(150, 130, 90), MAT.SmoothPlastic)
					else
						b.box("Bin", Vector3.new(w, h, d), Vector3.new(x + w / 2, y + 0.04 + h / 2, 0.05), COL.plate, MAT.SmoothPlastic)
						b.box("BinLabel", Vector3.new(0.4, 0.2, 0.02), Vector3.new(x + w / 2, y + 0.04 + h * 0.7, 0.05 - d / 2 - 0.01), COL.paper, MAT.SmoothPlastic)
					end
				end
				x += w + 0.15
			end
		end
	end
	local brace = math.atan2(6, 5.8)
	b.box("Brace", Vector3.new(8.3, 0.1, 0.04), CFrame.new(0, 3.4, 1.04) * CFrame.Angles(0, 0, brace), COL.edge, MAT.Metal)
	b.box("Brace", Vector3.new(8.3, 0.1, 0.04), CFrame.new(0, 3.4, 1.1) * CFrame.Angles(0, 0, -brace), COL.edge, MAT.Metal)
end

------------------------------------------------------------------------------------------------------------
-- Server room

local function serverRack(seed: number)
	return function(b: Builder)
		local base = b.box("Plinth", Vector3.new(2.8, 0.3, 4.0), Vector3.new(0, 0.15, 0), COL.dark, MAT.Metal, true)
		textGui(base, string.format("RACK %02d", seed * 7), COL.stencil, { transparency = 0.2, padX = 0.2, padY = 0.15 })
		b.box("TopFrame", Vector3.new(2.8, 0.3, 4.0), Vector3.new(0, 7.85, 0), COL.dark, MAT.Metal, true)
		b.box("Core", Vector3.new(2.4, 7.4, 3.6), Vector3.new(0, 4, 0.2), COL.black, MAT.Metal, true)
		for _, x in { -1.3, 1.3 } do
			for _, z in { -1.9, 1.9 } do
				b.box("Post", Vector3.new(0.2, 7.4, 0.2), Vector3.new(x, 4, z), COL.edge, MAT.Metal)
			end
			local sx = math.sign(x)
			b.box("Side", Vector3.new(0.06, 7.4, 3.6), Vector3.new(sx * 1.37, 4, 0), COL.dark, MAT.Metal)
			for i = 1, 6 do
				b.box("SideVent", Vector3.new(0.03, 0.08, 2.6), Vector3.new(sx * 1.415, 5.6 + i * 0.22, 0), COL.black, MAT.Metal)
			end
		end
		local rng = Random.new(seed)
		local dots = {}
		local y = 0.55
		while y < 7.4 do
			local units = if rng:NextNumber() < 0.25 then 2 else 1
			local h = 0.45 * units
			if y + h > 7.45 then
				break
			end
			if rng:NextNumber() < 0.9 then
				b.box("Server", Vector3.new(2.3, h - 0.06, 0.12), Vector3.new(0, y + h / 2, -1.66), COL.plate, MAT.Metal)
				b.box("Grip", Vector3.new(0.08, h - 0.16, 0.08), Vector3.new(-1.05, y + h / 2, -1.76), COL.edge, MAT.Metal)
				local sy = 1 - (y + h / 2 - 0.5) / 7.0
				for i = 1, rng:NextInteger(2, 5) do
					local roll = rng:NextNumber()
					table.insert(dots, { 0.6 + i * 0.065, sy, if roll < 0.55 then 1 elseif roll < 0.85 then 2 elseif roll < 0.95 then 3 else 4 })
				end
			else
				b.box("Blank", Vector3.new(2.3, h - 0.06, 0.04), Vector3.new(0, y + h / 2, -1.62), COL.dark, MAT.Metal)
			end
			y += h
		end
		local pane = b.box("Leds", Vector3.new(2.3, 7.0, 0.02), Vector3.new(0, 4, -1.82), COL.black, MAT.SmoothPlastic)
		pane.Transparency = 1
		leds(pane, dots)
		-- The front door: dark glass in a frame.
		-- Tinted plastic, not Glass: Glass hides the LED SurfaceGui behind it.
		local glass = b.box("DoorGlass", Vector3.new(2.1, 7.0, 0.04), Vector3.new(0, 4, -1.96), COL.glass, MAT.SmoothPlastic)
		glass.Transparency = 0.7
		glass.Reflectance = 0.08
		for _, s in { -1, 1 } do
			b.box("DoorFrame", Vector3.new(2.4, 0.15, 0.06), Vector3.new(0, 4 + s * 3.575, -1.97), COL.dark, MAT.Metal)
			b.box("DoorFrame", Vector3.new(0.15, 7.0, 0.06), Vector3.new(s * 1.125, 4, -1.97), COL.dark, MAT.Metal)
		end
		b.box("DoorHandle", Vector3.new(0.08, 0.9, 0.1), Vector3.new(0.9, 4, -2.05), COL.edge, MAT.Metal)
		statusLight(b, Vector3.new(1.0, 0.08, 0.03), Vector3.new(0, 7.85, -2.015))
		for i, x in { -0.5, 0, 0.5 } do
			b.cyl("Cable", 4, 0.16 + i * 0.03, CFrame.new(x, 10, 1.2) * ALONG_Y, COL.rubber, MAT.Rubber)
		end
	end
end

local function coolingUnit(b: Builder)
	b.box("Plinth", Vector3.new(6.1, 0.5, 3.1), Vector3.new(0, 0.25, 0), COL.dark, MAT.Metal, true)
	b.bevel("Body", Vector3.new(6, 7.1, 3), CFrame.new(0, 4.05, 0), 0.12, "Y", Color3.fromRGB(46, 49, 55), MAT.Metal, true)
	b.box("Top", Vector3.new(6.1, 0.4, 3.1), Vector3.new(0, 7.8, 0), COL.dark, MAT.Metal)
	for _, x in { -1.45, 1.45 } do
		b.box("GrilleHole", Vector3.new(2.6, 4, 0.04), Vector3.new(x, 3.2, -1.52), COL.black, MAT.Metal)
		for i = 1, 10 do
			b.box("Louver", Vector3.new(2.5, 0.08, 0.22), CFrame.new(x, 1.2 + i * 0.38, -1.62) * CFrame.Angles(math.rad(-35), 0, 0), COL.dark, MAT.Metal)
		end
		for _, s in { -1, 1 } do
			b.box("GrilleFrame", Vector3.new(2.8, 0.2, 0.2), Vector3.new(x, 3.2 + s * 2.1, -1.6), COL.edge, MAT.Metal)
		end
	end
	b.box("Seam", Vector3.new(0.08, 6.6, 0.03), Vector3.new(0, 4.05, -1.515), COL.black, MAT.Metal)
	b.box("ScreenBezel", Vector3.new(1.7, 1.1, 0.08), Vector3.new(-1.45, 6.4, -1.54), COL.black, MAT.SmoothPlastic)
	kitScreen(b, Vector3.new(1.5, 0.9, 0.04), Vector3.new(-1.45, 6.4, -1.6), "Graph")
	statusLight(b, Vector3.new(0.25, 0.25, 0.04), Vector3.new(1.0, 6.4, -1.52), "Power")
	b.box("Indicator", Vector3.new(0.25, 0.25, 0.04), Vector3.new(1.4, 6.4, -1.52), COL.amber, MAT.Neon)
	textGui(b.box("Label", Vector3.new(1.4, 0.35, 0.02), Vector3.new(1.45, 5.9, -1.51), COL.dark, MAT.Metal), "CRAC-2", COL.stencil, { transparency = 0.2, padY = 0.1 })
	for _, x in { 1.6, 2.4 } do
		b.cyl("Pipe", 8, 0.5, CFrame.new(x, 12, 0.6) * ALONG_Y, COL.worn, WORN)
		b.cyl("Flange", 0.2, 0.72, CFrame.new(x, 8.3, 0.6) * ALONG_Y, COL.dark, MAT.Metal)
	end
end

local function cableBundle(b: Builder)
	for _, c in { { -0.15, 0.3 }, { 0.12, 0.25 }, { 0.36, 0.22 } } do
		b.cyl("Cable", 8, c[2], CFrame.new(0, c[2] / 2, c[1]), COL.rubber, MAT.Rubber)
	end
	local cover = b.box("Cover", Vector3.new(2.4, 0.36, 0.7), Vector3.new(0, 0.18, 0.1), COL.hazard, MAT.Rubber, true)
	hazard(cover, Enum.NormalId.Top)
	for _, s in { -1, 1 } do
		b.prism("Ramp", Vector3.new(0, 0, 0.1 + s * 0.35), Vector3.new(0, 0.36, 0.1 + s * 0.35), Vector3.new(0, 0, 0.1 + s * 0.75), 2.4, COL.rubber, MAT.Rubber, true)
	end
end

------------------------------------------------------------------------------------------------------------
-- Industrial

local function pipeRun(b: Builder)
	local pipes = { { y = 11, d = 1.0, z = -1.15 }, { y = 12.35, d = 0.6, z = -0.9 }, { y = 9.85, d = 0.5, z = -0.85 } }
	for i, p in pipes do
		b.cyl("Pipe", 8, p.d, CFrame.new(0, p.y, p.z), if i == 2 then COL.dark else COL.worn, if i == 2 then MAT.Metal else WORN)
		for _, x in { -3.88, 3.88 } do
			b.cyl("Flange", 0.2, p.d + 0.3, CFrame.new(x, p.y, p.z), COL.dark, MAT.Metal)
		end
		for _, x in { -2.2, 2.2 } do
			b.cyl("Clamp", 0.2, p.d + 0.12, CFrame.new(x, p.y, p.z), COL.edge, MAT.Metal)
			local back = p.z + p.d / 2 + 0.06
			b.box("Arm", Vector3.new(0.16, 0.16, -0.3 - back), Vector3.new(x, p.y, (back - 0.3) / 2), COL.edge, MAT.Metal)
		end
	end
	for _, x in { -2.2, 2.2 } do
		b.box("Strut", Vector3.new(0.3, 3.6, 0.3), Vector3.new(x, 11.1, -0.15), COL.dark, MAT.Metal)
	end
	b.cyl("Band", 0.7, 1.04, CFrame.new(-0.8, 11, -1.15), COL.hazard, MAT.Metal)
	-- A gate valve facing out, with its handwheel.
	b.cyl("Bonnet", 0.7, 0.42, CFrame.new(1.2, 11, -1.95) * ALONG_Z, COL.dark, MAT.Metal)
	b.cyl("Stem", 0.4, 0.08, CFrame.new(1.2, 11, -2.5) * ALONG_Z, COL.edge, MAT.Metal)
	for k = 0, 7 do
		b.box("Wheel", Vector3.new(0.3, 0.08, 0.08), CFrame.new(1.2, 11, -2.62) * CFrame.Angles(0, 0, k * math.pi / 4) * CFrame.new(0, 0.42, 0), COL.red, MAT.Metal)
	end
	b.box("Spoke", Vector3.new(0.8, 0.06, 0.04), Vector3.new(1.2, 11, -2.62), COL.red, MAT.Metal)
	b.cyl("Hub", 0.16, 0.16, CFrame.new(1.2, 11, -2.7) * ALONG_Z, COL.edge, MAT.Metal)
	-- A pressure gauge.
	b.cyl("GaugeStem", 0.35, 0.12, CFrame.new(-1.6, 11, -1.8) * ALONG_Z, COL.edge, MAT.Metal)
	b.cyl("Gauge", 0.14, 0.6, CFrame.new(-1.6, 11, -2.04) * ALONG_Z, COL.dark, MAT.Metal)
	b.cyl("GaugeFace", 0.02, 0.5, CFrame.new(-1.6, 11, -2.12) * ALONG_Z, COL.paper, MAT.SmoothPlastic)
	b.box("Needle", Vector3.new(0.03, 0.2, 0.02), CFrame.new(-1.6, 11, -2.14) * CFrame.Angles(0, 0, math.rad(-35)) * CFrame.new(0, 0.08, 0), COL.red, MAT.SmoothPlastic)
	local label = b.box("PipeTag", Vector3.new(1.2, 0.32, 0.02), Vector3.new(-0.6, 12.35, -1.21), COL.hazard, MAT.SmoothPlastic)
	textGui(label, "COOLANT >>", COL.hazardDark, { padY = 0.1 })
end

local function pipeVertical(b: Builder)
	for i, p in { { x = -0.6, d = 0.9 }, { x = 0.6, d = 0.6 } } do
		local z = -(0.3 + p.d / 2)
		b.cyl("Pipe", 15.95, p.d, CFrame.new(p.x, 15.95 / 2, z) * ALONG_Y, if i == 1 then COL.worn else COL.dark, if i == 1 then WORN else MAT.Metal)
		for _, y in { 0.6, 6, 15.3 } do
			b.cyl("Flange", 0.2, p.d + 0.3, CFrame.new(p.x, y, z) * ALONG_Y, COL.dark, MAT.Metal)
		end
		for _, y in { 3, 12 } do
			b.cyl("Clamp", 0.24, p.d + 0.12, CFrame.new(p.x, y, z) * ALONG_Y, COL.edge, MAT.Metal)
		end
	end
	for _, y in { 3, 12 } do
		b.box("Bracket", Vector3.new(2.2, 0.3, 0.26), Vector3.new(0, y, -0.13), COL.edge, MAT.Metal)
	end
	b.cyl("Branch", 0.3, 0.5, CFrame.new(-0.6, 9, -0.15) * ALONG_Z, COL.worn, WORN)
	b.cyl("BranchFlange", 0.12, 0.72, CFrame.new(-0.6, 9, -0.06) * ALONG_Z, COL.dark, MAT.Metal)
end

local function junctionBox(b: Builder)
	local y = 4.5
	b.bevel("Box", Vector3.new(2.4, 3.0, 0.8), CFrame.new(0, y, -0.4), 0.1, "Y", Color3.fromRGB(46, 49, 55), MAT.Metal, true)
	b.box("Door", Vector3.new(2.1, 2.7, 0.05), Vector3.new(0, y, -0.825), COL.plate, MAT.Metal)
	for _, dy in { -0.9, 0.9 } do
		b.cyl("Hinge", 0.4, 0.08, CFrame.new(-1.08, y + dy, -0.83) * ALONG_Y, COL.edge, MAT.Metal)
	end
	b.box("Latch", Vector3.new(0.12, 0.4, 0.1), Vector3.new(0.88, y, -0.9), COL.edge, MAT.Metal)
	local warn = b.box("Warning", Vector3.new(0.9, 0.7, 0.02), Vector3.new(0, y + 0.7, -0.86), COL.hazard, MAT.SmoothPlastic)
	textGui(warn, "DANGER\n440 V", COL.hazardDark, { padY = 0.1 })
	statusLight(b, Vector3.new(0.2, 0.2, 0.03), Vector3.new(-0.75, y - 1.05, -0.865), "Power")
	for _, s in { -1, 1 } do
		local x = s * 0.5
		local y0 = if s > 0 then y + 1.55 else 0
		local y1 = if s > 0 then 16 else y - 1.55
		b.cyl("Conduit", y1 - y0, 0.4, CFrame.new(x, (y0 + y1) / 2, -0.35) * ALONG_Y, COL.dark, MAT.Metal)
		b.cyl("Gland", 0.15, 0.52, CFrame.new(x, if s > 0 then y + 1.575 else y - 1.575, -0.35) * ALONG_Y, COL.edge, MAT.Metal)
	end
end

local function crate(b: Builder)
	b.box("Core", Vector3.new(3.6, 3.6, 3.6), Vector3.new(0, 2, 0), COL.plate, MAT.DiamondPlate, true)
	for _, x in { -1, 1 } do
		for _, z in { -1, 1 } do
			b.box("EdgeV", Vector3.new(0.4, 4, 0.4), Vector3.new(x * 1.8, 2, z * 1.8), COL.dark, MAT.Metal, true)
			b.box("EdgeX", Vector3.new(3.2, 0.4, 0.4), Vector3.new(0, 2 + x * 1.8, z * 1.8), COL.dark, MAT.Metal)
			b.box("EdgeZ", Vector3.new(0.4, 0.4, 3.2), Vector3.new(x * 1.8, 2 + z * 1.8, 0), COL.dark, MAT.Metal)
		end
	end
	local diag = math.atan2(3.2, 3.2)
	for _, x in { -1, 1 } do
		b.box("Brace", Vector3.new(0.06, 4.3, 0.24), CFrame.new(x * 1.83, 2, 0) * CFrame.Angles(diag * x, 0, 0), COL.dark, MAT.Metal)
	end
	b.box("Brace", Vector3.new(4.3, 0.24, 0.06), CFrame.new(0, 2, 1.83) * CFrame.Angles(0, 0, diag), COL.dark, MAT.Metal)
	local stencil = b.box("Stencil", Vector3.new(2.8, 1.2, 0.02), Vector3.new(0, 2.2, -1.81), COL.plate, MAT.Metal)
	stencil.Transparency = 1
	textGui(stencil, "AXIOM\nDV-07 / B2", Color3.fromRGB(150, 145, 128), { transparency = 0.4, pps = 40 })
	for _, x in { -1.8, 1.8 } do
		for _, y in { 0.2, 3.8 } do
			bolt(b, x, y, -2.0, 0.14)
		end
	end
end

local function crateStack(b: Builder)
	crate(b.sub(CFrame.new(-2.05, 0, 0)))
	crate(b.sub(CFrame.new(2.35, 0, 0.3) * CFrame.Angles(0, math.rad(-6), 0)))
	crate(b.sub(CFrame.new(-0.8, 4, 0.1) * CFrame.Angles(0, math.rad(14), 0)))
end

local function barrel(b: Builder)
	b.cyl("Drum", 3.4, 2.2, CFrame.new(0, 1.7, 0) * ALONG_Y, COL.worn, WORN, true)
	for _, y in { 0.1, 1.15, 2.25, 3.3 } do
		b.cyl("Rib", 0.15, 2.3, CFrame.new(0, y, 0) * ALONG_Y, COL.dark, MAT.Metal)
	end
	b.cyl("Band", 0.6, 2.24, CFrame.new(0, 2.75, 0) * ALONG_Y, COL.hazard, MAT.Metal)
	b.cyl("Lid", 0.05, 1.9, CFrame.new(0, 3.425, 0) * ALONG_Y, COL.dark, MAT.Metal)
	b.cyl("Bung", 0.1, 0.35, CFrame.new(0.5, 3.5, 0.3) * ALONG_Y, COL.edge, MAT.Metal)
	b.cyl("Bung", 0.1, 0.22, CFrame.new(-0.55, 3.5, -0.35) * ALONG_Y, COL.edge, MAT.Metal)
end

local function railing(b: Builder)
	for _, x in { -3.8, 0, 3.8 } do
		b.box("BasePlate", Vector3.new(0.6, 0.06, 0.6), Vector3.new(x, 0.03, 0), COL.dark, MAT.Metal)
		b.box("Post", Vector3.new(0.24, 3.44, 0.24), Vector3.new(x, 0.06 + 1.72, 0), COL.dark, MAT.Metal, true)
		for _, dx in { -0.2, 0.2 } do
			b.cyl("Bolt", 0.05, 0.1, CFrame.new(x + dx, 0.085, 0.2) * ALONG_Y, COL.edge, MAT.Metal)
		end
	end
	b.cyl("TopRail", 8, 0.22, CFrame.new(0, 3.5, 0), Color3.fromRGB(150, 115, 30), MAT.Metal, true)
	b.cyl("MidRail", 8, 0.16, CFrame.new(0, 1.9, 0), COL.dark, MAT.Metal, true)
	b.box("KickPlate", Vector3.new(8, 0.4, 0.06), Vector3.new(0, 0.3, -0.15), COL.plate, MAT.Metal, true)
end

------------------------------------------------------------------------------------------------------------
-- Signs (wall-mounted at y 7 unless noted). Edit the TextLabel to change what a static sign says.

local function sign(text: string, size: Vector3, plateColor: Color3, textColor: Color3, stripe: boolean, mode: string?)
	return function(b: Builder)
		local y = 7
		b.bevel("Backer", size + Vector3.new(0.3, 0.3, 0), CFrame.new(0, y, -size.Z / 2), 0.05, "Y", COL.dark, MAT.Metal)
		local plate = b.box("Plate", Vector3.new(size.X, size.Y, 0.05), Vector3.new(0, y, -size.Z - 0.025), plateColor, MAT.SmoothPlastic)
		textGui(plate, text, textColor, { padY = if stripe then 0.22 else 0.12 })
		if stripe then
			local s = b.box("Stripe", Vector3.new(size.X, size.Y * 0.18, 0.04), Vector3.new(0, y - size.Y * 0.41, -size.Z - 0.07), COL.hazard, MAT.SmoothPlastic)
			hazard(s)
		end
		if mode then
			tag(plate, "KitSign", { SignMode = mode })
		end
		for _, x in { -1, 1 } do
			bolt(b, x * (size.X / 2 + 0.06), y + size.Y / 2 + 0.06, -size.Z, 0.12)
			bolt(b, x * (size.X / 2 + 0.06), y - size.Y / 2 - 0.06, -size.Z, 0.12)
		end
	end
end

-- A lit status sign: dark at rest; Lockdown and the finales light it up (KitSign, mode Lockdown).
local function lockdownSign(b: Builder)
	local y = 9
	b.bevel("Housing", Vector3.new(5.2, 1.5, 0.4), CFrame.new(0, y, -0.2), 0.1, "Y", COL.dark, MAT.Metal)
	local plate = b.box("Plate", Vector3.new(4.8, 1.1, 0.04), Vector3.new(0, y, -0.42), Color3.fromRGB(16, 17, 20), MAT.SmoothPlastic)
	textGui(plate, "STANDBY", Color3.fromRGB(70, 74, 80), { padY = 0.16 })
	tag(plate, "KitSign", { SignMode = "Lockdown" })
	for _, x in { -2.25, 2.25 } do
		b.box("Bracket", Vector3.new(0.2, 0.6, 0.2), Vector3.new(x, y + 0.95, -0.1), COL.edge, MAT.Metal)
	end
end

------------------------------------------------------------------------------------------------------------
-- Gameplay pieces: they follow the map contract, so the game drives them. Set their ids when placing.

-- Mainframe Terminal (Map/Terminals). The server writes the Screen part's colour and its Display.Text; the
-- reboot prompt sits on Console. A side screen shows the terminal's own progress (Terminal feed).
local function mainframe(b: Builder)
	local model = b.parent
	for key, value in { TerminalId = "TERM_NEW", Room = "", DisplayName = "New terminal", TargetKind = "CorruptTerminal", TargetId = "TERM_NEW", Progress = 0 } do
		model:SetAttribute(key, value)
	end
	b.box("Plinth", Vector3.new(7.2, 0.3, 3.4), Vector3.new(0, 0.15, 0.2), COL.black, MAT.Metal, true)
	local console = b.bevel("Console", Vector3.new(5.6, 2.9, 2.6), CFrame.new(0, 1.75, 0.2), 0.12, "Y", COL.dark, MAT.Metal, true)
	for _, x in { -1.3, 1.3 } do
		b.box("Door", Vector3.new(2.5, 2.1, 0.05), Vector3.new(x, 1.85, -1.125), COL.plate, MAT.Metal)
		for i = 1, 3 do
			b.box("Vent", Vector3.new(1.6, 0.08, 0.02), Vector3.new(x - 0.2 * math.sign(x), 2.3 + i * 0.13, -1.16), COL.black, MAT.Metal)
		end
		b.box("Handle", Vector3.new(0.1, 0.6, 0.1), Vector3.new(x - math.sign(x) * 1.0, 1.85, -1.2), COL.edge, MAT.Metal)
	end
	local kick = b.box("KickBand", Vector3.new(5.3, 0.3, 0.03), Vector3.new(0, 0.5, -1.115), COL.hazard, MAT.SmoothPlastic)
	hazard(kick)
	b.wedge("Deck", Vector3.new(5.6, 0.6, 1.6), Vector3.new(0, 3.5, -0.3), COL.dark, MAT.Metal, true)
	local angle = math.atan2(0.6, 1.6)
	local deckCF = CFrame.new(0, 3.5, -0.3) * CFrame.Angles(-angle, 0, 0) * CFrame.new(0, 0.02, 0)
	local deckPlate = b.box("ControlDeck", Vector3.new(5.2, 0.04, 1.6), deckCF, COL.plate, MAT.Metal)
	buttonDeck(deckPlate, 23)
	keyboard(b.sub(deckCF * CFrame.new(-1.0, 0.02, 0.1)))
	b.box("Riser", Vector3.new(5.2, 3.8, 0.6), Vector3.new(0, 5.1, 0.9), COL.dark, MAT.Metal, true)
	b.box("Hood", Vector3.new(5.6, 0.14, 1.2), Vector3.new(0, 7.07, 0.6), COL.dark, MAT.Metal)
	-- The contract's Screen: neon, so its edges glow in the status colour the server sets.
	local screen = b.box("Screen", Vector3.new(4.2, 2.6, 0.16), Vector3.new(0, 5.15, 0.52), Color3.fromRGB(110, 200, 255), MAT.Neon)
	local gui = Instance.new("SurfaceGui")
	gui.Name = "Display"
	gui.Face = Enum.NormalId.Front
	gui.LightInfluence = 0
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 60
	local back = Instance.new("Frame")
	back.Name = "Back"
	back.BorderSizePixel = 0
	back.Size = UDim2.fromScale(1, 1)
	back.BackgroundColor3 = Color3.fromRGB(5, 10, 16)
	back.Parent = gui
	local header = Instance.new("TextLabel")
	header.Name = "Header"
	header.BackgroundTransparency = 1
	header.Position = UDim2.fromScale(0.05, 0.04)
	header.Size = UDim2.fromScale(0.9, 0.16)
	header.FontFace = FONT.display
	header.Text = "AXIOM MAINFRAME ACCESS"
	header.TextScaled = true
	header.TextColor3 = Color3.fromRGB(66, 132, 124)
	header.Parent = back
	local rule = Instance.new("Frame")
	rule.BorderSizePixel = 0
	rule.Position = UDim2.fromScale(0.05, 0.22)
	rule.Size = UDim2.new(0.9, 0, 0, 2)
	rule.BackgroundColor3 = Color3.fromRGB(66, 132, 124)
	rule.Parent = back
	local label = Instance.new("TextLabel")
	label.Name = "Text"
	label.BackgroundTransparency = 1
	label.Position = UDim2.fromScale(0.06, 0.28)
	label.Size = UDim2.fromScale(0.88, 0.66)
	label.FontFace = FONT.display
	label.TextScaled = true
	label.TextColor3 = Color3.fromRGB(110, 200, 255)
	label.Text = "MAINFRAME\nREBOOT 0%"
	label.Parent = gui
	gui.Parent = screen
	for _, s in { -1, 1 } do
		b.box("Bezel", Vector3.new(4.6, 0.2, 0.22), Vector3.new(0, 5.15 + s * 1.4, 0.49), COL.black, MAT.Metal)
		b.box("Bezel", Vector3.new(0.2, 2.6, 0.22), Vector3.new(s * 2.2, 5.15, 0.49), COL.black, MAT.Metal)
	end
	local plaque = b.box("Plaque", Vector3.new(3.0, 0.3, 0.03), Vector3.new(0, 6.83, 0.585), COL.dark, MAT.Metal)
	textGui(plaque, "MAINFRAME TERMINAL", COL.stencil, { padY = 0.1 })
	-- Side towers with LED columns and status beacons.
	for _, s in { -1, 1 } do
		b.box("Tower", Vector3.new(0.7, 4.6, 2.0), Vector3.new(s * 3.15, 2.6, 0.4), COL.dark, MAT.Metal, true)
		local pane = b.box("Leds", Vector3.new(0.4, 3.6, 0.02), Vector3.new(s * 3.15, 2.6, -0.61), COL.black, MAT.SmoothPlastic)
		local dots = {}
		for i = 1, 16 do
			table.insert(dots, { 0.3, (i - 0.5) / 16, if i % 5 == 0 then 3 else 2 })
			table.insert(dots, { 0.7, (i - 0.5) / 16, 1 })
		end
		leds(pane, dots)
		statusLight(b, Vector3.new(0.5, 0.3, 0.5), Vector3.new(s * 3.15, 5.05, 0.4), "Terminal")
	end
	-- Side screen on an arm: the terminal's own progress.
	local arm = CFrame.new(3.15, 6.1, 0.2) * CFrame.Angles(0, math.rad(-28), 0)
	b.box("ArmPost", Vector3.new(0.2, 0.9, 0.2), Vector3.new(3.15, 5.65, 0.4), COL.edge, MAT.Metal)
	b.box("SideHousing", Vector3.new(1.9, 1.2, 0.14), arm * CFrame.new(0, 0, 0.07), COL.dark, MAT.Metal)
	kitScreen(b, Vector3.new(1.7, 1.0, 0.03), arm * CFrame.new(0, 0, -0.015), "Terminal")
	for _, x in { -1.6, -0.8, 0.8, 1.6 } do
		b.cyl("Cable", 7.0, 0.14, CFrame.new(x, 3.5, 1.32) * ALONG_Y, COL.rubber, MAT.Rubber)
	end
	return console
end

-- Security camera (Facility/Cameras). Lens's LookVector is the camera's view; RecLight lights while the
-- Chimera watches through it; a shot-out camera darkens Lens and Housing. Aim it by rotating the model.
local function securityCamera(b: Builder)
	local model = b.parent
	for key, value in { CameraId = "CAM_NEW", Room = "", DisplayName = "New camera", Links = "" } do
		model:SetAttribute(key, value)
	end
	local y = 12
	b.box("WallPlate", Vector3.new(0.9, 1.3, 0.12), Vector3.new(0, y, -0.06), COL.dark, MAT.Metal)
	for _, s in { -1, 1 } do
		bolt(b, s * 0.3, y + 0.5, -0.12, 0.1)
		bolt(b, s * 0.3, y - 0.5, -0.12, 0.1)
	end
	b.box("Arm", Vector3.new(0.24, 0.24, 1.0), Vector3.new(0, y + 0.3, -0.62), COL.dark, MAT.Metal)
	b.ball("Joint", 0.38, Vector3.new(0, y + 0.3, -1.2), COL.edge, MAT.Metal)
	local head = CFrame.new(0, y, -1.55) * CFrame.Angles(math.rad(-22), 0, 0)
	local housing = b.box("Housing", Vector3.new(0.8, 0.72, 1.7), head, COL.plate, MAT.Metal)
	b.box("Shield", Vector3.new(0.96, 0.06, 1.95), head * CFrame.new(0, 0.41, -0.1), COL.dark, MAT.Metal)
	b.cyl("Barrel", 0.16, 0.62, head * CFrame.new(0, -0.02, -0.93) * ALONG_Z, COL.dark, MAT.Metal)
	b.box("Lens", Vector3.new(0.4, 0.4, 0.1), head * CFrame.new(0, -0.02, -0.94), COL.glass, MAT.Glass)
	local rec = b.box("RecLight", Vector3.new(0.14, 0.14, 0.06), head * CFrame.new(0.3, 0.24, -0.88), COL.off, MAT.SmoothPlastic)
	local glow = Instance.new("PointLight")
	glow.Color = Color3.fromRGB(255, 30, 30)
	glow.Range = 6
	glow.Brightness = 2
	glow.Enabled = false
	glow.Parent = rec
	return housing
end

-- Sliding door (Map/Doors), for an 8 x 10 opening with DoorFrame_8x10. Place it closed in the doorway: it
-- opens by sliding Slide studs along its X. Only Panel moves; the trim is welded to it. LockLight1 and
-- LockLight2 sit on the frame's header and show the lock.
local function door(b: Builder)
	local model = b.parent
	for key, value in { DoorId = "D_NEW", RoomA = "", RoomB = "", DisplayName = "New door", TargetKind = "LockDoor", TargetId = "D_NEW", Slide = 8 } do
		model:SetAttribute(key, value)
	end
	local panel = b.box("Panel", Vector3.new(8, 10, 0.6), Vector3.new(0, 5, 0), COL.plate, MAT.Metal, true)
	local trim = {}
	local function add(p: BasePart): BasePart
		table.insert(trim, p)
		return p
	end
	for _, face in { -1, 1 } do
		-- `f` faces out of the door on this side; x * -face keeps a feature at the same world x on both sides.
		local f = b.sub(CFrame.new(0, 0, face * 0.3) * (if face > 0 then TURN else CFrame.identity))
		add(f.box("Border", Vector3.new(8, 0.5, 0.1), Vector3.new(0, 9.75, -0.05), COL.dark, MAT.Metal))
		add(f.box("Kick", Vector3.new(8, 0.9, 0.1), Vector3.new(0, 0.45, -0.05), COL.plate, MAT.DiamondPlate))
		for _, s in { -1, 1 } do
			add(f.box("Border", Vector3.new(0.5, 8.6, 0.1), Vector3.new(s * 3.75, 5.2, -0.05), COL.dark, MAT.Metal))
		end
		add(f.box("Inset", Vector3.new(7.0, 8.6, 0.04), Vector3.new(0, 5.2, -0.02), COL.sheet, MAT.Metal))
		local band = add(f.box("Band", Vector3.new(7.0, 0.8, 0.03), Vector3.new(0, 3.2, -0.055), COL.hazard, MAT.SmoothPlastic))
		hazard(band)
		add(f.box("Window", Vector3.new(1.3, 2.2, 0.03), Vector3.new(1.6 * -face, 6.9, -0.055), COL.glass, MAT.Glass))
		add(f.box("Handle", Vector3.new(0.14, 1.8, 0.14), Vector3.new(3.0 * face, 4.6, -0.18), COL.edge, MAT.Metal))
		for _, y in { 3.9, 5.3 } do
			add(f.box("HandleMount", Vector3.new(0.3, 0.2, 0.08), Vector3.new(3.0 * face, y, -0.08), COL.edge, MAT.Metal))
		end
		local stencil = add(f.box("Stencil", Vector3.new(4.0, 0.8, 0.02), Vector3.new(0.6 * face, 8.6, -0.05), COL.sheet, MAT.Metal))
		stencil.Transparency = 1
		textGui(stencil, "SECURITY DOOR", COL.stencil, { transparency = 0.35, padY = 0.15 })
		for _, x in { -3.75, 3.75 } do
			bolt(f, x, 9.75, -0.1, 0.12)
		end
	end
	for _, p in trim do
		p.Anchored = false
		p.Massless = true
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = panel
		weld.Part1 = p
		weld.Parent = p
	end
	for i, face in { -1, 1 } do
		b.box("LockLight" .. i, Vector3.new(2.4, 0.3, 0.12), Vector3.new(0, 10.4, face * 2.06), Color3.fromRGB(45, 45, 48), MAT.SmoothPlastic)
	end
	return panel
end

-- Emergency beacon (Facility/EmergencyLights/<RoomId>): its Lamp lights red when the wing's terminal is
-- rebooted.
local function emergencyLight(b: Builder)
	b.cyl("Base", 0.25, 1.1, CFrame.new(0, -0.125, 0) * ALONG_Y, COL.dark, MAT.Metal)
	b.cyl("Collar", 0.15, 0.95, CFrame.new(0, -0.325, 0) * ALONG_Y, COL.edge, MAT.Metal)
	local lamp = b.cyl("Lamp", 0.7, 0.82, CFrame.new(0, -0.75, 0) * ALONG_Y, COL.off, MAT.SmoothPlastic)
	local glow = Instance.new("PointLight")
	glow.Color = Color3.fromRGB(255, 60, 40)
	glow.Range = 30
	glow.Brightness = 1.4
	glow.Shadows = false
	glow.Enabled = false
	glow.Parent = lamp
	for _, p in { Vector3.new(0.47, -0.75, 0), Vector3.new(-0.47, -0.75, 0), Vector3.new(0, -0.75, 0.47), Vector3.new(0, -0.75, -0.47) } do
		b.box("Cage", Vector3.new(0.06, 0.8, 0.06), p, COL.edge, MAT.Metal)
	end
	b.cyl("CageRing", 0.06, 1.0, CFrame.new(0, -1.16, 0) * ALONG_Y, COL.edge, MAT.Metal)
end

------------------------------------------------------------------------------------------------------------
-- The kit list: category, name, mount, where it goes in the place, and the builder.

local GEOM, PROPS, LIGHTS = "Map/Geometry", "Map/Props", "Facility/Lights/<RoomId>"

local KIT = {
	{ "Walls", "WallPanel_8x16_Plate", "Wall", GEOM, wallPanel(8, 16, "Plate") },
	{ "Walls", "WallPanel_8x16_Ribbed", "Wall", GEOM, wallPanel(8, 16, "Ribbed") },
	{ "Walls", "WallPanel_8x16_Vent", "Wall", GEOM, wallPanel(8, 16, "Vent") },
	{ "Walls", "WallPanel_8x16_Pipes", "Wall", GEOM, wallPanel(8, 16, "Pipes") },
	{ "Walls", "WallPanel_8x16_Screen", "Wall", GEOM, wallPanel(8, 16, "Screen", false, "Status") },
	{ "Walls", "WallPanel_8x16_Hazard", "Wall", GEOM, wallPanel(8, 16, "Hazard") },
	{ "Walls", "WallPanel_8x16_Access", "Wall", GEOM, wallPanel(8, 16, "Access") },
	{ "Walls", "WallPanel_4x16_Plate", "Wall", GEOM, wallPanel(4, 16, "Plate") },
	{ "Walls", "WallPanel_8x12_Plate", "Wall", GEOM, wallPanel(8, 12, "Plate") },
	{ "Walls", "WallPanel_8x12_Ribbed", "Wall", GEOM, wallPanel(8, 12, "Ribbed") },
	{ "Walls", "WallPanel_8x12_Vent", "Wall", GEOM, wallPanel(8, 12, "Vent") },
	{ "Walls", "WallPanel_8x12_Screen", "Wall", GEOM, wallPanel(8, 12, "Screen", false, "Room") },
	{ "Walls", "WallPanel_4x12_Plate", "Wall", GEOM, wallPanel(4, 12, "Plate") },
	{ "Walls", "WallUpper_8x8", "Wall", GEOM, wallPanel(8, 8, "Plate", true) },
	{ "Walls", "WallUpper_8x8_Ribbed", "Wall", GEOM, wallPanel(8, 8, "Ribbed", true) },
	{ "Walls", "WallUpper_8x4", "Wall", GEOM, wallPanel(8, 4, "Plate", true) },
	{ "Walls", "WallCap_8", "Wall", GEOM, wallCap(8) },
	{ "Walls", "Pillar_16", "Floor", GEOM, pillar(16) },
	{ "Walls", "Pillar_12", "Floor", GEOM, pillar(12) },

	{ "Floors", "FloorPlate_8x8", "Floor", GEOM, floorPlate },
	{ "Floors", "FloorGrate_8x8", "Floor", GEOM, floorGrate },
	{ "Floors", "FloorHazard_8x1", "Floor", GEOM, floorHazard },
	{ "Floors", "FloorHatch_4x4", "Floor", GEOM, floorHatch },

	{ "Ceilings", "CeilingPanel_8x8", "Ceiling", GEOM, ceilingPanel },
	{ "Ceilings", "CeilingBeam_8", "Ceiling", GEOM, ceilingBeam },
	{ "Ceilings", "CeilingDuct_8", "Ceiling", GEOM, ceilingDuct },
	{ "Ceilings", "CableTray_8", "Ceiling", GEOM, cableTray },
	{ "Ceilings", "CeilingPipes_8", "Ceiling", GEOM, ceilingPipes },

	{ "Doorways", "DoorFrame_8x10", "Doorway", GEOM, doorFrame(8, 10) },
	{ "Doorways", "DoorFrame_12x10", "Doorway", GEOM, doorFrame(12, 10) },
	{ "Doorways", "DoorFrame_24x12", "Doorway", GEOM, doorFrame(24, 12) },
	{ "Doorways", "DoorFrame_24x14", "Doorway", GEOM, doorFrame(24, 14) },

	{ "Lights", "Light_CeilingStrip", "Ceiling", LIGHTS, lightStrip },
	{ "Lights", "Light_WallCage", "Wall", LIGHTS, lightCage },
	{ "Lights", "Light_Pendant", "Ceiling", LIGHTS, lightPendant },

	{ "Office", "Desk_8x4", "Floor", PROPS, desk },
	{ "Office", "Workstation_8x4", "Floor", PROPS, workstation },
	{ "Office", "Monitor_Status", "Desk", PROPS, monitor("Status") },
	{ "Office", "Monitor_Camera", "Desk", PROPS, monitor("Camera") },
	{ "Office", "Monitor_Terminals", "Desk", PROPS, monitor("Terminals") },
	{ "Office", "Monitor_Log", "Desk", PROPS, monitor("Log") },
	{ "Office", "Monitor_Squad", "Desk", PROPS, monitor("Squad") },
	{ "Office", "Monitor_Upload", "Desk", PROPS, monitor("Upload") },
	{ "Office", "Monitor_Alert", "Desk", PROPS, monitor("Alert") },
	{ "Office", "Monitor_Off", "Desk", PROPS, monitor("Off") },
	{ "Office", "Keyboard", "Desk", PROPS, keyboard },
	{ "Office", "Mouse", "Desk", PROPS, mouse },
	{ "Office", "Laptop", "Desk", PROPS, laptop },
	{ "Office", "Mug", "Desk", PROPS, mug },
	{ "Office", "PaperTray", "Desk", PROPS, paperTray },
	{ "Office", "PCTower", "Floor", PROPS, pcTower },
	{ "Office", "OfficeChair", "Floor", PROPS, chair },
	{ "Office", "ControlConsole_8", "Floor", PROPS, console },
	{ "Office", "WallMonitor_Map", "Wall", PROPS, wallMonitor("Map") },
	{ "Office", "WallMonitor_Camera", "Wall", PROPS, wallMonitor("Camera") },
	{ "Office", "WallMonitor_Status", "Wall", PROPS, wallMonitor("Status") },
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

	{ "Signs", "Sign_Sector", "Wall", PROPS, sign("SECTOR 07", Vector3.new(4, 1.6, 0.15), COL.dark, COL.text, true, "Room") },
	{ "Signs", "Sign_Direction", "Wall", PROPS, sign("<  THE CORE", Vector3.new(5, 1, 0.15), COL.dark, COL.text, false) },
	{ "Signs", "Sign_Warning", "Wall", PROPS, sign("DANGER\nHIGH VOLTAGE", Vector3.new(3, 2, 0.12), COL.hazard, COL.hazardDark, false) },
	{ "Signs", "Sign_Restricted", "Wall", PROPS, sign("RESTRICTED\nAUTHORIZED STAFF ONLY", Vector3.new(4, 1.6, 0.12), Color3.fromRGB(110, 22, 20), COL.text, false) },
	{ "Signs", "Sign_Lockdown", "Wall", PROPS, lockdownSign },

	{ "Gameplay", "MainframeTerminal", "Floor", "Map/Terminals", mainframe },
	{ "Gameplay", "SecurityCamera", "Wall", "Facility/Cameras", securityCamera },
	{ "Gameplay", "Door_8x10", "Doorway", "Map/Doors", door },
	{ "Gameplay", "Light_Emergency", "Ceiling", "Facility/EmergencyLights/<RoomId>", emergencyLight },
}

local CATEGORY_ORDER = { "Walls", "Floors", "Ceilings", "Doorways", "Lights", "Office", "ServerRoom", "Industrial", "Signs", "Gameplay" }

local function buildPiece(entry): Model
	local model = Instance.new("Model")
	model.Name = entry[2]
	model:SetAttribute("KitCategory", entry[1])
	model:SetAttribute("Mount", entry[3])
	model:SetAttribute("PlaceIn", entry[4])
	local primary = entry[5](newBuilder(model, CFrame.identity))
	if typeof(primary) == "Instance" and primary:IsA("BasePart") then
		-- With a PrimaryPart the pivot follows that part, so offset it back to the mount point.
		model.PrimaryPart = primary
		primary.PivotOffset = primary.CFrame:Inverse()
	end
	model.WorldPivot = CFrame.identity
	return model
end

local function build(): string
	ensureMaterials()
	prepareSample()
	local recording = ChangeHistoryService:TryBeginRecording("Build map kit")
	local old = ServerStorage:FindFirstChild("MapKit")
	if old then
		old:Destroy()
	end
	local root = Instance.new("Folder")
	root.Name = "MapKit"
	root:SetAttribute("Note", "Dark-metal kit pieces. Built by ServerStorage.DevTools.BuildMapKit; see its header for mounts, pivots and live pieces.")
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
		if pieces % 6 == 0 then
			task.wait()
		end
	end
	if recording then
		ChangeHistoryService:FinishRecording(recording, Enum.FinishRecordingOperation.Commit)
	end
	return `map kit built: {pieces} pieces, {parts} parts in ServerStorage.MapKit`
end

------------------------------------------------------------------------------------------------------------
-- Z-fight audit: two faces that point the same way, lie in the same plane and overlap fight for the pixel.

type Face = { part: BasePart, n: Vector3, d: number, verts: { Vector3 } }
type Plane = { n: Vector3, d: number }

local PLANE_EPS, OVERLAP_EPS = 0.012, 0.004

local function facesOf(part: BasePart, space: CFrame): { Face }
	local out = {}
	local cf = space:ToObjectSpace(part.CFrame)
	local size = part.Size
	local hx, hy, hz = size.X / 2, size.Y / 2, size.Z / 2
	local function P(x: number, y: number, z: number): Vector3
		return cf:PointToWorldSpace(Vector3.new(x, y, z))
	end
	local function add(normal: Vector3, verts: { Vector3 })
		local n = cf:VectorToWorldSpace(normal).Unit
		table.insert(out, { part = part, n = n, d = n:Dot(verts[1]), verts = verts })
	end
	if part:IsA("WedgePart") then
		add(Vector3.new(0, -1, 0), { P(-hx, -hy, -hz), P(hx, -hy, -hz), P(hx, -hy, hz), P(-hx, -hy, hz) })
		add(Vector3.new(0, 0, 1), { P(-hx, -hy, hz), P(hx, -hy, hz), P(hx, hy, hz), P(-hx, hy, hz) })
		add(Vector3.new(0, hz, -hy), { P(-hx, -hy, -hz), P(hx, -hy, -hz), P(hx, hy, hz), P(-hx, hy, hz) })
		for _, s in { -1, 1 } do
			add(Vector3.new(s, 0, 0), { P(s * hx, -hy, -hz), P(s * hx, -hy, hz), P(s * hx, hy, hz) })
		end
	elseif part:IsA("Part") and part.Shape == Enum.PartType.Cylinder then
		local r = math.min(hy, hz)
		for _, s in { -1, 1 } do
			local verts = {}
			for k = 0, 7 do
				local a = k * math.pi / 4
				table.insert(verts, P(s * hx, r * math.cos(a), r * math.sin(a)))
			end
			add(Vector3.new(s, 0, 0), verts)
		end
	elseif part:IsA("Part") and part.Shape == Enum.PartType.Block then
		for _, s in { -1, 1 } do
			add(Vector3.new(s, 0, 0), { P(s * hx, -hy, -hz), P(s * hx, hy, -hz), P(s * hx, hy, hz), P(s * hx, -hy, hz) })
			add(Vector3.new(0, s, 0), { P(-hx, s * hy, -hz), P(hx, s * hy, -hz), P(hx, s * hy, hz), P(-hx, s * hy, hz) })
			add(Vector3.new(0, 0, s), { P(-hx, -hy, s * hz), P(hx, -hy, s * hz), P(hx, hy, s * hz), P(-hx, hy, s * hz) })
		end
	end
	return out
end

local function overlap2D(a: { Vector2 }, b: { Vector2 }): boolean
	for _, poly in { a, b } do
		for i = 1, #poly do
			local edge = poly[i % #poly + 1] - poly[i]
			if edge.Magnitude > 1e-6 then
				local axis = Vector2.new(-edge.Y, edge.X).Unit
				local minA, maxA, minB, maxB = math.huge, -math.huge, math.huge, -math.huge
				for _, p in a do
					local d = p:Dot(axis)
					minA, maxA = math.min(minA, d), math.max(maxA, d)
				end
				for _, p in b do
					local d = p:Dot(axis)
					minB, maxB = math.min(minB, d), math.max(maxB, d)
				end
				if math.min(maxA, maxB) - math.max(minA, minB) <= OVERLAP_EPS then
					return false
				end
			end
		end
	end
	return true
end

local function visible(part: BasePart): boolean
	return part.Transparency < 0.99 or part:FindFirstChildWhichIsA("SurfaceGui") ~= nil
end

-- Faces lying on these planes face into a wall, floor or ceiling and are never seen.
local function hidden(face: Face, planes: { Plane }): boolean
	for _, plane in planes do
		if face.n:Dot(plane.n) > 0.999 and math.abs(face.d - plane.d) < 0.005 then
			return true
		end
	end
	return false
end

-- Is a point inside a part (in `space`)? Only opaque parts hide what's behind them.
local function inside(part: BasePart, point: Vector3, space: CFrame): boolean
	if part.Transparency > 0.3 then
		return false
	end
	local rel = space:ToObjectSpace(part.CFrame):PointToObjectSpace(point)
	local half = part.Size / 2 - Vector3.one * 0.001
	if math.abs(rel.X) >= half.X or math.abs(rel.Y) >= half.Y or math.abs(rel.Z) >= half.Z then
		return false
	end
	if part:IsA("WedgePart") then
		return (rel.Y + half.Y) / (2 * half.Y) < (rel.Z + half.Z) / (2 * half.Z)
	elseif part:IsA("Part") and part.Shape == Enum.PartType.Cylinder then
		local r = math.min(half.Y, half.Z)
		return rel.Y * rel.Y + rel.Z * rel.Z < r * r
	elseif part:IsA("Part") and part.Shape == Enum.PartType.Ball then
		return rel.Magnitude < half.X
	end
	return true
end

local function inPolygon(poly: { Vector2 }, q: Vector2): boolean
	local sign = 0
	for i = 1, #poly do
		local a, b = poly[i], poly[i % #poly + 1]
		local cross = (b.X - a.X) * (q.Y - a.Y) - (b.Y - a.Y) * (q.X - a.X)
		if math.abs(cross) > 1e-9 then
			local s = if cross > 0 then 1 else -1
			if sign == 0 then
				sign = s
			elseif s ~= sign then
				return false
			end
		end
	end
	return true
end

-- Points spread over where two coplanar faces overlap, nudged off the face toward its viewer.
local function overlapPoints(pa: { Vector2 }, pb: { Vector2 }, n: Vector3, d: number, u: Vector3, v: Vector3): { Vector3 }
	local function box(poly: { Vector2 }): (number, number, number, number)
		local x0, y0, x1, y1 = math.huge, math.huge, -math.huge, -math.huge
		for _, q in poly do
			x0, y0, x1, y1 = math.min(x0, q.X), math.min(y0, q.Y), math.max(x1, q.X), math.max(y1, q.Y)
		end
		return x0, y0, x1, y1
	end
	local ax0, ay0, ax1, ay1 = box(pa)
	local bx0, by0, bx1, by1 = box(pb)
	local x0, y0, x1, y1 = math.max(ax0, bx0), math.max(ay0, by0), math.min(ax1, bx1), math.min(ay1, by1)
	local points = {}
	for i = 0, 4 do
		for j = 0, 4 do
			local q = Vector2.new(x0 + (x1 - x0) * (i + 0.5) / 5, y0 + (y1 - y0) * (j + 0.5) / 5)
			if inPolygon(pa, q) and inPolygon(pb, q) then
				table.insert(points, n * (d + 0.02) + u * q.X + v * q.Y)
			end
		end
	end
	if #points == 0 then
		table.insert(points, n * (d + 0.02) + u * (x0 + x1) / 2 + v * (y0 + y1) / 2)
	end
	return points
end

local function round2(v: number): number
	local x = math.floor(v * 100 + 0.5) / 100
	return if x == 0 then 0 else x
end

-- Returns the overlaps you could see, and how many more are buried inside another solid part.
local function auditParts(parts: { BasePart }, space: CFrame, planes: { Plane }, owner: { [BasePart]: string }?): ({ string }, number)
	local groups: { [string]: { Face } } = {}
	local cylinders = {}
	for _, part in parts do
		if visible(part) then
			for _, face in facesOf(part, space) do
				if not hidden(face, planes) then
					local key = string.format("%.2f,%.2f,%.2f", round2(face.n.X), round2(face.n.Y), round2(face.n.Z))
					groups[key] = groups[key] or {}
					table.insert(groups[key], face)
				end
			end
			if part:IsA("Part") and part.Shape == Enum.PartType.Cylinder then
				table.insert(cylinders, part)
			end
		end
	end
	local issues = {}
	local seen = {}
	local buriedCount = 0
	local function label(p: BasePart): string
		return if owner and owner[p] then `{owner[p]}.{p.Name}` else p.Name
	end
	local function report(a: BasePart, b: BasePart, what: string)
		local ka, kb = tostring(a), tostring(b)
		local key = if ka < kb then ka .. "|" .. kb else kb .. "|" .. ka
		if not seen[key] then
			seen[key] = true
			table.insert(issues, `{label(a)} x {label(b)} ({what})`)
		end
	end
	for _, list in groups do
		table.sort(list, function(a, b)
			return a.d < b.d
		end)
		for i = 1, #list do
			local fa = list[i]
			local j = i + 1
			while j <= #list and list[j].d - fa.d < PLANE_EPS do
				local fb = list[j]
				if fb.part ~= fa.part then
					local n = fa.n
					local u = n:Cross(if math.abs(n.Y) < 0.9 then Vector3.yAxis else Vector3.xAxis).Unit
					local v = n:Cross(u)
					local pa, pb = {}, {}
					for _, p in fa.verts do
						table.insert(pa, Vector2.new(p:Dot(u), p:Dot(v)))
					end
					for _, p in fb.verts do
						table.insert(pb, Vector2.new(p:Dot(u), p:Dot(v)))
					end
					if overlap2D(pa, pb) then
						-- Hidden if every spot of the overlap is buried inside some other part.
						local covered = true
						for _, q in overlapPoints(pa, pb, n, fa.d, u, v) do
							local buried = false
							for _, other in parts do
								if other ~= fa.part and other ~= fb.part and inside(other, q, space) then
									buried = true
									break
								end
							end
							if not buried then
								covered = false
								break
							end
						end
						if covered then
							buriedCount += 1
						else
							report(fa.part, fb.part, string.format("faces %.2f,%.2f,%.2f", n.X, n.Y, n.Z))
						end
					end
				end
				j += 1
			end
		end
	end
	-- Curved sides: two cylinders on the same axis with the same radius.
	for i = 1, #cylinders do
		for j = i + 1, #cylinders do
			local a, b = cylinders[i], cylinders[j]
			local axis = a.CFrame.RightVector
			if math.abs(axis:Dot(b.CFrame.RightVector)) > 0.999 then
				local delta = b.Position - a.Position
				local along = delta:Dot(axis)
				local off = (delta - axis * along).Magnitude
				local ra, rb = math.min(a.Size.Y, a.Size.Z) / 2, math.min(b.Size.Y, b.Size.Z) / 2
				local reach = (a.Size.X + b.Size.X) / 2 - math.abs(along)
				if off < 0.01 and math.abs(ra - rb) < PLANE_EPS and reach > 0.01 then
					report(a, b, "curved sides")
				end
			end
		end
	end
	table.sort(issues)
	return issues, buriedCount
end

local function partsOf(root: Instance): { BasePart }
	local list = {}
	for _, d in root:GetDescendants() do
		if d:IsA("BasePart") then
			table.insert(list, d)
		end
	end
	return list
end

local MOUNT_PLANES: { [string]: { Plane } } = {
	Wall = { { n = Vector3.zAxis, d = 0 }, { n = -Vector3.yAxis, d = 0 } },
	Floor = { { n = -Vector3.yAxis, d = 0 } },
	Desk = { { n = -Vector3.yAxis, d = 0 } },
	Doorway = { { n = -Vector3.yAxis, d = 0 } },
	Ceiling = { { n = Vector3.yAxis, d = 0 } },
}

local function kitPiece(kit: Instance, name: string): Model
	for _, folder in kit:GetChildren() do
		local model = folder:FindFirstChild(name)
		if model then
			return (model :: Model):Clone()
		end
	end
	error(`no kit piece {name}`)
end

-- A short hallway built from the kit, to check pieces against each other: panels side by side and
-- stacked, a doorway with its door and an upper panel over it, floor tiles with a hazard strip, ceiling
-- tiles with a light and a tray, and props on the panels. The wall's face is z = 0, the floor y = 0 and
-- the ceiling y = 16.
local function sampleHall(kit: Instance): (Folder, { [BasePart]: string })
	local hall = Instance.new("Folder")
	hall.Name = "KitAuditHall"
	local owner = {}
	local count = 0
	local function put(name: string, cf: CFrame)
		local model = kitPiece(kit, name)
		model:PivotTo(cf)
		count += 1
		model.Name = `{name}#{count}`
		model.Parent = hall
		for _, p in partsOf(model) do
			owner[p] = model.Name
		end
	end
	put("WallPanel_8x16_Plate", CFrame.new(4, 0, 0))
	put("WallPanel_8x16_Vent", CFrame.new(12, 0, 0))
	put("WallPanel_8x16_Screen", CFrame.new(20, 0, 0))
	put("DoorFrame_8x10", CFrame.new(28, 0, 1))
	put("Door_8x10", CFrame.new(28, 0, 1))
	put("WallUpper_8x4", CFrame.new(28, 12, 0))
	put("WallPanel_8x16_Pipes", CFrame.new(36, 0, 0))
	put("WallPanel_8x16_Hazard", CFrame.new(44, 0, 0))
	put("WallUpper_8x8", CFrame.new(44, 16, 0))
	put("WallCap_8", CFrame.new(44, 24, 0))
	for i = 0, 5 do
		put("FloorPlate_8x8", CFrame.new(4 + i * 8, 0, -4))
		put("CeilingPanel_8x8", CFrame.new(4 + i * 8, 16, -4))
	end
	put("FloorHazard_8x1", CFrame.new(4, 0, -1))
	put("Light_CeilingStrip", CFrame.new(12, 16, -4))
	put("CableTray_8", CFrame.new(20, 16, -2))
	put("Sign_Sector", CFrame.new(4, 0, -Z_SHEET))
	put("JunctionBox", CFrame.new(44, 0, -Z_SHEET))
	put("WallMonitor_Map", CFrame.new(4, 3, -Z_SHEET))
	return hall, owner
end

local function audit(): string
	local kit = ServerStorage:FindFirstChild("MapKit")
	if not kit then
		build()
		kit = ServerStorage:FindFirstChild("MapKit")
	end
	local lines = {}
	local total, buried = 0, 0
	for _, category in CATEGORY_ORDER do
		local folder = (kit :: Instance):FindFirstChild(category)
		for _, model in (if folder then folder:GetChildren() else {}) do
			local planes = MOUNT_PLANES[model:GetAttribute("Mount")] or {}
			local issues, hiddenCount = auditParts(partsOf(model), (model :: Model):GetPivot(), planes)
			total += #issues
			buried += hiddenCount
			for _, issue in issues do
				table.insert(lines, `{model.Name}: {issue}`)
			end
		end
		task.wait()
	end
	local hall, owner = sampleHall(kit :: Instance)
	local planes = { { n = Vector3.zAxis, d = 0 }, { n = -Vector3.yAxis, d = 0 }, { n = Vector3.yAxis, d = 16 } }
	-- Pairs inside one piece were reported above; keep the ones between pieces.
	local hallIssues, hallBuried = auditParts(partsOf(hall), CFrame.identity, planes, owner)
	for _, issue in hallIssues do
		local a, b = string.match(issue, "^([^%.]+)%.[^ ]+ x ([^%.]+)%.")
		if a ~= b then
			total += 1
			table.insert(lines, "hall: " .. issue)
		end
	end
	hall:Destroy()
	table.insert(lines, 1, `Z-fight audit: {total} visible overlapping coplanar pairs ({#KIT} pieces and a sample hall); {buried + hallBuried} more are buried inside solid parts`)
	return table.concat(lines, "\n")
end

------------------------------------------------------------------------------------------------------------
-- The gallery

-- A plate standing on the gallery floor with a piece's name (or a row's category) on its front.
local function nameplate(g: Builder, text: string, size: Vector3, at: Vector3, color: Color3)
	local p = g.box("Label", size, at, COL.black, MAT.SmoothPlastic)
	p.CastShadow = false
	textGui(p, text, color, { light = 0, padX = 0.04, padY = 0.1, pps = 40 })
end

-- Lays a copy of every piece out in rows (one per category, in kit order) on a lit floor at `origin`, far
-- from the map, each with a nameplate in front. Wall pieces get a backdrop wall, ceiling pieces a slab to
-- hang from. Delete Workspace.MapKitGallery before saving the place.
local function gallery(origin: Vector3?): string
	local kit = ServerStorage:FindFirstChild("MapKit")
	if not kit then
		build()
		kit = ServerStorage:FindFirstChild("MapKit")
	end
	ensureMaterials()
	local base = origin or Vector3.new(0, 0, 700)
	local old = workspace:FindFirstChild("MapKitGallery")
	if old then
		old:Destroy()
	end
	local root = Instance.new("Folder")
	root.Name = "MapKitGallery"
	root.Parent = workspace
	local g = newBuilder(root, CFrame.new(base))
	local order = {}
	for i, entry in KIT do
		order[entry[2]] = i
	end
	local rowZ = 0
	for _, category in CATEGORY_ORDER do
		local folder = (kit :: Instance):FindFirstChild(category)
		if folder then
			local x = 0
			local deepest = 0
			local models = folder:GetChildren()
			table.sort(models, function(a, b)
				return (order[a.Name] or math.huge) < (order[b.Name] or math.huge)
			end)
			nameplate(g, string.upper(category), Vector3.new(10, 2.4, 0.2), Vector3.new(-7, 7, rowZ - 0.1), COL.cyan)
			for _, model in models do
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
				local front = z + offset.Z - size.Z / 2 - (if mount == "Desk" then 0.5 else 0)
				nameplate(g, `{copy.Name}\n{mount}`, Vector3.new(math.max(width, 4.5), 1.4, 0.15), Vector3.new(x + width / 2 + 0.5, 0.7, front - 2), COL.text)
				x += width + 4
				deepest = math.max(deepest, size.Z)
			end
			g.box("Floor", Vector3.new(x + 20, 1, deepest + 14), Vector3.new(x / 2 - 6, -0.5, rowZ - 4), Color3.fromRGB(30, 31, 34), MAT.Concrete)
			g.box("Backdrop", Vector3.new(x + 20, 18, 1), Vector3.new(x / 2 - 6, 9, rowZ + 0.5), Color3.fromRGB(36, 37, 40), MAT.Concrete)
			g.box("CeilingSlab", Vector3.new(x + 20, 1, deepest + 14), Vector3.new(x / 2 - 6, 18.5, rowZ - 4), Color3.fromRGB(30, 31, 34), MAT.Concrete)
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

return setmetatable({ build = build, gallery = gallery, audit = audit, KIT = KIT }, {
	__call = function()
		return build()
	end,
})
