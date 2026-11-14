-- Builds Axiom Data Vault, the full map, from the map kit. The layout (every structural block and every kit
-- piece's place) comes from ServerStorage.DevTools.MapLayout, which tools/map/design_map.py generates;
-- edit the layout there, not here. This builds it into the place and follows the map contract in
-- src/shared/FacilityMap.luau.
--
-- A one-time generator, not game code: Rojo syncs it to ServerStorage.DevTools and nothing requires it at
-- runtime. Running it REPLACES Workspace.Map and Workspace.Facility (and removes Workspace.MapKitGallery),
-- so hand edits made in Studio since the last build are lost. It needs ServerStorage.MapKit (rebuild it
-- first if the kit changed). Run it in Edit mode from the command bar (the clone skips the module cache):
--   require(game.ServerStorage.DevTools.BuildMap:Clone()).run()     builds in the background; Studio stays
--       responsive. Progress shows in the Output and in DevTools' BuildMapStatus attribute.
--   require(game.ServerStorage.DevTools.BuildMap:Clone()).build()   builds and returns when done.
local ChangeHistoryService = game:GetService("ChangeHistoryService")
local CollectionService = game:GetService("CollectionService")
local HttpService = game:GetService("HttpService")
local Lighting = game:GetService("Lighting")
local ServerStorage = game:GetService("ServerStorage")

local BuildMap = {}

local CHUNK = 120 -- pieces per frame

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

-- Folders by path ("Map/Geometry/CORE"), made on demand under the two roots.
local function folderMaker(roots: { [string]: Instance })
	local cache: { [string]: Instance } = {}
	local function get(path: string): Instance
		local found = cache[path]
		if found then
			return found
		end
		local parentPath, name = string.match(path, "^(.*)/([^/]+)$")
		local parent = if parentPath then get(parentPath) else roots[path]
		if not parentPath then
			cache[path] = parent
			return parent
		end
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

local MATERIALS = {
	Concrete = Enum.Material.Concrete,
	Metal = Enum.Material.Metal,
	SmoothPlastic = Enum.Material.SmoothPlastic,
	DiamondPlate = Enum.Material.DiamondPlate,
	Rubber = Enum.Material.Rubber,
	Neon = Enum.Material.Neon,
	CorrodedMetal = Enum.Material.CorrodedMetal,
	Glass = Enum.Material.Glass,
	Fabric = Enum.Material.Fabric,
	Leather = Enum.Material.Leather,
	Cardboard = Enum.Material.Cardboard,
}

local function cframeOf(p: { number }, r: any): CFrame
	local cf = CFrame.new(p[1], p[2], p[3])
	if type(r) == "number" then
		return cf * CFrame.Angles(0, math.rad(r), 0)
	elseif type(r) == "table" then
		return cf * CFrame.Angles(math.rad(r[1]), math.rad(r[2]), math.rad(r[3]))
	end
	return cf
end

-- A plain part from the layout: n name, f folder, p centre, s size, r turn, m material, c colour,
-- v material variant, and flags: nc (no collide), nq (no query), t transparency, refl, ns (no shadow),
-- shape ("cyl" or "ball"), tag (CollectionService), a (attributes).
local function makeBox(rec: any): BasePart
	local part: BasePart
	if rec.wedge then
		part = Instance.new("WedgePart")
	else
		local p = Instance.new("Part")
		if rec.shape == "cyl" then
			p.Shape = Enum.PartType.Cylinder
		elseif rec.shape == "ball" then
			p.Shape = Enum.PartType.Ball
		end
		part = p
	end
	part.Name = rec.n
	part.Size = Vector3.new(rec.s[1], rec.s[2], rec.s[3])
	part.CFrame = cframeOf(rec.p, rec.r)
	part.Material = MATERIALS[rec.m] or Enum.Material.SmoothPlastic
	part.Color = Color3.fromRGB(rec.c[1], rec.c[2], rec.c[3])
	if rec.v then
		part.MaterialVariant = rec.v
	end
	part.Anchored = true
	part.CanTouch = false
	part.CanCollide = not rec.nc
	part.CanQuery = not rec.nq
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
	if rec.tag then
		CollectionService:AddTag(part, rec.tag)
	end
	if rec.a then
		for key, value in rec.a do
			part:SetAttribute(key, value)
		end
	end
	if rec.fx == "mist" then
		-- Cold mist rolling off the floor (the Cooling Plant).
		local e = Instance.new("ParticleEmitter")
		e.Texture = "rbxasset://textures/particles/smoke_main.dds"
		e.Color = ColorSequence.new(Color3.fromRGB(200, 228, 242))
		e.LightEmission = 0.05
		e.LightInfluence = 0.7
		e.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(0.3, 0.86),
			NumberSequenceKeypoint.new(1, 1),
		})
		e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 4), NumberSequenceKeypoint.new(1, 10) })
		e.Lifetime = NumberRange.new(7, 10)
		e.Rate = 2.5
		e.Speed = NumberRange.new(0.3, 0.8)
		e.SpreadAngle = Vector2.new(180, 15)
		e.Acceleration = Vector3.new(0, 0.12, 0)
		e.Rotation = NumberRange.new(0, 360)
		e.RotSpeed = NumberRange.new(-8, 8)
		e.Parent = part
	end
	if rec.light then
		local l = rec.light
		local light: Light = if l.kind == "spot" then Instance.new("SpotLight") elseif l.kind == "surface" then Instance.new("SurfaceLight") else Instance.new("PointLight")
		light.Color = Color3.fromRGB(l.c[1], l.c[2], l.c[3])
		light.Range = l.range
		light.Brightness = l.brightness
		light.Shadows = l.shadows == true
		if l.face and (light:IsA("SpotLight") or light:IsA("SurfaceLight")) then
			(light :: any).Face = Enum.NormalId[l.face]
		end
		if l.angle and (light:IsA("SpotLight") or light:IsA("SurfaceLight")) then
			(light :: any).Angle = l.angle
		end
		light.Enabled = l.off ~= true
		light.Parent = part
	end
	return part
end

-- A corner post: a steel column filling a room's corner, with a striped corner guard at its foot.
local function makePost(rec: { any }, parent: Instance)
	local x0, x1, z0, z1, y0, h, corner = rec[1], rec[2], rec[3], rec[4], rec[5], rec[6], rec[7]
	local post = Instance.new("Part")
	post.Name = "CornerPost"
	post.Size = Vector3.new(x1 - x0, h, z1 - z0)
	post.CFrame = CFrame.new((x0 + x1) / 2, y0 + h / 2, (z0 + z1) / 2)
	post.Material = Enum.Material.Metal
	post.MaterialVariant = "AxiomSteel"
	post.Color = Color3.fromRGB(28, 30, 34)
	post.Anchored = true
	post.CanTouch = false
	post.Parent = parent
	-- The room side of the post: the corner guard wraps its outer edge.
	local ex = if string.find(corner, "W") then x1 else x0
	local ez = if string.find(corner, "N") then z1 else z0
	local sx = if string.find(corner, "W") then 1 else -1
	local sz = if string.find(corner, "N") then 1 else -1
	for i = 1, 2 do
		local guard = Instance.new("Part")
		guard.Name = "CornerGuard"
		guard.Anchored = true
		guard.CanCollide = false
		guard.CanTouch = false
		guard.Material = Enum.Material.SmoothPlastic
		guard.MaterialVariant = "AxiomHazard"
		guard.Color = Color3.fromRGB(190, 145, 30)
		if i == 1 then
			guard.Size = Vector3.new(0.08, 4, 0.7)
			guard.CFrame = CFrame.new(ex + sx * 0.04, y0 + 2.2, ez - sz * 0.35)
		else
			guard.Size = Vector3.new(0.7, 4, 0.08)
			guard.CFrame = CFrame.new(ex - sx * 0.35, y0 + 2.2, ez + sz * 0.04)
		end
		guard.Parent = parent
	end
end

-- Turns a security camera's head (about its joint) so the Lens looks at `target`.
local function aimCamera(model: Model, target: Vector3)
	local joint = model:FindFirstChild("Joint") :: BasePart?
	local lens = model:FindFirstChild("Lens") :: BasePart?
	if not (joint and lens) then
		return
	end
	local function angles(look: Vector3): (number, number)
		return math.atan2(-look.X, -look.Z), math.asin(math.clamp(look.Y, -1, 1))
	end
	local yaw0, pitch0 = angles(lens.CFrame.LookVector)
	local yaw1, pitch1 = angles((target - lens.Position).Unit)
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
			if l.c then
				d.Color = Color3.fromRGB(l.c[1], l.c[2], l.c[3])
			end
			if l.range then
				d.Range = l.range
			end
			if l.brightness then
				d.Brightness = l.brightness
			end
		elseif d:IsA("BasePart") and d.Name == "Fixture" and l.c then
			-- Tint the glowing part toward the light's colour.
			local c = Color3.fromRGB(l.c[1], l.c[2], l.c[3])
			d.Color = d.Color:Lerp(c, 0.6)
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

-- Places one kit piece and applies its options (see design_map.py's piece()).
local function placePiece(rec: { any }, kit: { [string]: Model }, getFolder: (string) -> Instance, roots: { [string]: Instance }): Instance?
	local name, folderPath, x, y, z, yaw, opts = rec[1], rec[2], rec[3], rec[4], rec[5], rec[6], rec[7]
	local source = kit[name]
	if not source then
		warn(`[BuildMap] no kit piece {name}`)
		return nil
	end
	local model = source:Clone()
	local cf = CFrame.new(x, y, z) * CFrame.Angles(0, math.rad(yaw), 0)
	if opts and opts.look then
		local at = Vector3.new(x, y, z)
		cf = CFrame.lookAt(at, Vector3.new(opts.look[1], opts.look[2], opts.look[3]))
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
					d.Color = Color3.fromRGB(34, 34, 36)
				end
			end
		end
		if opts.aim then
			aimCamera(model, Vector3.new(opts.aim[1], opts.aim[2], opts.aim[3]))
		end
		if opts.strip then
			-- Parts to leave out (a sign's stripe, a desk's cables...).
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

local function makeRoots(): (Folder, Folder)
	for _, name in { "Map", "Facility", "MapKitGallery" } do
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
	map.Parent = workspace
	facility.Parent = workspace
	return map, facility
end

local function setupLighting(l: any)
	if not l then
		return
	end
	Lighting.ClockTime = 0
	Lighting.Brightness = 0
	Lighting.Ambient = Color3.fromRGB(l.ambient[1], l.ambient[2], l.ambient[3])
	Lighting.OutdoorAmbient = Color3.fromRGB(8, 8, 10)
	Lighting.EnvironmentDiffuseScale = l.diffuse
	Lighting.EnvironmentSpecularScale = l.specular
	Lighting.GlobalShadows = true
	Lighting.ExposureCompensation = l.exposure or 0
	pcall(function()
		(Lighting :: any).Technology = Enum.Technology.Future
	end)
end

function BuildMap.build(): string
	local started = os.clock()
	local layout = loadLayout()
	local kit = kitIndex()
	local recording = nil
	pcall(function()
		recording = ChangeHistoryService:TryBeginRecording("Build Axiom Data Vault")
	end)
	local map, facility = makeRoots()
	local roots = { Map = map, Facility = facility }
	local getFolder = folderMaker(roots)

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

	-- Structure and plain parts, in chunks.
	local n = 0
	for _, rec in layout.boxes do
		makeBox(rec).Parent = getFolder(rec.f)
		n += 1
		if n % 400 == 0 then
			task.wait()
		end
	end
	local postFolder = getFolder("Map/Geometry/Structure")
	for i, rec in layout.posts do
		makePost(rec, getFolder("Map/Geometry/" .. rec[8]))
		if i % 200 == 0 then
			task.wait()
		end
	end
	status(`structure done: {#layout.boxes} boxes, {#layout.posts} posts`)

	-- Kit pieces.
	for i, rec in layout.pieces do
		placePiece(rec, kit, getFolder, roots)
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
	local text = string.format("built Axiom Data Vault: %d parts, %d pieces in %.1f s", parts, #layout.pieces, os.clock() - started)
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
