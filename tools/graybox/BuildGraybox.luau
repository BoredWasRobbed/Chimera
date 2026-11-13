-- Builds the graybox of Axiom Data Vault: the Core plus three wings (Server Farms, Maintenance Tunnels,
-- Office Wing) and the Insertion lobby, with 14 security cameras, 8 shell docks, 11 lockable doors,
-- 3 placeholder terminals, 5 charging stations and 10 Overload traps, laid out to match
-- src/shared/FacilityMap.
--
-- A one-time generator, not game code: Rojo syncs it to ServerStorage.DevTools and nothing requires it
-- at runtime. Running it REPLACES Workspace.Map and Workspace.Facility, so hand edits made in Studio
-- since the last build are lost. Run it in Edit mode from the command bar:
--   require(game.ServerStorage.DevTools.BuildGraybox)()
local ChangeHistoryService = game:GetService("ChangeHistoryService")
local Lighting = game:GetService("Lighting")

local T = 2 -- wall thickness

local C = {
	floor = Color3.fromRGB(58, 60, 64),
	wall = Color3.fromRGB(88, 92, 98),
	ceiling = Color3.fromRGB(38, 40, 44),
	trim = Color3.fromRGB(30, 32, 36),
	metal = Color3.fromRGB(70, 74, 80),
	dark = Color3.fromRGB(26, 28, 32),
	blue = Color3.fromRGB(70, 150, 255),
	amber = Color3.fromRGB(255, 150, 60),
	cyan = Color3.fromRGB(120, 220, 255),
	off = Color3.fromRGB(35, 35, 38),
	coolant = Color3.fromRGB(150, 200, 220),
	wood = Color3.fromRGB(96, 80, 64),
}

local LIGHT = {
	CORE = Color3.fromRGB(170, 205, 255),
	INSERTION = Color3.fromRGB(240, 245, 255),
	SF = Color3.fromRGB(150, 190, 255),
	MT = Color3.fromRGB(255, 185, 120),
	OW = Color3.fromRGB(235, 240, 230),
}

-- Rooms: interior rectangles (walls are centred on these edges). Light panels sit on an inner wall face.
local ROOMS = {
	{ id = "CORE", name = "The Core", x0 = -60, x1 = 60, z0 = -60, z1 = 60, h = 40, zone = "CORE", panel = { 30, 58.8, "-z" } },
	{ id = "INSERTION", name = "Insertion", x0 = -24, x1 = 24, z0 = 60, z1 = 108, h = 16, zone = "INSERTION", panel = { -22.8, 90, "+x" } },
	{ id = "SF_CORRIDOR", name = "Farm Corridor", x0 = -8, x1 = 8, z0 = -104, z1 = -60, h = 16, zone = "SF", panel = { 6.8, -90, "-x" } },
	{ id = "SF_RACKHALL", name = "Rack Hall", x0 = -56, x1 = 56, z0 = -172, z1 = -104, h = 24, zone = "SF", panel = { -54.8, -110, "+x" } },
	{ id = "SF_TERMINAL", name = "Farm Terminal Room", x0 = -32, x1 = 32, z0 = -220, z1 = -172, h = 18, zone = "SF", panel = { -30.8, -190, "+x" } },
	{ id = "SF_COLDAISLE", name = "Cold Aisle", x0 = 56, x1 = 152, z0 = -152, z1 = -120, h = 16, zone = "SF", panel = { 80, -150.8, "+z" } },
	{ id = "MT_TUNNEL", name = "Service Tunnel", x0 = 60, x1 = 120, z0 = -7, z1 = 7, h = 12, zone = "MT", panel = { 100, -5.8, "+z" } },
	{ id = "MT_PIPERUN", name = "Pipe Run", x0 = 120, x1 = 152, z0 = -120, z1 = 44, h = 14, zone = "MT", panel = { 121.2, -40, "+x" } },
	{ id = "MT_BOILER", name = "Boiler Room", x0 = 152, x1 = 212, z0 = -30, z1 = 30, h = 18, zone = "MT", panel = { 185, 28.8, "-z" } },
	{ id = "OW_LOBBY", name = "Reception", x0 = -110, x1 = -60, z0 = -22, z1 = 22, h = 16, zone = "OW", panel = { -90, 20.8, "-z" } },
	{ id = "OW_CUBICLES", name = "Cubicle Floor", x0 = -190, x1 = -110, z0 = -56, z1 = 56, h = 16, zone = "OW", panel = { -125, 54.8, "-z" } },
	{ id = "OW_OFFICE", name = "Manager's Office", x0 = -238, x1 = -190, z0 = -30, z1 = 30, h = 16, zone = "OW", panel = { -215, -28.8, "+z" } },
	{ id = "OW_CONFERENCE", name = "Conference Room", x0 = -180, x1 = -130, z0 = 56, z1 = 92, h = 14, zone = "OW", panel = { -178.8, 75, "+x" } },
}

-- Wall lines: { axis, line, from, to, height, openings }. axis "x" runs along X at z = line; "z" runs
-- along Z at x = line. Openings are { from, to, top }. Shared walls appear once.
local WALLS = {
	{ "x", -60, -60, 60, 40, { { -8, 8, 14 } } },
	{ "x", 60, -60, 60, 40, { { -12, 12, 14 } } },
	{ "z", 60, -60, 60, 40, { { -6, 6, 10 } } },
	{ "z", -60, -60, 60, 40, { { -12, 12, 14 } } },
	{ "x", 108, -24, 24, 16, {} },
	{ "z", 24, 60, 108, 16, {} },
	{ "z", -24, 60, 108, 16, {} },
	{ "z", 8, -104, -60, 16, {} },
	{ "z", -8, -104, -60, 16, {} },
	{ "x", -104, -56, 56, 24, { { -4, 4, 10 } } },
	{ "x", -172, -56, 56, 24, { { -24, -16, 10 }, { 16, 24, 10 } } },
	{ "z", 56, -172, -104, 24, { { -140, -132, 10 } } },
	{ "z", -56, -172, -104, 24, {} },
	{ "x", -220, -32, 32, 18, {} },
	{ "z", 32, -220, -172, 18, {} },
	{ "z", -32, -220, -172, 18, {} },
	{ "x", -152, 56, 152, 16, {} },
	{ "x", -120, 56, 152, 16, { { 124, 148, 12 } } },
	{ "z", 152, -152, -120, 16, {} },
	{ "x", -7, 60, 120, 12, {} },
	{ "x", 7, 60, 120, 12, {} },
	{ "z", 120, -120, 44, 14, { { -4, 4, 10 } } },
	{ "z", 152, -120, 44, 18, { { -22, -14, 10 }, { 14, 22, 10 } } },
	{ "x", 44, 120, 152, 14, {} },
	{ "x", -30, 152, 212, 18, {} },
	{ "x", 30, 152, 212, 18, {} },
	{ "z", 212, -30, 30, 18, {} },
	{ "x", -22, -110, -60, 16, {} },
	{ "x", 22, -110, -60, 16, {} },
	{ "z", -110, -56, 56, 16, { { -4, 4, 10 } } },
	{ "z", -190, -56, 56, 16, { { -22, -14, 10 }, { 14, 22, 10 } } },
	{ "x", -56, -190, -110, 16, {} },
	{ "x", 56, -190, -110, 16, { { -159, -151, 10 } } },
	{ "z", -238, -30, 30, 16, {} },
	{ "x", -30, -238, -190, 16, {} },
	{ "x", 30, -238, -190, 16, {} },
	{ "x", 92, -180, -130, 14, {} },
	{ "z", -130, 56, 92, 14, {} },
	{ "z", -180, 56, 92, 14, {} },
}

-- Lockable doors: they sit in a wall opening above and slide `slide` (+1/-1) along the wall to open.
local DOORS = {
	{ id = "D_SF_CORRIDOR", axis = "x", line = -104, a = -4, b = 4, slide = 1, rooms = { "SF_CORRIDOR", "SF_RACKHALL" }, name = "Rack Hall door" },
	{ id = "D_SF_TERM_W", axis = "x", line = -172, a = -24, b = -16, slide = -1, rooms = { "SF_RACKHALL", "SF_TERMINAL" }, name = "Terminal room west door" },
	{ id = "D_SF_TERM_E", axis = "x", line = -172, a = 16, b = 24, slide = 1, rooms = { "SF_RACKHALL", "SF_TERMINAL" }, name = "Terminal room east door" },
	{ id = "D_SF_COLD", axis = "z", line = 56, a = -140, b = -132, slide = 1, rooms = { "SF_RACKHALL", "SF_COLDAISLE" }, name = "Cold Aisle door" },
	{ id = "D_MT_TUNNEL", axis = "z", line = 120, a = -4, b = 4, slide = 1, rooms = { "MT_TUNNEL", "MT_PIPERUN" }, name = "Pipe Run door" },
	{ id = "D_MT_BOILER_N", axis = "z", line = 152, a = -22, b = -14, slide = -1, rooms = { "MT_PIPERUN", "MT_BOILER" }, name = "Boiler north door" },
	{ id = "D_MT_BOILER_S", axis = "z", line = 152, a = 14, b = 22, slide = 1, rooms = { "MT_PIPERUN", "MT_BOILER" }, name = "Boiler south door" },
	{ id = "D_OW_LOBBY", axis = "z", line = -110, a = -4, b = 4, slide = 1, rooms = { "OW_LOBBY", "OW_CUBICLES" }, name = "Cubicle Floor door" },
	{ id = "D_OW_OFFICE_N", axis = "z", line = -190, a = -22, b = -14, slide = -1, rooms = { "OW_CUBICLES", "OW_OFFICE" }, name = "Office north door" },
	{ id = "D_OW_OFFICE_S", axis = "z", line = -190, a = 14, b = 22, slide = 1, rooms = { "OW_CUBICLES", "OW_OFFICE" }, name = "Office south door" },
	{ id = "D_OW_CONF", axis = "x", line = 56, a = -159, b = -151, slide = 1, rooms = { "OW_CUBICLES", "OW_CONFERENCE" }, name = "Conference door" },
}

-- Security cameras: every room has one (the Core has two); links follow room adjacency.
local CAMERAS = {
	{ id = "CORE_NE", room = "CORE", name = "Core north-east", pos = { 56.5, 33, -56.5 }, look = { -15, 0, 15 }, links = "CORE_SW,INSERTION,SF_CORRIDOR,MT_TUNNEL,OW_LOBBY" },
	{ id = "CORE_SW", room = "CORE", name = "Core south-west", pos = { -56.5, 33, 56.5 }, look = { 15, 0, -15 }, links = "CORE_NE,INSERTION,SF_CORRIDOR,MT_TUNNEL,OW_LOBBY" },
	{ id = "INSERTION", room = "INSERTION", name = "Insertion", pos = { 21.5, 13, 105.5 }, look = { -5, 0, 70 }, links = "CORE_NE,CORE_SW" },
	{ id = "SF_CORRIDOR", room = "SF_CORRIDOR", name = "Farm Corridor", pos = { 5.5, 13.5, -62.5 }, look = { 0, 2, -100 }, links = "CORE_NE,CORE_SW,SF_RACKHALL" },
	{ id = "SF_RACKHALL", room = "SF_RACKHALL", name = "Rack Hall", pos = { 53.5, 21, -106.5 }, look = { -25, 0, -160 }, links = "SF_CORRIDOR,SF_TERMINAL,SF_COLDAISLE" },
	{ id = "SF_TERMINAL", room = "SF_TERMINAL", name = "Farm Terminal Room", pos = { 29.5, 15.5, -174.5 }, look = { -15, 0, -215 }, links = "SF_RACKHALL" },
	{ id = "SF_COLDAISLE", room = "SF_COLDAISLE", name = "Cold Aisle", pos = { 149.5, 13.5, -122.5 }, look = { 70, 0, -145 }, links = "SF_RACKHALL,MT_PIPERUN" },
	{ id = "MT_TUNNEL", room = "MT_TUNNEL", name = "Service Tunnel", pos = { 62.5, 9.5, 4.5 }, look = { 120, 2, 0 }, links = "CORE_NE,CORE_SW,MT_PIPERUN" },
	{ id = "MT_PIPERUN", room = "MT_PIPERUN", name = "Pipe Run", pos = { 149.5, 11.5, 41.5 }, look = { 130, 0, -90 }, links = "MT_TUNNEL,MT_BOILER,SF_COLDAISLE" },
	{ id = "MT_BOILER", room = "MT_BOILER", name = "Boiler Room", pos = { 209.5, 15.5, -27.5 }, look = { 165, 0, 20 }, links = "MT_PIPERUN" },
	{ id = "OW_LOBBY", room = "OW_LOBBY", name = "Reception", pos = { -62.5, 13.5, -19.5 }, look = { -105, 0, 10 }, links = "CORE_NE,CORE_SW,OW_CUBICLES" },
	{ id = "OW_CUBICLES", room = "OW_CUBICLES", name = "Cubicle Floor", pos = { -112.5, 13.5, -53.5 }, look = { -180, 0, 40 }, links = "OW_LOBBY,OW_OFFICE,OW_CONFERENCE" },
	{ id = "OW_OFFICE", room = "OW_OFFICE", name = "Manager's Office", pos = { -192.5, 13.5, 27.5 }, look = { -234, 0, -20 }, links = "OW_CUBICLES" },
	{ id = "OW_CONFERENCE", room = "OW_CONFERENCE", name = "Conference Room", pos = { -132.5, 11.5, 89.5 }, look = { -176, 0, 60 }, links = "OW_CUBICLES" },
}

-- Shell docks: 2 at the Core, 2 per wing. `face` is where the shell looks when it steps off.
local DOCKS = {
	{ id = "DOCK_CORE_NE", room = "CORE", name = "Core dock north-east", pos = { 44, -44 }, face = { 0, 0 } },
	{ id = "DOCK_CORE_SW", room = "CORE", name = "Core dock south-west", pos = { -44, 44 }, face = { 0, 0 } },
	{ id = "DOCK_SF_RACK", room = "SF_RACKHALL", name = "Rack Hall dock", pos = { 50, -164 }, face = { 30, -164 } },
	{ id = "DOCK_SF_COLD", room = "SF_COLDAISLE", name = "Cold Aisle dock", pos = { 100, -148 }, face = { 100, -130 } },
	{ id = "DOCK_MT_PIPE", room = "MT_PIPERUN", name = "Pipe Run dock", pos = { 148, -70 }, face = { 130, -70 } },
	{ id = "DOCK_MT_BOILER", room = "MT_BOILER", name = "Boiler Room dock", pos = { 207, 25 }, face = { 190, 10 } },
	{ id = "DOCK_OW_CUBE", room = "OW_CUBICLES", name = "Cubicle Floor dock", pos = { -185, -51 }, face = { -170, -40 } },
	{ id = "DOCK_OW_CONF", room = "OW_CONFERENCE", name = "Conference Room dock", pos = { -175, 87 }, face = { -160, 75 } },
}

-- Flashlight charging stations: mercs stand on the pad to recharge (5 on the full map).
local STATIONS = {
	{ id = "STATION_INSERTION", pos = { 16, 76 }, face = { 0, 76 } },
	{ id = "STATION_CORE", pos = { 50, 20 }, face = { 40, 20 } },
	{ id = "STATION_RECEPTION", pos = { -100, 14 }, face = { -90, 14 } },
	{ id = "STATION_PIPERUN", pos = { 145, 10 }, face = { 135, 10 } },
	{ id = "STATION_RACKHALL", pos = { -50, -110 }, face = { -40, -110 } },
}

-- Overload targets: steam valves and power conduits on the walls. `target` is what the Chimera aims at;
-- mercs who walk near `floor` set an armed trap off.
local TRAPS = {
	{ id = "TRAP_PIPE_N", kind = "Steam", room = "MT_PIPERUN", target = { 121.4, 6, -80 }, floor = { 126, -80 } },
	{ id = "TRAP_PIPE_S", kind = "Steam", room = "MT_PIPERUN", target = { 150.6, 6, 0 }, floor = { 146, 0 } },
	{ id = "TRAP_BOILER", kind = "Steam", room = "MT_BOILER", target = { 180, 4, -5.6 }, floor = { 180, 0 } },
	{ id = "TRAP_TUNNEL", kind = "Steam", room = "MT_TUNNEL", target = { 80, 6, 5.6 }, floor = { 80, 1 } },
	{ id = "TRAP_COLD", kind = "Steam", room = "SF_COLDAISLE", target = { 136, 6, -150.6 }, floor = { 136, -146 } },
	{ id = "TRAP_RACK_W", kind = "Conduit", room = "SF_RACKHALL", target = { -54.6, 3, -138 }, floor = { -51, -138 } },
	{ id = "TRAP_RACK_E", kind = "Conduit", room = "SF_RACKHALL", target = { 54.6, 3, -112 }, floor = { 51, -112 } },
	{ id = "TRAP_CORE", kind = "Conduit", room = "CORE", target = { -58.6, 3, -30 }, floor = { -55, -30 } },
	{ id = "TRAP_CUBE", kind = "Conduit", room = "OW_CUBICLES", target = { -150, 3, -54.6 }, floor = { -150, -51 } },
	{ id = "TRAP_LOBBY", kind = "Conduit", room = "OW_LOBBY", target = { -70, 3, 20.6 }, floor = { -70, 17 } },
}

-- Placeholder Mainframe Terminals (reboots arrive in milestone 3), one per wing.
local TERMINALS = {
	{ id = "TERM_SF", room = "SF_TERMINAL", name = "Server Farm terminal", pos = { 0, -216 }, face = { 0, -200 } },
	{ id = "TERM_MT", room = "MT_BOILER", name = "Boiler Room terminal", pos = { 208, 0 }, face = { 190, 0 } },
	{ id = "TERM_OW", room = "OW_OFFICE", name = "Manager's Office terminal", pos = { -234, 0 }, face = { -215, 0 } },
}

local function v3(t: { number }): Vector3
	return Vector3.new(t[1], t[2], t[3])
end

local function part(parent: Instance, name: string, size: Vector3, cframe: CFrame, color: Color3, material: Enum.Material?, props: { [string]: any }?): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.CFrame = cframe
	p.Color = color
	p.Material = material or Enum.Material.SmoothPlastic
	p.Anchored = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	if props then
		for key, value in props do
			(p :: any)[key] = value
		end
	end
	p.Parent = parent
	return p
end

local function folder(parent: Instance, name: string): Folder
	local f = Instance.new("Folder")
	f.Name = name
	f.Parent = parent
	return f
end

local NOT_SOLID = { CanCollide = false, CanTouch = false }
local MARKER = { CanCollide = false, CanTouch = false, CanQuery = false, Transparency = 1 }

local function wallLine(parent: Instance, def)
	local axis, line, from, to, height, openings = def[1], def[2], def[3], def[4], def[5], table.clone(def[6])
	table.sort(openings, function(a, b)
		return a[1] < b[1]
	end)
	local function solid(a: number, b: number, y0: number, y1: number)
		if b - a < 0.01 or y1 - y0 < 0.01 then
			return
		end
		local mid, length, h = (a + b) / 2, b - a, y1 - y0
		local size = if axis == "x" then Vector3.new(length, h, T) else Vector3.new(T, h, length)
		local pos = if axis == "x" then Vector3.new(mid, y0 + h / 2, line) else Vector3.new(line, y0 + h / 2, mid)
		part(parent, "Wall", size, CFrame.new(pos), C.wall, Enum.Material.Concrete)
	end
	local cursor = from - T / 2
	for _, opening in openings do
		solid(cursor, opening[1], 0, height)
		solid(opening[1], opening[2], opening[3], height)
		cursor = opening[2]
	end
	solid(cursor, to + T / 2, 0, height)
end

local function panelCFrame(room): CFrame
	local p = room.panel
	local normal = ({ ["+x"] = Vector3.xAxis, ["-x"] = -Vector3.xAxis, ["+z"] = Vector3.zAxis, ["-z"] = -Vector3.zAxis })[p[3]]
	local pos = Vector3.new(p[1], 5, p[2])
	return CFrame.lookAt(pos, pos + normal)
end

local function buildRooms(map: Folder, facility: Folder)
	local geometry = map:FindFirstChild("Geometry") :: Folder
	local lights = facility:FindFirstChild("Lights") :: Folder
	local rooms = facility:FindFirstChild("Rooms") :: Folder
	for _, r in ROOMS do
		local w, d = r.x1 - r.x0, r.z1 - r.z0
		local cx, cz = (r.x0 + r.x1) / 2, (r.z0 + r.z1) / 2
		part(geometry, `{r.id}_Floor`, Vector3.new(w, 2, d), CFrame.new(cx, -1, cz), C.floor, Enum.Material.Concrete)
		part(geometry, `{r.id}_Ceiling`, Vector3.new(w + T, 2, d + T), CFrame.new(cx, r.h + 1, cz), C.ceiling, Enum.Material.Concrete)

		local bounds = part(rooms, r.id, Vector3.new(w, r.h, d), CFrame.new(cx, r.h / 2, cz), C.off, nil, MARKER)
		bounds:SetAttribute("DisplayName", r.name)

		local roomLights = folder(lights, r.id)
		roomLights:SetAttribute("TargetKind", "Blackout")
		roomLights:SetAttribute("TargetId", r.id)
		local color = LIGHT[r.zone]
		local nx = math.max(1, math.round(w / 30))
		local nz = math.max(1, math.round(d / 30))
		for i = 1, nx do
			for j = 1, nz do
				local x = r.x0 + w * (i - 0.5) / nx
				local z = r.z0 + d * (j - 0.5) / nz
				local fixture = part(roomLights, "Fixture", Vector3.new(4, 0.3, 1.2), CFrame.new(x, r.h - 0.15, z), color, Enum.Material.Neon, { CanCollide = false, CanTouch = false, CastShadow = false })
				local light = Instance.new("SurfaceLight")
				light.Face = Enum.NormalId.Bottom
				light.Range = math.min(r.h + 12, 52)
				light.Angle = 150
				light.Brightness = 1.6
				light.Color = color
				light.Shadows = false
				light.Parent = fixture
			end
		end
		local cf = panelCFrame(r)
		local panel = part(roomLights, "Panel", Vector3.new(2, 3, 0.4), cf, C.metal, Enum.Material.Metal, NOT_SOLID)
		part(panel, "Indicator", Vector3.new(0.5, 0.5, 0.1), cf * CFrame.new(0, 0.8, -0.25), C.cyan, Enum.Material.Neon, NOT_SOLID)
	end
	for _, def in WALLS do
		wallLine(geometry, def)
	end
end

local function buildDoors(map: Folder)
	local doors = map:FindFirstChild("Doors") :: Folder
	for _, def in DOORS do
		local model = Instance.new("Model")
		model.Name = def.id
		model:SetAttribute("DoorId", def.id)
		model:SetAttribute("RoomA", def.rooms[1])
		model:SetAttribute("RoomB", def.rooms[2])
		model:SetAttribute("DisplayName", def.name)
		model:SetAttribute("TargetKind", "LockDoor")
		model:SetAttribute("TargetId", def.id)
		local mid = (def.a + def.b) / 2
		local width = def.b - def.a
		local alongX = def.axis == "x"
		local center = if alongX then Vector3.new(mid, 5, def.line) else Vector3.new(def.line, 5, mid)
		local rotation = if alongX then CFrame.identity else CFrame.Angles(0, math.pi / 2, 0)
		local closed = CFrame.new(center) * rotation
		local slide = if alongX then Vector3.new(def.slide * width, 0, 0) else Vector3.new(0, 0, def.slide * width)
		local open = closed + slide
		local panel = part(model, "Panel", Vector3.new(width, 10, 0.6), open, C.metal, Enum.Material.DiamondPlate)
		panel:SetAttribute("ClosedCFrame", closed)
		panel:SetAttribute("OpenCFrame", open)
		for index, side in { 1, -1 } do
			part(model, `LockLight{index}`, Vector3.new(1.2, 0.4, 0.3), closed * CFrame.new(0, 5.9, side * 1.15), C.off, Enum.Material.SmoothPlastic, NOT_SOLID)
		end
		model.PrimaryPart = panel
		model.Parent = doors
	end
end

local function buildCameras(facility: Folder)
	local cameras = facility:FindFirstChild("Cameras") :: Folder
	for _, def in CAMERAS do
		local pos, look = v3(def.pos), v3(def.look)
		local aim = CFrame.lookAt(pos, look)
		local model = Instance.new("Model")
		model.Name = def.id
		model:SetAttribute("CameraId", def.id)
		model:SetAttribute("Room", def.room)
		model:SetAttribute("DisplayName", def.name)
		model:SetAttribute("Links", def.links)
		part(model, "Mount", Vector3.new(0.5, 1.2, 0.5), CFrame.new(pos + Vector3.new(0, 0.9, 0)), C.trim, Enum.Material.Metal, NOT_SOLID)
		part(model, "Housing", Vector3.new(0.9, 0.9, 1.8), aim * CFrame.new(0, 0, 0.5), C.dark, Enum.Material.Metal, NOT_SOLID)
		part(model, "Lens", Vector3.new(0.6, 0.6, 0.2), aim * CFrame.new(0, 0, -0.5), C.trim, Enum.Material.Glass, NOT_SOLID)
		local rec = part(model, "RecLight", Vector3.new(0.22, 0.22, 0.22), aim * CFrame.new(0.32, 0.5, -0.3), C.off, Enum.Material.SmoothPlastic, NOT_SOLID)
		local glow = Instance.new("PointLight")
		glow.Color = Color3.fromRGB(255, 30, 30)
		glow.Range = 6
		glow.Brightness = 2
		glow.Enabled = false
		glow.Parent = rec
		model.PrimaryPart = model:FindFirstChild("Housing") :: BasePart
		model.Parent = cameras
	end
end

local function buildDocks(map: Folder)
	local docks = map:FindFirstChild("Docks") :: Folder
	for _, def in DOCKS do
		local top = Vector3.new(def.pos[1], 0.4, def.pos[2])
		local facing = CFrame.lookAt(top, Vector3.new(def.face[1], 0.4, def.face[2]))
		local model = Instance.new("Model")
		model.Name = def.id
		model:SetAttribute("DockId", def.id)
		model:SetAttribute("Room", def.room)
		model:SetAttribute("DisplayName", def.name)
		model:SetAttribute("TargetKind", "TakeShell")
		model:SetAttribute("TargetId", def.id)
		local pad = part(model, "Pad", Vector3.new(4, 0.4, 4), facing * CFrame.new(0, -0.2, 0), C.metal, Enum.Material.DiamondPlate)
		part(model, "Cradle", Vector3.new(4, 7.6, 0.6), facing * CFrame.new(0, 3.8, 1.6), C.dark, Enum.Material.Metal)
		part(model, "PrinterHead", Vector3.new(4.4, 0.6, 2.4), facing * CFrame.new(0, 7.9, 0.6), C.dark, Enum.Material.Metal)
		part(model, "Spawn", Vector3.new(1, 1, 1), facing, C.off, nil, MARKER)
		model.PrimaryPart = pad
		model.Parent = docks
	end
end

local function buildTerminals(map: Folder)
	local terminals = map:FindFirstChild("Terminals") :: Folder
	for _, def in TERMINALS do
		local base = Vector3.new(def.pos[1], 0, def.pos[2])
		local facing = CFrame.lookAt(base, Vector3.new(def.face[1], 0, def.face[2]))
		local model = Instance.new("Model")
		model.Name = def.id
		model:SetAttribute("TerminalId", def.id)
		model:SetAttribute("Room", def.room)
		model:SetAttribute("DisplayName", def.name)
		model:SetAttribute("TargetKind", "CorruptTerminal")
		model:SetAttribute("TargetId", def.id)
		model:SetAttribute("Progress", 0)
		local console = part(model, "Console", Vector3.new(5, 3.6, 2.4), facing * CFrame.new(0, 1.8, 0), C.dark, Enum.Material.Metal)
		local screen = part(model, "Screen", Vector3.new(4, 2.6, 0.3), facing * CFrame.new(0, 5, 0.4), C.cyan, Enum.Material.Glass)
		local gui = Instance.new("SurfaceGui")
		gui.Name = "Display"
		gui.Face = Enum.NormalId.Front
		gui.LightInfluence = 0
		gui.PixelsPerStud = 50
		gui.Parent = screen
		local label = Instance.new("TextLabel")
		label.Name = "Text"
		label.BackgroundColor3 = Color3.fromRGB(5, 10, 16)
		label.Size = UDim2.fromScale(1, 1)
		label.Font = Enum.Font.Code
		label.TextScaled = true
		label.TextColor3 = C.cyan
		label.Text = "MAINFRAME\nREBOOT 0%"
		label.Parent = gui
		model.PrimaryPart = console
		model.Parent = terminals
	end
end

local function buildStations(map: Folder, facility: Folder)
	local props = map:FindFirstChild("Props") :: Folder
	local stations = facility:FindFirstChild("Stations") :: Folder
	for _, def in STATIONS do
		local floor = Vector3.new(def.pos[1], 0, def.pos[2])
		local facing = CFrame.lookAt(floor, Vector3.new(def.face[1], 0, def.face[2]))
		local model = Instance.new("Model")
		model.Name = def.id
		model:SetAttribute("StationId", def.id)
		part(model, "Pad", Vector3.new(0.3, 5, 5), CFrame.new(floor + Vector3.new(0, 0.15, 0)) * CFrame.Angles(0, 0, math.pi / 2), Color3.fromRGB(255, 235, 170), Enum.Material.Neon, { Shape = Enum.PartType.Cylinder, CanCollide = false, CanTouch = false, CanQuery = false, Transparency = 0.5 })
		model.Parent = stations
		local post = part(props, "ChargingPost", Vector3.new(1, 4, 1), facing * CFrame.new(0, 2, 2.2), C.metal, Enum.Material.Metal)
		part(post, "Light", Vector3.new(0.7, 0.5, 0.1), facing * CFrame.new(0, 3.4, 1.65), Color3.fromRGB(255, 235, 170), Enum.Material.Neon, NOT_SOLID)
	end
end

local function buildTraps(facility: Folder)
	local traps = facility:FindFirstChild("Traps") :: Folder
	for _, def in TRAPS do
		local target = Vector3.new(def.target[1], def.target[2], def.target[3])
		local floor = Vector3.new(def.floor[1], 0.1, def.floor[2])
		local facing = CFrame.lookAt(target, Vector3.new(floor.X, target.Y, floor.Z))
		local model = Instance.new("Model")
		model.Name = def.id
		model:SetAttribute("TrapKind", def.kind)
		model:SetAttribute("Room", def.room)
		model:SetAttribute("TargetKind", "Overload")
		model:SetAttribute("TargetId", def.id)
		if def.kind == "Steam" then
			part(model, "Target", Vector3.new(0.4, 1.8, 1.8), facing * CFrame.Angles(0, math.pi / 2, 0), Color3.fromRGB(190, 145, 70), Enum.Material.Metal, { Shape = Enum.PartType.Cylinder, CanCollide = false, CanTouch = false })
			part(model, "Stub", Vector3.new(0.8, 0.8, 1.2), facing * CFrame.new(0, 0, 0.5), C.metal, Enum.Material.Metal, NOT_SOLID)
		else
			part(model, "Target", Vector3.new(2, 2.6, 0.6), facing, Color3.fromRGB(70, 74, 80), Enum.Material.Metal, NOT_SOLID)
			part(model, "Strip", Vector3.new(1.6, 0.2, 0.1), facing * CFrame.new(0, 0.9, -0.32), Color3.fromRGB(150, 210, 255), Enum.Material.Neon, NOT_SOLID)
		end
		part(model, "Floor", Vector3.new(1, 0.2, 1), CFrame.new(floor), C.off, nil, MARKER)
		model.Parent = traps
	end
end

local function rack(props: Folder, x0: number, x1: number, z: number)
	local length = x1 - x0
	local cf = CFrame.new((x0 + x1) / 2, 5, z)
	part(props, "Rack", Vector3.new(length, 10, 3), cf, C.dark, Enum.Material.Metal)
	for _, side in { -1, 1 } do
		part(props, "RackGlow", Vector3.new(length - 1, 0.3, 0.1), cf * CFrame.new(0, 3, side * 1.55), C.blue, Enum.Material.Neon, { CanCollide = false, CastShadow = false })
	end
end

local function cubicleCluster(props: Folder, cx: number, cz: number, openSide: number)
	-- A 12 x 12 block of four cubicles: 6-stud partitions with a gap on the side facing the main aisle.
	local h, s = 6, 6
	local function wall(size: Vector3, pos: Vector3)
		part(props, "Partition", size, CFrame.new(pos), Color3.fromRGB(110, 112, 118), Enum.Material.Fabric)
	end
	wall(Vector3.new(0.5, h, 2 * s), Vector3.new(cx - s, h / 2, cz))
	wall(Vector3.new(0.5, h, 2 * s), Vector3.new(cx + s, h / 2, cz))
	wall(Vector3.new(2 * s, h, 0.5), Vector3.new(cx, h / 2, cz - openSide * s))
	wall(Vector3.new(4, h, 0.5), Vector3.new(cx - s + 2, h / 2, cz + openSide * s))
	wall(Vector3.new(4, h, 0.5), Vector3.new(cx + s - 2, h / 2, cz + openSide * s))
	wall(Vector3.new(0.5, h, 2 * s - 2), Vector3.new(cx, h / 2, cz - openSide))
	part(props, "Desk", Vector3.new(4, 2.5, 2.5), CFrame.new(cx - 3, 1.25, cz - openSide * 4), C.wood, Enum.Material.Wood)
	part(props, "Desk", Vector3.new(4, 2.5, 2.5), CFrame.new(cx + 3, 1.25, cz - openSide * 4), C.wood, Enum.Material.Wood)
end

local function buildProps(map: Folder, facility: Folder)
	local props = map:FindFirstChild("Props") :: Folder

	-- The Core: a central server column to the ceiling and four towers.
	part(props, "CoreColumn", Vector3.new(14, 40, 14), CFrame.new(0, 20, 0), C.dark, Enum.Material.Metal)
	for _, side in { -1, 1 } do
		part(props, "CoreGlow", Vector3.new(14.2, 0.4, 0.2), CFrame.new(0, 12, side * 7.05), C.blue, Enum.Material.Neon, { CanCollide = false })
		part(props, "CoreGlow", Vector3.new(0.2, 0.4, 14.2), CFrame.new(side * 7.05, 12, 0), C.blue, Enum.Material.Neon, { CanCollide = false })
	end
	for _, at in { { 34, 0 }, { -34, 0 }, { 0, 34 }, { 0, -34 } } do
		part(props, "ServerTower", Vector3.new(6, 14, 6), CFrame.new(at[1], 7, at[2]), C.dark, Enum.Material.Metal)
	end

	-- Insertion: the lift the squad arrives in.
	part(props, "LiftDoors", Vector3.new(16, 12, 1), CFrame.new(0, 6, 106.4), C.metal, Enum.Material.DiamondPlate)
	part(props, "LiftFrame", Vector3.new(18, 1, 1.2), CFrame.new(0, 12.5, 106.4), C.amber, Enum.Material.Neon, { CanCollide = false })

	-- Server Farms: rack rows that make a maze, coolant cabinets in the Cold Aisle.
	rack(props, -48, -10, -118)
	rack(props, 10, 48, -118)
	rack(props, -40, -6, -132)
	rack(props, 6, 40, -132)
	rack(props, -48, -24, -146)
	rack(props, -12, 12, -146)
	rack(props, 24, 48, -146)
	rack(props, -48, -30, -160)
	rack(props, -10, 10, -160)
	rack(props, 30, 44, -160)
	for x = 64, 112, 12 do
		part(props, "CoolantCabinet", Vector3.new(6, 8, 3), CFrame.new(x, 4, -122.6), C.coolant, Enum.Material.Metal)
	end
	part(props, "CableTray", Vector3.new(14, 0.6, 40), CFrame.new(0, 13, -82), C.trim, Enum.Material.Metal, { CanCollide = false })

	-- Maintenance Tunnels: overhead pipes, crates, two boilers.
	for _, pipe in { { 122.6, 10.5, 1.2 }, { 149.4, 11.2, 1.6 } } do
		part(props, "Pipe", Vector3.new(164, pipe[3] * 2, pipe[3] * 2), CFrame.new(pipe[1], pipe[2], -38) * CFrame.Angles(0, math.pi / 2, 0), C.metal, Enum.Material.Metal, { Shape = Enum.PartType.Cylinder, CanCollide = false })
	end
	part(props, "Pipe", Vector3.new(60, 1.6, 1.6), CFrame.new(90, 10.4, 5.6), C.metal, Enum.Material.Metal, { Shape = Enum.PartType.Cylinder, CanCollide = false })
	for _, crate in { { 124.5, -100 }, { 147.5, -45 }, { 124.5, 10 }, { 147.5, 30 } } do
		part(props, "Crate", Vector3.new(4, 4, 4), CFrame.new(crate[1], 2, crate[2]), C.wood, Enum.Material.WoodPlanks)
	end
	for _, z in { -11, 11 } do
		part(props, "Boiler", Vector3.new(14, 10, 10), CFrame.new(180, 7, z) * CFrame.Angles(0, 0, math.pi / 2), C.metal, Enum.Material.CorrodedMetal, { Shape = Enum.PartType.Cylinder })
	end

	-- Office Wing: reception desk, cubicle clusters, the manager's desk, a conference table.
	part(props, "ReceptionDesk", Vector3.new(4, 3.5, 12), CFrame.new(-80, 1.75, -14), C.wood, Enum.Material.Wood)
	cubicleCluster(props, -130, -38, 1)
	cubicleCluster(props, -170, -38, 1)
	cubicleCluster(props, -130, 38, -1)
	cubicleCluster(props, -170, 38, -1)
	part(props, "ManagerDesk", Vector3.new(8, 3, 4), CFrame.new(-214, 1.5, 14), C.wood, Enum.Material.Wood)
	part(props, "ConferenceTable", Vector3.new(24, 3, 8), CFrame.new(-155, 1.5, 74), C.wood, Enum.Material.Wood)

	-- Merc spawn in the Insertion lobby.
	local spawns = facility:FindFirstChild("Spawns") :: Folder
	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "MercSpawn"
	spawn.Size = Vector3.new(10, 0.2, 10)
	spawn.CFrame = CFrame.new(0, 0.1, 94)
	spawn.Anchored = true
	spawn.CanCollide = false
	spawn.CanQuery = false
	spawn.Neutral = true
	spawn.Duration = 0
	spawn.Color = C.cyan
	spawn.Material = Enum.Material.SmoothPlastic
	spawn.Transparency = 0.8
	spawn.TopSurface = Enum.SurfaceType.Smooth
	spawn.Parent = spawns
	local decal = spawn:FindFirstChildOfClass("Decal")
	if decal then
		decal:Destroy()
	end
end

local function setupLighting()
	Lighting.ClockTime = 0
	Lighting.Brightness = 0
	Lighting.Ambient = Color3.fromRGB(28, 30, 36)
	Lighting.OutdoorAmbient = Color3.fromRGB(10, 10, 14)
	Lighting.EnvironmentDiffuseScale = 0.15
	Lighting.EnvironmentSpecularScale = 0.25
	Lighting.GlobalShadows = true
	for _, name in { "SunRays", "Atmosphere", "DepthOfField" } do
		local effect = Lighting:FindFirstChild(name)
		if effect then
			effect:Destroy()
		end
	end
	pcall(function()
		(Lighting :: any).Technology = Enum.Technology.Future
	end)
end

return function()
	local recording = nil
	pcall(function()
		recording = ChangeHistoryService:TryBeginRecording("Build Chimera graybox")
	end)

	for _, name in { "Map", "Facility", "Baseplate", "SpawnLocation" } do
		local old = workspace:FindFirstChild(name)
		if old then
			old:Destroy()
		end
	end

	local map = Instance.new("Folder")
	map.Name = "Map"
	for _, name in { "Geometry", "Props", "Doors", "Docks", "Terminals" } do
		folder(map, name)
	end
	local facility = Instance.new("Folder")
	facility.Name = "Facility"
	for _, name in { "Cameras", "Lights", "Rooms", "Spawns", "Stations", "Traps" } do
		folder(facility, name)
	end

	buildRooms(map, facility)
	task.wait()
	buildDoors(map)
	buildCameras(facility)
	buildDocks(map)
	buildTerminals(map)
	task.wait()
	buildProps(map, facility)
	buildStations(map, facility)
	buildTraps(facility)
	map.Parent = workspace
	task.wait()
	facility.Parent = workspace
	setupLighting()

	if recording then
		ChangeHistoryService:FinishRecording(recording, Enum.FinishRecordingOperation.Commit)
	end
	local count = 0
	for _, root in { map, facility } do
		for _, d in root:GetDescendants() do
			if d:IsA("BasePart") then
				count += 1
			end
		end
	end
	return `graybox built: {count} parts`
end
