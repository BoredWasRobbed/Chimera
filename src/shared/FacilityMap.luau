-- Reads the facility out of the place. The map is built in Studio (not in git), so this module is the
-- contract between the place and the code:
--
-- Workspace.Map            everything that blocks sight and movement (shells collide with it)
--   Geometry               floors, walls, ceilings
--   Props                  racks, cubicles, pipes, crates
--   Doors/<DoorId>         Model: DoorId, RoomA, RoomB, TargetKind="LockDoor", TargetId
--     Panel                the sliding door; CFrame attributes ClosedCFrame and OpenCFrame
--     LockLight*           lights that show the lock
--   Docks/<DockId>         Model: DockId, Room, DisplayName, TargetKind="TakeShell", TargetId
--     Spawn                invisible marker; its CFrame is the shell's feet and facing
--   Terminals/<Id>         Model: TerminalId, Room, DisplayName, TargetKind="CorruptTerminal", TargetId
--     Screen               part with a SurfaceGui "Display" holding a TextLabel "Text"
-- Workspace.Facility       things that don't block sight
--   Cameras/<CameraId>     Model: CameraId, Room, DisplayName, Links ("ID,ID"), optional PanLimit/TiltLimit
--     Lens                 its LookVector is the camera's resting direction
--     RecLight             lit red while the Chimera watches through this camera
--   Lights/<RoomId>        Folder: TargetKind="Blackout", TargetId=<RoomId>; light fixtures and a Panel part
--   Rooms/<RoomId>         invisible box part covering the room, attributes DisplayName and Wing
--                          ("CORE", "INSERTION", or a wing such as "SF"; a terminal's wing is its room's)
--   Stations/<Id>          Model: a flashlight charging station; its Pad part is where mercs stand
--   Traps/<Id>             Model: TrapKind ("Steam" or "Conduit"), Room, TargetKind="Overload", TargetId
--     Target               what the Chimera aims at to arm it (a valve or junction box)
--     Floor                invisible marker on the floor; mercs near it set the trap off
--   Core/Platform          invisible box over the Core platform the finales are held on
--   Floodlights/*          parts with a light, off until the Purge finale floodlights the Core
--   EmergencyLights/<RoomId>  parts with a light, off until a terminal in the room's wing is rebooted
local Config = require(script.Parent.Config)
local CameraMath = require(script.Parent.CameraMath)

local FacilityMap = {}

export type CameraInfo = {
	id: string,
	model: Model,
	lens: BasePart,
	recLight: BasePart?,
	room: string,
	links: { string },
	displayName: string,
	panLimit: number,
	tiltLimit: number,
	baseYaw: number,
	basePitch: number,
	origin: Vector3,
}

export type DockInfo = {
	id: string,
	model: Model,
	room: string,
	displayName: string,
	spawn: CFrame,
}

export type DoorInfo = {
	id: string,
	model: Model,
	panel: BasePart,
	closed: CFrame,
	open: CFrame,
	lockLights: { BasePart },
	rooms: { string },
}

export type TerminalInfo = {
	id: string,
	model: Model,
	room: string,
	displayName: string,
	screen: BasePart?,
}

export type RoomInfo = {
	id: string,
	displayName: string,
	wing: string,
	bounds: BasePart,
	fixtures: { BasePart },
	panel: BasePart?,
}

local function splitList(value: any): { string }
	local out = {}
	if type(value) == "string" then
		for item in string.gmatch(value, "[^,%s]+") do
			table.insert(out, item)
		end
	end
	return out
end

function FacilityMap.folders(): (Folder, Folder)
	return workspace:WaitForChild("Map") :: Folder, workspace:WaitForChild("Facility") :: Folder
end

function FacilityMap.cameras(): { [string]: CameraInfo }
	local _, facility = FacilityMap.folders()
	local out = {}
	for _, model in (facility:WaitForChild("Cameras")):GetChildren() do
		local id = model:GetAttribute("CameraId")
		local lens = model:FindFirstChild("Lens")
		if type(id) == "string" and lens and lens:IsA("BasePart") then
			local yaw, pitch = CameraMath.anglesFromLook(lens.CFrame.LookVector)
			out[id] = {
				id = id,
				model = model,
				lens = lens,
				recLight = model:FindFirstChild("RecLight") :: BasePart?,
				room = model:GetAttribute("Room") or "",
				links = splitList(model:GetAttribute("Links")),
				displayName = model:GetAttribute("DisplayName") or id,
				panLimit = model:GetAttribute("PanLimit") or Config.Camera.PanLimit,
				tiltLimit = model:GetAttribute("TiltLimit") or Config.Camera.TiltLimit,
				baseYaw = yaw,
				basePitch = pitch,
				origin = lens.Position + lens.CFrame.LookVector * (lens.Size.Z / 2 + 0.2),
			}
		end
	end
	return out
end

function FacilityMap.docks(): { [string]: DockInfo }
	local map = FacilityMap.folders()
	local out = {}
	for _, model in (map:WaitForChild("Docks")):GetChildren() do
		local id = model:GetAttribute("DockId")
		local spawn = model:FindFirstChild("Spawn")
		if type(id) == "string" and spawn and spawn:IsA("BasePart") then
			out[id] = {
				id = id,
				model = model,
				room = model:GetAttribute("Room") or "",
				displayName = model:GetAttribute("DisplayName") or id,
				spawn = spawn.CFrame,
			}
		end
	end
	return out
end

function FacilityMap.doors(): { [string]: DoorInfo }
	local map = FacilityMap.folders()
	local out = {}
	for _, model in (map:WaitForChild("Doors")):GetChildren() do
		local id = model:GetAttribute("DoorId")
		local panel = model:FindFirstChild("Panel")
		if type(id) == "string" and panel and panel:IsA("BasePart") then
			local lights = {}
			for _, child in model:GetChildren() do
				if child:IsA("BasePart") and string.sub(child.Name, 1, 9) == "LockLight" then
					table.insert(lights, child)
				end
			end
			out[id] = {
				id = id,
				model = model,
				panel = panel,
				closed = panel:GetAttribute("ClosedCFrame") or panel.CFrame,
				open = panel:GetAttribute("OpenCFrame") or panel.CFrame,
				lockLights = lights,
				rooms = { model:GetAttribute("RoomA") or "", model:GetAttribute("RoomB") or "" },
			}
		end
	end
	return out
end

function FacilityMap.terminals(): { [string]: TerminalInfo }
	local map = FacilityMap.folders()
	local out = {}
	for _, model in (map:WaitForChild("Terminals")):GetChildren() do
		local id = model:GetAttribute("TerminalId")
		if type(id) == "string" then
			out[id] = {
				id = id,
				model = model,
				room = model:GetAttribute("Room") or "",
				displayName = model:GetAttribute("DisplayName") or id,
				screen = model:FindFirstChild("Screen") :: BasePart?,
			}
		end
	end
	return out
end

function FacilityMap.rooms(): { [string]: RoomInfo }
	local _, facility = FacilityMap.folders()
	local out = {}
	local lights = facility:WaitForChild("Lights")
	for _, bounds in (facility:WaitForChild("Rooms")):GetChildren() do
		if bounds:IsA("BasePart") then
			local fixtures = {}
			local panel = nil
			local folder = lights:FindFirstChild(bounds.Name)
			if folder then
				for _, part in folder:GetChildren() do
					if part:IsA("BasePart") then
						if part.Name == "Panel" then
							panel = part
						else
							table.insert(fixtures, part)
						end
					end
				end
			end
			out[bounds.Name] = {
				id = bounds.Name,
				displayName = bounds:GetAttribute("DisplayName") or bounds.Name,
				wing = bounds:GetAttribute("Wing") or "",
				bounds = bounds,
				fixtures = fixtures,
				panel = panel,
			}
		end
	end
	return out
end

export type StationInfo = { id: string, model: Model, pad: BasePart }
export type TrapInfo = { id: string, kind: string, room: string, model: Model, target: BasePart, floor: Vector3 }

function FacilityMap.stations(): { [string]: StationInfo }
	local _, facility = FacilityMap.folders()
	local out = {}
	local folder = facility:FindFirstChild("Stations")
	for _, model in (if folder then folder:GetChildren() else {}) do
		local pad = model:FindFirstChild("Pad")
		if pad and pad:IsA("BasePart") then
			out[model.Name] = { id = model.Name, model = model, pad = pad }
		end
	end
	return out
end

function FacilityMap.traps(): { [string]: TrapInfo }
	local _, facility = FacilityMap.folders()
	local out = {}
	local folder = facility:FindFirstChild("Traps")
	for _, model in (if folder then folder:GetChildren() else {}) do
		local id = model:GetAttribute("TargetId")
		local target = model:FindFirstChild("Target")
		local floor = model:FindFirstChild("Floor")
		if type(id) == "string" and target and target:IsA("BasePart") and floor and floor:IsA("BasePart") then
			out[id] = {
				id = id,
				kind = model:GetAttribute("TrapKind") or "Steam",
				room = model:GetAttribute("Room") or "",
				model = model,
				target = target,
				floor = floor.Position,
			}
		end
	end
	return out
end

-- The Core: its room (the one whose Wing is "CORE") and the platform the finales are held on.
function FacilityMap.core(rooms: { [string]: RoomInfo }): (string?, BasePart?)
	local _, facility = FacilityMap.folders()
	local room = nil
	for id, info in rooms do
		if info.wing == "CORE" then
			room = id
			break
		end
	end
	local folder = facility:FindFirstChild("Core")
	local platform = folder and folder:FindFirstChild("Platform")
	return room, if platform and platform:IsA("BasePart") then platform else nil
end

function FacilityMap.floodlights(): { BasePart }
	local _, facility = FacilityMap.folders()
	local out = {}
	local folder = facility:FindFirstChild("Floodlights")
	for _, part in (if folder then folder:GetChildren() else {}) do
		if part:IsA("BasePart") then
			table.insert(out, part)
		end
	end
	return out
end

-- Emergency light parts by room id.
function FacilityMap.emergencyLights(): { [string]: { BasePart } }
	local _, facility = FacilityMap.folders()
	local out = {}
	local folder = facility:FindFirstChild("EmergencyLights")
	for _, roomFolder in (if folder then folder:GetChildren() else {}) do
		local parts = {}
		for _, part in roomFolder:GetChildren() do
			if part:IsA("BasePart") then
				table.insert(parts, part)
			end
		end
		out[roomFolder.Name] = parts
	end
	return out
end

-- Is a point inside a box part (any rotation)?
function FacilityMap.inBox(box: BasePart, position: Vector3): boolean
	local rel = box.CFrame:PointToObjectSpace(position)
	local half = box.Size / 2
	return math.abs(rel.X) <= half.X and math.abs(rel.Y) <= half.Y and math.abs(rel.Z) <= half.Z
end

-- The Interface target an instance belongs to: the nearest ancestor (or itself) with a TargetKind attribute.
function FacilityMap.targetOf(instance: Instance?): (string?, string?)
	local current = instance
	while current and current ~= workspace do
		local kind = current:GetAttribute("TargetKind")
		if type(kind) == "string" then
			return kind, current:GetAttribute("TargetId")
		end
		current = current.Parent
	end
	return nil, nil
end

function FacilityMap.roomAt(rooms: { [string]: RoomInfo }, position: Vector3): string?
	for id, room in rooms do
		local rel = room.bounds.CFrame:PointToObjectSpace(position)
		local half = room.bounds.Size / 2
		if math.abs(rel.X) <= half.X and math.abs(rel.Y) <= half.Y and math.abs(rel.Z) <= half.Z then
			return id
		end
	end
	return nil
end

return FacilityMap
