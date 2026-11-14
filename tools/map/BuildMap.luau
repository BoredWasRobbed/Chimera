-- Builds Axiom Tower, Level 61 (the Chimera map), from ServerStorage.DevTools.MapLayout, which
-- tools/map/design_map.py generates: every structural block and finish, every prop (the map's own prefabs and
-- the map kit's pieces), the city outside the windows, the rain and city glow, and the place's lighting. Edit
-- the layout in the Python, not here. The build follows the map contract in src/shared/FacilityMap.luau.
--
-- A one-time generator, not game code: Rojo syncs it to ServerStorage.DevTools and nothing requires it at
-- runtime. Running it REPLACES Workspace.Map, Workspace.Facility, Workspace.City and Workspace.Weather (and
-- removes Workspace.MapKitGallery), so hand edits made in Studio since the last build are lost. It needs
-- ServerStorage.MapKit for the kit pieces (gameplay pieces, racks, screens); rebuild the kit first if it
-- changed. Run it in Edit mode from the command bar (the clone skips the module cache):
--   require(game.ServerStorage.DevTools.BuildMap:Clone()).run()     builds in the background; Studio stays
--       responsive. Progress shows in the Output and in DevTools' BuildMapStatus attribute.
--   require(game.ServerStorage.DevTools.BuildMap:Clone()).build()   builds and returns when done.
-- Lighting.Technology isn't scriptable from every context: set it to Future in the Properties window.
local ChangeHistoryService = game:GetService("ChangeHistoryService")
local CollectionService = game:GetService("CollectionService")
local HttpService = game:GetService("HttpService")
local Lighting = game:GetService("Lighting")
local MaterialService = game:GetService("MaterialService")
local ServerStorage = game:GetService("ServerStorage")

local BuildMap = {}

local CHUNK = 150 -- pieces per frame
local ZEKTON = "rbxasset://fonts/families/Zekton.json"

local function status(text: string)
	local tools = ServerStorage:FindFirstChild("DevTools")
	if tools then
		tools:SetAttribute("BuildMapStatus", text)
	end
	print("[BuildMap] " .. text)
end

local function loadLayout(): any
	local tools = ServerStorage:FindFirstChild("DevTools")
	local module = tools and tools:FindFirstChild("MapLayout")
	assert(module, "ServerStorage.DevTools.MapLayout is missing: run tools/map/design_map.py and let Rojo sync")
	local text = require(module:Clone()) :: any
	return HttpService:JSONDecode(text)
end

local function kitIndex(): { [string]: Model }
	local kit = ServerStorage:FindFirstChild("MapKit")
	assert(kit, "ServerStorage.MapKit is missing: run require(game.ServerStorage.DevTools.BuildMapKit:Clone())()")
	local index = {}
	for _, folder in kit:GetChildren() do
		for _, model in folder:GetChildren() do
			if model:IsA("Model") then
				index[model.Name] = model
			end
		end
	end
	return index
end

-- Folders by path ("Map/Geometry/CORE"), made on demand under the roots.
local function folderMaker(roots: { [string]: Instance })
	local cache: { [string]: Instance } = {}
	local function get(path: string): Instance
		local found = cache[path]
		if found then
			return found
		end
		local parentPath, name = string.match(path, "^(.*)/([^/]+)$")
		if not parentPath then
			local root = roots[path]
			assert(root, "no root " .. path)
			cache[path] = root
			return root
		end
		local parent = get(parentPath)
		local f = parent:FindFirstChild(name)
		if not f then
			f = Instance.new("Folder")
			f.Name = name
			f.Parent = parent
		end
		cache[path] = f
		return f
	end
	return get
end

local function rgb(c: { number }): Color3
	return Color3.fromRGB(c[1], c[2], c[3])
end

local materialCache: { [string]: Enum.Material } = {}
local function materialOf(name: string?): Enum.Material
	if not name then
		return Enum.Material.SmoothPlastic
	end
	local found = materialCache[name]
	if found then
		return found
	end
	local ok, value = pcall(function()
		return (Enum.Material :: any)[name]
	end)
	local m = if ok and value then value else Enum.Material.SmoothPlastic
	materialCache[name] = m
	return m
end

local function fontOf(name: string?, bold: boolean?): Font
	local weight = if bold then Enum.FontWeight.Bold else Enum.FontWeight.Regular
	if name == nil or name == "Zekton" then
		return Font.new(ZEKTON, weight)
	end
	local ok, enum = pcall(function()
		return (Enum.Font :: any)[name]
	end)
	if ok and enum then
		local f = Font.fromEnum(enum)
		if bold then
			f.Weight = Enum.FontWeight.Bold
		end
		return f
	end
	return Font.new(ZEKTON, weight)
end

-- A SurfaceGui with one TextLabel named Text (the gui is named SignText unless the record names it), so a
-- placement's `text` option and FacilityScreens' signs can rewrite it.
local function makeGui(part: BasePart, g: any)
	local gui = Instance.new("SurfaceGui")
	gui.Name = g.name or "SignText"
	gui.Face = (Enum.NormalId :: any)[g.face or "Front"]
	gui.LightInfluence = g.light or 1
	gui.Brightness = g.bright or 1
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = g.ppu or 40
	gui.ClipsDescendants = true
	local label = Instance.new("TextLabel")
	label.Name = "Text"
	label.Size = UDim2.fromScale(1, 1)
	label.BorderSizePixel = 0
	label.BackgroundTransparency = if g.bg then 0 else 1
	if g.bg then
		label.BackgroundColor3 = rgb(g.bg)
	end
	label.Text = g.text or ""
	label.TextColor3 = rgb(g.color or { 220, 220, 220 })
	label.TextTransparency = g.tt or 0
	label.FontFace = fontOf(g.font, g.bold == 1)
	label.TextWrapped = g.nowrap == nil
	label.TextXAlignment = (Enum.TextXAlignment :: any)[g.align or "Center"]
	label.TextYAlignment = (Enum.TextYAlignment :: any)[g.valign or "Center"]
	label.Rotation = g.rot or 0
	if g.size then
		label.TextSize = g.size * (g.ppu or 40)
	else
		label.TextScaled = true
	end
	local pad = math.floor((g.pad or 0.06) * (g.ppu or 40))
	if pad > 0 then
		local p = Instance.new("UIPadding")
		p.PaddingLeft = UDim.new(0, pad)
		p.PaddingRight = UDim.new(0, pad)
		p.PaddingTop = UDim.new(0, pad)
		p.PaddingBottom = UDim.new(0, pad)
		p.Parent = label
	end
	label.Parent = gui
	gui.Parent = part
end

local function makeLight(part: BasePart, l: any)
	local light: Light = if l.kind == "spot" then Instance.new("SpotLight") elseif l.kind == "surface" then Instance.new("SurfaceLight") else Instance.new("PointLight")
	light.Color = rgb(l.c)
	light.Range = l.range
	light.Brightness = l.brightness
	light.Shadows = l.shadows == true
	if l.face and (light:IsA("SpotLight") or light:IsA("SurfaceLight")) then
		(light :: any).Face = (Enum.NormalId :: any)[l.face]
	end
	if l.angle and (light:IsA("SpotLight") or light:IsA("SurfaceLight")) then
		(light :: any).Angle = l.angle
	end
	light.Enabled = l.off ~= true
	light.Parent = part
end

local function makeFx(part: BasePart, kind: string)
	local e = Instance.new("ParticleEmitter")
	e.Texture = "rbxasset://textures/particles/smoke_main.dds"
	e.Rotation = NumberRange.new(0, 360)
	e.RotSpeed = NumberRange.new(-8, 8)
	if kind == "steam" then
		-- Steam leaking from the plant: warmer, faster, rising.
		e.Color = ColorSequence.new(Color3.fromRGB(210, 210, 206))
		e.LightEmission = 0.05
		e.LightInfluence = 0.8
		e.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.25, 0.8), NumberSequenceKeypoint.new(1, 1) })
		e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 2), NumberSequenceKeypoint.new(1, 9) })
		e.Lifetime = NumberRange.new(4, 6)
		e.Rate = 3
		e.Speed = NumberRange.new(1, 2.5)
		e.SpreadAngle = Vector2.new(25, 25)
		e.Acceleration = Vector3.new(0.3, 0.9, 0)
	else
		-- Cold mist rolling off the floor.
		e.Color = ColorSequence.new(Color3.fromRGB(200, 228, 242))
		e.LightEmission = 0.05
		e.LightInfluence = 0.7
		e.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.3, 0.86), NumberSequenceKeypoint.new(1, 1) })
		e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 4), NumberSequenceKeypoint.new(1, 10) })
		e.Lifetime = NumberRange.new(7, 10)
		e.Rate = 2.5
		e.Speed = NumberRange.new(0.3, 0.8)
		e.SpreadAngle = Vector2.new(180, 15)
		e.Acceleration = Vector3.new(0, 0.12, 0)
	end
	e.Parent = part
end

local function decorate(part: BasePart, rec: any)
	if rec.tag then
		if type(rec.tag) == "table" then
			for _, t in rec.tag do
				CollectionService:AddTag(part, t)
			end
		else
			CollectionService:AddTag(part, rec.tag)
		end
	end
	if rec.a then
		for key, value in rec.a do
			part:SetAttribute(key, value)
		end
	end
	if rec.gui then
		makeGui(part, rec.gui)
	end
	if rec.tex then
		for _, t in rec.tex do
			local tx = Instance.new("Texture")
			tx.Texture = t.id
			tx.Face = (Enum.NormalId :: any)[t.face or "Front"]
			tx.StudsPerTileU = t.u or 8
			tx.StudsPerTileV = t.v or 8
			tx.OffsetStudsU = t.ou or 0
			tx.OffsetStudsV = t.ov or 0
			tx.Transparency = t.t or 0
			if t.tag then
				CollectionService:AddTag(tx, t.tag)
			end
			tx.Parent = part
		end
	end
	if rec.fx then
		makeFx(part, rec.fx)
	end
	if rec.light then
		makeLight(part, rec.light)
	end
end

local function newPart(rec: any): BasePart
	local part: BasePart
	local shape = rec.shape or rec.sh
	if rec.wedge or shape == "wedge" then
		part = Instance.new("WedgePart")
	else
		local p = Instance.new("Part")
		if shape == "cyl" then
			p.Shape = Enum.PartType.Cylinder
		elseif shape == "ball" then
			p.Shape = Enum.PartType.Ball
		end
		part = p
	end
	part.Name = rec.n
	part.Size = Vector3.new(rec.s[1], rec.s[2], rec.s[3])
	part.Material = materialOf(rec.m)
	part.Color = rgb(rec.c)
	if rec.v then
		part.MaterialVariant = rec.v
	end
	part.Anchored = true
	part.CanTouch = false
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	if rec.t then
		part.Transparency = rec.t
	end
	if rec.refl then
		part.Reflectance = rec.refl
	end
	if rec.ns then
		part.CastShadow = false
	end
	return part
end

local function angles(r: any): CFrame
	if type(r) == "number" then
		return CFrame.Angles(0, math.rad(r), 0)
	elseif type(r) == "table" then
		return CFrame.Angles(math.rad(r[1]), math.rad(r[2]), math.rad(r[3]))
	end
	return CFrame.identity
end

-- A plain world part from the layout: n name, f folder, p centre, s size, r turn, m material, c colour,
-- v material variant; flags nc (no collide), nq (no raycasts), t, refl, ns (no shadow), shape, tag, a, gui,
-- tex, fx, light.
local function makeBox(rec: any): BasePart
	local part = newPart(rec)
	part.CFrame = CFrame.new(rec.p[1], rec.p[2], rec.p[3]) * angles(rec.r)
	part.CanCollide = not rec.nc
	part.CanQuery = not rec.nq
	decorate(part, rec)
	return part
end

-- A prefab template: parts relative to the pivot, built once and cloned for each placement. Parts with
-- `weld` are welded (unanchored) to the named part, so they move with it (a door's trim on its Panel).
local function buildPrefab(name: string, def: any): Model
	local model = Instance.new("Model")
	model.Name = name
	local byName: { [string]: BasePart } = {}
	local welds = {}
	for _, rec in def.parts do
		local part = newPart(rec)
		local cf = rec.cf
		part.CFrame = CFrame.new(cf[1], cf[2], cf[3]) * CFrame.Angles(math.rad(cf[4]), math.rad(cf[5]), math.rad(cf[6]))
		part.CanCollide = rec.col == 1
		part.CanQuery = rec.nq == nil
		decorate(part, rec)
		part.Parent = model
		if not byName[rec.n] then
			byName[rec.n] = part
		end
		if rec.weld then
			table.insert(welds, { part, rec.weld })
		end
	end
	for _, w in welds do
		local part, to = w[1], byName[w[2]]
		if to then
			part.Anchored = false
			part.Massless = true
			local weld = Instance.new("WeldConstraint")
			weld.Part0 = to
			weld.Part1 = part
			weld.Parent = part
		end
	end
	model.WorldPivot = CFrame.identity
	return model
end

-- Turns a security camera's head (about its joint) so the Lens looks at `target`.
local function aimCamera(model: Model, target: Vector3)
	local joint = model:FindFirstChild("Joint") :: BasePart?
	local lens = model:FindFirstChild("Lens") :: BasePart?
	if not (joint and lens) then
		return
	end
	local function anglesOf(look: Vector3): (number, number)
		return math.atan2(-look.X, -look.Z), math.asin(math.clamp(look.Y, -1, 1))
	end
	local yaw0, pitch0 = anglesOf(lens.CFrame.LookVector)
	local yaw1, pitch1 = anglesOf((target - lens.Position).Unit)
	local pivot = CFrame.new(joint.Position)
	local from = CFrame.Angles(0, yaw0, 0) * CFrame.Angles(pitch0, 0, 0)
	local to = CFrame.Angles(0, yaw1, 0) * CFrame.Angles(pitch1, 0, 0)
	local turn = to * from:Inverse()
	for _, name in { "Housing", "Shield", "Barrel", "Lens", "RecLight" } do
		for _, part in model:GetChildren() do
			if part.Name == name and part:IsA("BasePart") then
				part.CFrame = pivot * turn * pivot:Inverse() * part.CFrame
			end
		end
	end
end

local function setLight(model: Instance, l: any)
	for _, d in model:GetDescendants() do
		if d:IsA("Light") then
			if l.kind then
				-- A different kind of light: replace it.
				local parent = d.Parent :: BasePart
				d:Destroy()
				makeLight(parent, l)
			else
				if l.c then
					d.Color = rgb(l.c)
				end
				if l.range then
					d.Range = l.range
				end
				if l.brightness then
					d.Brightness = l.brightness
				end
			end
		end
	end
end

local function setSignText(model: Instance, text: string)
	for _, d in model:GetDescendants() do
		if d:IsA("TextLabel") and d.Parent and d.Parent.Name == "SignText" then
			d.Text = text
			return
		end
	end
end

local function setFeeds(model: Instance, feed: string, cameraId: string?)
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") and CollectionService:HasTag(d, "KitScreen") then
			d:SetAttribute("Feed", feed)
			if cameraId then
				d:SetAttribute("CameraId", cameraId)
			end
		end
	end
end

-- Places one piece (a prefab, or a kit piece) and applies its options (see design_map.py's piece()).
local function placePiece(rec: { any }, prefabs: { [string]: Model }, kit: { [string]: Model }, getFolder: (string) -> Instance): Instance?
	local name, folderPath, x, y, z, yaw, opts = rec[1], rec[2], rec[3], rec[4], rec[5], rec[6], rec[7]
	local source = prefabs[name] or kit[name]
	if not source then
		warn(`[BuildMap] no prefab or kit piece {name}`)
		return nil
	end
	local model = source:Clone()
	local cf = CFrame.new(x, y, z) * CFrame.Angles(0, math.rad(yaw), 0)
	if opts and opts.look then
		cf = CFrame.lookAt(Vector3.new(x, y, z), Vector3.new(opts.look[1], opts.look[2], opts.look[3]))
	end
	if opts and opts.tilt then
		cf *= CFrame.Angles(math.rad(opts.tilt), 0, 0)
	end
	model:PivotTo(cf)
	for _, key in { "KitCategory", "Mount", "PlaceIn" } do
		model:SetAttribute(key, nil)
	end
	if opts then
		if opts.id then
			model.Name = opts.id
		end
		if opts.a then
			for key, value in opts.a do
				model:SetAttribute(key, value)
			end
		end
		if opts.text then
			setSignText(model, opts.text)
		end
		if opts.feed then
			setFeeds(model, opts.feed, opts.cameraId)
		end
		if opts.light then
			setLight(model, opts.light)
		end
		if opts.dead then
			-- A dead fixture: no lamp, no light (a prop, not in a Lights folder, so Blackout leaves it alone).
			for _, d in model:GetDescendants() do
				if d:IsA("Light") then
					d:Destroy()
				elseif d:IsA("BasePart") and d.Name == "Fixture" then
					d.Name = "DeadFixture"
					d.Material = Enum.Material.SmoothPlastic
					d.Color = Color3.fromRGB(46, 46, 48)
				end
			end
		end
		if opts.flicker then
			-- A failing fixture: the client's Ambience makes it stutter while its room has power.
			for _, d in model:GetDescendants() do
				if d:IsA("BasePart") and d.Name == "Fixture" then
					CollectionService:AddTag(d, "Flicker")
					d:SetAttribute("FlickerMode", opts.flicker)
				end
			end
		end
		if opts.aim then
			aimCamera(model, Vector3.new(opts.aim[1], opts.aim[2], opts.aim[3]))
		end
		if opts.strip then
			for _, d in model:GetDescendants() do
				if d:IsA("BasePart") and table.find(opts.strip, d.Name) then
					d:Destroy()
				end
			end
		end
		if opts.unpack == "part" then
			-- The piece is one part with its details as children (LightPanel, Floodlight): place the part.
			local primary = model.PrimaryPart
			if primary then
				primary.Parent = getFolder(folderPath)
				if opts.id then
					primary.Name = opts.id
				end
			end
			model:Destroy()
			return primary
		elseif opts.unpack == "station" then
			-- The Pad stays in Facility/Stations; the charger goes into Map/Props, where it blocks.
			local pad = model:FindFirstChild("Pad")
			local station = Instance.new("Model")
			station.Name = opts.id or "Station"
			station:SetAttribute("StationId", station.Name)
			if pad then
				pad.Parent = station
			end
			model.PrimaryPart = nil
			model.Name = `{station.Name}_Charger`
			model.Parent = getFolder(opts.props)
			station.Parent = getFolder(folderPath)
			return station
		elseif opts.unpack == "trap" then
			-- A pipe run's valve or a junction box becomes an Overload trap: its target part is renamed
			-- Target and an invisible Floor marker goes where mercs set it off.
			local target = model:FindFirstChild(opts.target)
			if target then
				target.Name = "Target"
			end
			local floor = Instance.new("Part")
			floor.Name = "Floor"
			floor.Size = Vector3.new(1, 0.2, 1)
			floor.CFrame = CFrame.new(opts.floor[1], opts.floor[2], opts.floor[3])
			floor.Anchored = true
			floor.CanCollide = false
			floor.CanTouch = false
			floor.CanQuery = false
			floor.Transparency = 1
			floor.Parent = model
		end
	end
	model.Parent = getFolder(folderPath)
	return model
end

local function makeRoots(): (Folder, Folder, Folder, Folder)
	for _, name in { "Map", "Facility", "MapKitGallery", "City", "Weather" } do
		local old = workspace:FindFirstChild(name)
		if old then
			old:Destroy()
		end
	end
	local map = Instance.new("Folder")
	map.Name = "Map"
	for _, name in { "Geometry", "Props", "Doors", "Docks", "Terminals" } do
		local f = Instance.new("Folder")
		f.Name = name
		f.Parent = map
	end
	local facility = Instance.new("Folder")
	facility.Name = "Facility"
	for _, name in { "Cameras", "Lights", "Rooms", "Spawns", "Stations", "Traps", "Core", "Floodlights", "EmergencyLights" } do
		local f = Instance.new("Folder")
		f.Name = name
		f.Parent = facility
	end
	local city = Instance.new("Folder")
	city.Name = "City"
	local weather = Instance.new("Folder")
	weather.Name = "Weather"
	map.Parent = workspace
	facility.Parent = workspace
	city.Parent = workspace
	weather.Parent = workspace
	return map, facility, city, weather
end

local function ensureMaterials(list: any)
	for _, m in list or {} do
		local variant = MaterialService:FindFirstChild(m.name)
		if not (variant and variant:IsA("MaterialVariant")) then
			variant = Instance.new("MaterialVariant")
			variant.Name = m.name
		end
		local v = variant :: MaterialVariant
		v.BaseMaterial = materialOf(m.base)
		v.ColorMap = m.id
		v.StudsPerTile = m.studs
		v.MaterialPattern = if m.pattern == "Organic" then Enum.MaterialPattern.Organic else Enum.MaterialPattern.Regular
		v.Parent = MaterialService
	end
end

local function effect(className: string, name: string): Instance
	local e = Lighting:FindFirstChild(name)
	if not (e and e.ClassName == className) then
		if e then
			e:Destroy()
		end
		e = Instance.new(className)
		e.Name = name
		e.Parent = Lighting
	end
	return e :: Instance
end

local function setupLighting(l: any)
	if not l then
		return
	end
	Lighting.ClockTime = l.clock or 0
	Lighting.Brightness = l.brightness or 0
	Lighting.Ambient = rgb(l.ambient)
	Lighting.OutdoorAmbient = rgb(l.outdoor or { 8, 8, 10 })
	Lighting.EnvironmentDiffuseScale = l.diffuse
	Lighting.EnvironmentSpecularScale = l.specular
	Lighting.GlobalShadows = true
	Lighting.ExposureCompensation = l.exposure or 0
	Lighting.FogEnd = 100000
	pcall(function()
		(Lighting :: any).Technology = Enum.Technology.Future
	end)
	if l.atmosphere then
		local a = effect("Atmosphere", "Atmosphere") :: Atmosphere
		a.Density = l.atmosphere.density
		a.Offset = l.atmosphere.offset
		a.Color = rgb(l.atmosphere.color)
		a.Decay = rgb(l.atmosphere.decay)
		a.Glare = l.atmosphere.glare
		a.Haze = l.atmosphere.haze
	end
	if l.bloom then
		local b = effect("BloomEffect", "Bloom") :: BloomEffect
		b.Intensity = l.bloom.intensity
		b.Size = l.bloom.size
		b.Threshold = l.bloom.threshold
	end
	if l.grade then
		local c = effect("ColorCorrectionEffect", "Grade") :: ColorCorrectionEffect
		c.Brightness = l.grade.brightness
		c.Contrast = l.grade.contrast
		c.Saturation = l.grade.saturation
		c.TintColor = rgb(l.grade.tint)
	end
	if l.sky then
		local sky = effect("Sky", "Sky") :: Sky
		sky.StarCount = l.sky.stars or 0
		sky.CelestialBodiesShown = false
	end
end

-- Rain past a window: streaks falling through the slab's volume.
local function makeRain(rec: any, parent: Instance)
	local p = Instance.new("Part")
	p.Name = "Rain"
	p.Size = Vector3.new(rec.s[1], rec.s[2], rec.s[3])
	p.CFrame = CFrame.new(rec.c[1], rec.c[2], rec.c[3])
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Transparency = 1
	p.CastShadow = false
	local e = Instance.new("ParticleEmitter")
	e.Name = "Rain"
	e.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	e.EmissionDirection = Enum.NormalId.Bottom
	e.Orientation = Enum.ParticleOrientation.VelocityParallel
	e.Color = ColorSequence.new(Color3.fromRGB(190, 200, 214))
	e.LightEmission = 0.25
	e.LightInfluence = 0.6
	e.Transparency = NumberSequence.new(0.55)
	e.Size = NumberSequence.new(0.12)
	e.Squash = NumberSequence.new(2.6)
	e.Speed = NumberRange.new(75, 90)
	e.Lifetime = NumberRange.new(rec.fall / 85, rec.fall / 80)
	e.Rate = rec.rate
	e.SpreadAngle = Vector2.new(3, 3)
	e.Acceleration = Vector3.new(3, -30, 1)
	e.Parent = p
	p.Parent = parent
end

-- City glow: a cool spotlight outside a window, aimed in and down. Ambience flashes these for lightning.
local function makeGlow(rec: any, parent: Instance)
	local p = Instance.new("Part")
	p.Name = "CityGlow"
	p.Size = Vector3.new(1, 1, 1)
	p.CFrame = CFrame.lookAt(Vector3.new(rec.p[1], rec.p[2], rec.p[3]), Vector3.new(rec.look[1], rec.look[2], rec.look[3]))
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Transparency = 1
	p.CastShadow = false
	local s = Instance.new("SpotLight")
	s.Face = Enum.NormalId.Front
	s.Color = rgb(rec.c)
	s.Brightness = rec.b
	s.Range = rec.range
	s.Angle = rec.angle
	s.Shadows = rec.shadows == true
	s.Parent = p
	p:SetAttribute("BaseBrightness", rec.b)
	CollectionService:AddTag(p, "CityGlow")
	p.Parent = parent
end

function BuildMap.build(): string
	local started = os.clock()
	local layout = loadLayout()
	local kit = kitIndex()
	local recording = nil
	pcall(function()
		recording = ChangeHistoryService:TryBeginRecording("Build Axiom Tower")
	end)
	ensureMaterials(layout.materials)
	local map, facility, city, weather = makeRoots()
	local roots = { Map = map, Facility = facility, City = city, Weather = weather }
	local getFolder = folderMaker(roots)

	-- Prefab templates.
	local prefabs: { [string]: Model } = {}
	local n = 0
	for name, def in layout.prefabs do
		prefabs[name] = buildPrefab(name, def)
		n += 1
		if n % 40 == 0 then
			task.wait()
		end
	end
	status(`{n} prefabs ready`)

	-- Rooms, their light folders and emergency-light folders.
	local game_ = layout.game
	for _, r in game_.rooms do
		local bounds = Instance.new("Part")
		bounds.Name = r.id
		bounds.Size = Vector3.new(r.s[1], r.s[2], r.s[3])
		bounds.CFrame = CFrame.new(r.c[1], r.c[2], r.c[3])
		bounds.Anchored = true
		bounds.CanCollide = false
		bounds.CanTouch = false
		bounds.CanQuery = false
		bounds.Transparency = 1
		bounds.Color = Color3.fromRGB(35, 35, 38)
		bounds:SetAttribute("DisplayName", r.name)
		bounds:SetAttribute("Wing", r.wing)
		bounds.Parent = getFolder("Facility/Rooms")
		local lights = getFolder("Facility/Lights/" .. r.id)
		lights:SetAttribute("TargetKind", "Blackout")
		lights:SetAttribute("TargetId", r.id)
		if r.emergency then
			getFolder("Facility/EmergencyLights/" .. r.id)
		end
	end
	status("rooms done")

	-- Structure, finishes and plain parts, in chunks.
	n = 0
	for _, rec in layout.boxes do
		makeBox(rec).Parent = getFolder(rec.f)
		n += 1
		if n % 400 == 0 then
			task.wait()
		end
	end
	status(`structure done: {#layout.boxes} boxes`)

	-- Pieces.
	for i, rec in layout.pieces do
		placePiece(rec, prefabs, kit, getFolder)
		if i % CHUNK == 0 then
			status(`pieces {i}/{#layout.pieces}`)
			task.wait()
		end
	end
	status("pieces done")

	-- Contract objects that aren't plain pieces.
	if game_.platform then
		local p = game_.platform
		local platform = Instance.new("Part")
		platform.Name = "Platform"
		platform.Size = Vector3.new(p.s[1], p.s[2], p.s[3])
		platform.CFrame = CFrame.new(p.c[1], p.c[2], p.c[3])
		platform.Anchored = true
		platform.CanCollide = false
		platform.CanTouch = false
		platform.CanQuery = false
		platform.Transparency = 1
		platform.Parent = getFolder("Facility/Core")
	end
	if game_.spawn then
		local s = game_.spawn
		local spawn = Instance.new("SpawnLocation")
		spawn.Name = "MercSpawn"
		spawn.Size = Vector3.new(s.s[1], 0.2, s.s[2])
		spawn.CFrame = CFrame.new(s.c[1], s.c[2], s.c[3]) * CFrame.Angles(0, math.rad(s.yaw or 0), 0)
		spawn.Anchored = true
		spawn.CanCollide = false
		spawn.CanQuery = false
		spawn.CanTouch = true
		spawn.Neutral = true
		spawn.Duration = 0
		spawn.Transparency = 1
		local decal = spawn:FindFirstChildOfClass("Decal")
		if decal then
			decal:Destroy()
		end
		spawn.Parent = getFolder("Facility/Spawns")
	end

	-- The city and the weather.
	n = 0
	for _, rec in layout.city or {} do
		makeBox(rec).Parent = city
		n += 1
		if n % 300 == 0 then
			task.wait()
		end
	end
	for _, rec in (layout.weather and layout.weather.rain) or {} do
		makeRain(rec, weather)
	end
	for _, rec in (layout.weather and layout.weather.glow) or {} do
		makeGlow(rec, weather)
	end
	status(`city done: {n} parts`)
	setupLighting(layout.lighting)

	if recording then
		ChangeHistoryService:FinishRecording(recording, Enum.FinishRecordingOperation.Commit)
	end
	local parts = 0
	for _, root in { map, facility } do
		for _, d in root:GetDescendants() do
			if d:IsA("BasePart") then
				parts += 1
			end
		end
	end
	local text = string.format("built Axiom Tower: %d parts (+%d city), %d pieces in %.1f s", parts, n, #layout.pieces, os.clock() - started)
	status(text)
	return text
end

-- Builds in a background thread so the command bar returns at once; watch the Output.
function BuildMap.run(): string
	status("starting")
	task.spawn(function()
		local ok, result = pcall(BuildMap.build)
		if not ok then
			status("FAILED: " .. tostring(result))
		end
	end)
	return "building in the background; see DevTools.BuildMapStatus"
end

return BuildMap
