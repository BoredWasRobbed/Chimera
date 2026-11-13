-- The facility as the server sees it, loaded once from the place, plus a startup check that the map
-- follows the layout rules this milestone relies on.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local FacilityMap = require(ReplicatedStorage.Shared.FacilityMap)

local MapData = {}

MapData.cameras = {} :: { [string]: FacilityMap.CameraInfo }
MapData.docks = {} :: { [string]: FacilityMap.DockInfo }
MapData.doors = {} :: { [string]: FacilityMap.DoorInfo }
MapData.terminals = {} :: { [string]: FacilityMap.TerminalInfo }
MapData.rooms = {} :: { [string]: FacilityMap.RoomInfo }

function MapData.init()
	MapData.cameras = FacilityMap.cameras()
	MapData.docks = FacilityMap.docks()
	MapData.doors = FacilityMap.doors()
	MapData.terminals = FacilityMap.terminals()
	MapData.rooms = FacilityMap.rooms()
end

function MapData.roomAt(position: Vector3): string?
	return FacilityMap.roomAt(MapData.rooms, position)
end

-- Points a viewer must be able to see for each kind of Interface target.
function MapData.dockPoints(dock: FacilityMap.DockInfo): { Vector3 }
	local feet = dock.spawn
	return {
		(feet * CFrame.new(0, 4.6, 0)).Position,
		(feet * CFrame.new(0, 3, 0)).Position,
		(feet * CFrame.new(0, 1.2, 0)).Position,
	}
end

function MapData.doorPoints(door: FacilityMap.DoorInfo): { Vector3 }
	local cf = door.closed
	local half = door.panel.Size / 2
	return {
		cf.Position,
		(cf * CFrame.new(half.X * 0.6, half.Y * 0.5, 0)).Position,
		(cf * CFrame.new(-half.X * 0.6, half.Y * 0.5, 0)).Position,
		(cf * CFrame.new(0, -half.Y * 0.5, 0)).Position,
	}
end

function MapData.terminalPoints(terminal: FacilityMap.TerminalInfo): { Vector3 }
	local pivot = terminal.model:GetPivot()
	local points = { pivot.Position }
	if terminal.screen then
		table.insert(points, 1, terminal.screen.Position)
	end
	return points
end

function MapData.lightPoints(room: FacilityMap.RoomInfo): { Vector3 }
	local points = {}
	if room.panel then
		table.insert(points, room.panel.Position)
	end
	for _, fixture in room.fixtures do
		table.insert(points, fixture.Position - Vector3.new(0, fixture.Size.Y / 2 + 0.05, 0))
	end
	return points
end

-- Warns about anything that breaks the layout rules: unknown or one-way links, rooms without a camera,
-- docks no camera can see. `cameraSees` comes from Sight so this module stays free of raycasts.
function MapData.validate(cameraSees: (FacilityMap.CameraInfo, { Vector3 }, Instance?) -> boolean)
	local problems = {}
	local roomsWithCamera = {}
	local count = 0
	for id, cam in MapData.cameras do
		count += 1
		roomsWithCamera[cam.room] = true
		for _, link in cam.links do
			local other = MapData.cameras[link]
			if not other then
				table.insert(problems, `camera {id} links to unknown camera {link}`)
			elseif not table.find(other.links, id) then
				table.insert(problems, `camera link {id} -> {link} is one-way`)
			end
		end
		if #cam.links == 0 then
			table.insert(problems, `camera {id} has no links`)
		end
	end
	for id in MapData.rooms do
		if not roomsWithCamera[id] then
			table.insert(problems, `room {id} has no camera`)
		end
	end
	local dockCount = 0
	for id, dock in MapData.docks do
		dockCount += 1
		local seen = false
		for _, cam in MapData.cameras do
			if cameraSees(cam, MapData.dockPoints(dock), dock.model) then
				seen = true
				break
			end
		end
		if not seen then
			table.insert(problems, `dock {id} isn't in view of any camera`)
		end
	end
	local doorCount, terminalCount = 0, 0
	for _ in MapData.doors do
		doorCount += 1
	end
	for _ in MapData.terminals do
		terminalCount += 1
	end
	print(`[Chimera] map: {count} cameras, {dockCount} docks, {doorCount} doors, {terminalCount} terminals`)
	for _, problem in problems do
		warn(`[Chimera] map check: {problem}`)
	end
	return problems
end

return MapData
