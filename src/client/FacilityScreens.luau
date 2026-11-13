-- Drives the map kit's live pieces from the match's real state, on every client:
--   KitScreen     screens: one ScreenFeeds feed each (see src/shared/ScreenFeeds for the feeds)
--   KitLeds       server rack LEDs and console buttons: blink faster as network load rises, turn amber in
--                 Lockdown and magenta in the Upload finale
--   KitStatus     status lights (attribute StatusMode): "Room" cyan, amber in a blacked-out room, green in a
--                 secured wing, red in Lockdown or a finale; "Terminal" follows its terminal; "Power" is
--                 green, or blinking red while its room is dark
--   KitDoorLight  lights on doorframes: the nearest door's state (open, sealed, welded)
--   KitSign       signs (attribute SignMode): "Room" shows the room it hangs in; "Through" (doorframe
--                 headers) the room on the other side of the wall; "Lockdown" lights up for Lockdown and the
--                 finales
-- Everything here draws facts every client already has (ReplicatedStorage.MatchState, terminal, camera and
-- door attributes, which lights are on, merc vitals), so it sends nothing and shows nothing new. Screens in
-- a blacked-out room dim. The event log is built here from changes in those facts.
local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)
local FacilityMap = require(ReplicatedStorage.Shared.FacilityMap)
local ScreenFeeds = require(ReplicatedStorage.Shared.ScreenFeeds)

local FacilityScreens = {}

local NEAR, FAR, LED_RANGE = 60, 160, 70 -- studs: near screens animate at 8 Hz, far ones at 2 Hz
local LOG_SIZE = 30

local STATUS_COLORS = {
	normal = Color3.fromRGB(80, 200, 255),
	dark = Color3.fromRGB(255, 150, 50),
	secure = Color3.fromRGB(90, 255, 140),
	alarm = Color3.fromRGB(255, 55, 45),
	fault = Color3.fromRGB(200, 90, 255),
	busy = Color3.fromRGB(255, 205, 90),
	off = Color3.fromRGB(30, 32, 36),
}
local DOOR_COLORS = {
	open = Color3.fromRGB(90, 255, 140),
	sealed = Color3.fromRGB(255, 160, 40),
	welded = Color3.fromRGB(255, 205, 140),
}

type Screen = {
	part: BasePart,
	gui: SurfaceGui,
	feed: string,
	ctx: ScreenFeeds.Context,
	handle: ScreenFeeds.Handle?,
	brightness: number,
	nextAt: number,
}
type LedGroup = { part: BasePart, frames: { Frame }, colors: { Color3 }, mode: string }
type Lit = { part: BasePart, mode: string, room: string?, wing: string?, terminal: Model?, door: FacilityMap.DoorInfo?, key: string }

local screens: { Screen } = {}
local ledGroups: { LedGroup } = {}
local statusLights: { Lit } = {}
local doorLights: { Lit } = {}
local signs: { Lit } = {}
local seen: { [Instance]: boolean } = {}

local matchState: Configuration
local rooms: { [string]: FacilityMap.RoomInfo } = {}
local roomLights: { [string]: { Light } } = {}
local emergencyParts: { [string]: { BasePart } } = {}
local doors: { [string]: FacilityMap.DoorInfo } = {}
local terminalModels: { Model } = {}
local cameraModels: { Model } = {}

local state: ScreenFeeds.State
local prev: { [string]: any }? = nil
local log: { ScreenFeeds.LogLine } = {}
local boost = 0
local lastStateAt, lastFxAt, lastActivityAt = 0, 0, 0
local mounted = 0

local function serverNow(): number
	return workspace:GetServerTimeNow()
end

local function attr(name: string): any
	return matchState:GetAttribute(name)
end

local function faceSize(size: Vector3, face: Enum.NormalId): (number, number)
	if face == Enum.NormalId.Top or face == Enum.NormalId.Bottom then
		return size.Z, size.X
	elseif face == Enum.NormalId.Left or face == Enum.NormalId.Right then
		return size.Z, size.Y
	end
	return size.X, size.Y
end

local function roomOf(position: Vector3): (string?, FacilityMap.RoomInfo?)
	local id = FacilityMap.roomAt(rooms, position)
	return id, if id then rooms[id] else nil
end

local function terminalModelOf(instance: Instance): Model?
	local current = instance.Parent
	while current and current ~= workspace do
		if current:IsA("Model") and current:GetAttribute("TerminalId") then
			return current
		end
		current = current.Parent
	end
	return nil
end

local function shortName(name: string): string
	return (string.gsub(name, " terminal$", ""))
end

------------------------------------------------------------------------------------------------------------
-- The facts

local PHASE_STAMPS = { Lobby = "LOBBY", Loadout = "LOAD", Deployment = "DEPLOY", Results = "END" }

local function stamp(): string
	local phase = attr("Phase")
	if phase == "Race" or phase == "Finale" then
		return ScreenFeeds.clock(serverNow() - (attr("RaceStartedAt") or serverNow()))
	end
	return PHASE_STAMPS[phase] or "--"
end

local function event(text: string, level: string, room: string?)
	table.insert(log, { stamp = stamp(), text = text, level = level })
	while #log > LOG_SIZE do
		table.remove(log, 1)
	end
	boost = math.min(1, boost + (if level == "crit" then 0.35 else 0.2))
	if room and state then
		local entry = { text = text, at = os.clock() }
		state.alerts[room] = entry
		local info = rooms[room]
		if info and info.wing ~= "" then
			state.wingAlerts[info.wing] = entry
		end
	end
end

local function buildStatic()
	local roomData: { [string]: ScreenFeeds.Room } = {}
	local order = {}
	local extent = { math.huge, math.huge, -math.huge, -math.huge }
	for id, room in rooms do
		local cf, size = room.bounds.CFrame, room.bounds.Size
		local x0, z0, x1, z1 = math.huge, math.huge, -math.huge, -math.huge
		for _, sx in { -1, 1 } do
			for _, sz in { -1, 1 } do
				local p = cf:PointToWorldSpace(Vector3.new(sx * size.X / 2, 0, sz * size.Z / 2))
				x0, z0, x1, z1 = math.min(x0, p.X), math.min(z0, p.Z), math.max(x1, p.X), math.max(z1, p.Z)
			end
		end
		roomData[id] = { id = id, name = room.displayName, wing = room.wing, dark = false, emergency = false, rect = { x0, z0, x1, z1 } }
		table.insert(order, id)
		extent = { math.min(extent[1], x0), math.min(extent[2], z0), math.max(extent[3], x1), math.max(extent[4], z1) }
	end
	table.sort(order)
	local docks = {}
	local map = FacilityMap.folders()
	local dockFolder = map:FindFirstChild("Docks")
	for _, model in (if dockFolder then dockFolder:GetChildren() else {}) do
		local room = model:GetAttribute("Room")
		if type(room) == "string" then
			docks[room] = (docks[room] or 0) + 1
		end
	end
	local coreRoom = FacilityMap.core(rooms)
	state = {
		now = os.clock(),
		phase = "Lobby",
		phaseLabel = "LOBBY",
		clock = 0,
		clockLabel = "",
		threat = 1,
		upload = 0,
		lockdown = false,
		finale = nil,
		finaleLeft = 0,
		hold = 0,
		holdNeeded = Config.Finale.HoldSeconds,
		winner = nil,
		terminalsDone = 0,
		terminalsNeeded = Config.Terminals.ForLockdown,
		terminals = {},
		terminalsById = {},
		cameras = {},
		camerasById = {},
		rooms = roomData,
		roomOrder = order,
		extent = if extent[1] < math.huge then extent else nil,
		coreRoom = coreRoom,
		wingSecure = {},
		doors = {},
		docks = docks,
		squad = {},
		log = log,
		alerts = {},
		wingAlerts = {},
		activity = table.create(32, 0.1),
		load = 0.1,
		glitch = false,
	}
end

-- Reads every fact, then logs what changed since the last read.
local function collect()
	local now = serverNow()
	local s = state
	s.now = os.clock()
	local phase = attr("Phase") or "Lobby"
	local finale = attr("Finale")
	s.phase = phase
	s.finale = if type(finale) == "string" and finale ~= "" then finale else nil
	s.lockdown = attr("Lockdown") == true
	s.threat = math.clamp(attr("Threat") or 1, 1, 4)
	s.upload = math.clamp(attr("Upload") or 0, 0, 1)
	s.hold = attr("Hold") or 0
	local winner = attr("Winner")
	s.winner = if type(winner) == "string" then winner else nil
	s.terminalsDone = attr("TerminalsDone") or 0
	s.terminalsNeeded = attr("TerminalsNeeded") or Config.Terminals.ForLockdown
	local phaseLeft = math.max(0, (attr("PhaseEndsAt") or 0) - now)
	local finaleLeft = math.max(0, (attr("FinaleEndsAt") or 0) - now)
	s.finaleLeft = finaleLeft
	if phase == "Race" then
		s.clock, s.clockLabel = now - (attr("RaceStartedAt") or now), "BREACH ELAPSED"
	elseif phase == "Finale" then
		s.clock, s.clockLabel = finaleLeft, if s.finale == "Upload" then "UPLOAD SEQUENCE" else "PURGE PROTOCOL"
	elseif phase == "Results" then
		s.clock, s.clockLabel = attr("MatchSeconds") or 0, "MATCH TIME"
	elseif phase == "Lobby" then
		s.clock, s.clockLabel = phaseLeft, if attr("Waiting") then "WAITING FOR PLAYERS" else "NEXT ROUND"
	else
		s.clock, s.clockLabel = phaseLeft, string.upper(phase)
	end
	s.phaseLabel = if s.lockdown and phase == "Race" then "LOCKDOWN" else string.upper(phase)
	s.glitch = s.finale == "Upload"

	table.clear(s.terminals)
	table.clear(s.terminalsById)
	table.clear(s.wingSecure)
	for _, model in terminalModels do
		local id = model:GetAttribute("TerminalId")
		local roomId = model:GetAttribute("Room") or ""
		local room = rooms[roomId]
		local pivot = model:GetPivot().Position
		local t: ScreenFeeds.Terminal = {
			id = id,
			name = shortName(model:GetAttribute("DisplayName") or id),
			room = roomId,
			wing = if room then room.wing else "",
			progress = model:GetAttribute("Progress") or 0,
			done = model:GetAttribute("Done") == true,
			locked = (model:GetAttribute("LockedUntil") or 0) > now,
			operator = model:GetAttribute("Operator"),
			pos = Vector2.new(pivot.X, pivot.Z),
		}
		table.insert(s.terminals, t)
		s.terminalsById[id] = t
		if t.done and t.wing ~= "" then
			s.wingSecure[t.wing] = true
		end
	end

	table.clear(s.cameras)
	table.clear(s.camerasById)
	for _, model in cameraModels do
		local id = model:GetAttribute("CameraId")
		local c: ScreenFeeds.Camera = {
			id = id,
			name = model:GetAttribute("DisplayName") or id,
			room = model:GetAttribute("Room") or "",
			broken = (model:GetAttribute("BrokenUntil") or 0) > now,
		}
		table.insert(s.cameras, c)
		s.camerasById[id] = c
	end

	for id, r in s.rooms do
		local lights = roomLights[id]
		local lit = #lights == 0
		for _, light in lights do
			if light.Enabled then
				lit = true
				break
			end
		end
		r.dark = not lit
		local on = false
		for _, part in emergencyParts[id] or {} do
			if part.Material == Enum.Material.Neon then
				on = true
				break
			end
		end
		r.emergency = on
	end

	table.clear(s.doors)
	for id, door in doors do
		local light = door.lockLights[1]
		table.insert(s.doors, {
			id = id,
			name = door.model:GetAttribute("DisplayName") or id,
			rooms = door.rooms,
			locked = light ~= nil and light.Material == Enum.Material.Neon,
			welded = door.model:GetAttribute("Welded") == true,
		})
	end

	table.clear(s.squad)
	for _, player in Players:GetPlayers() do
		if player:GetAttribute("Role") == "Merc" then
			local character = player.Character
			local eliminated = player:GetAttribute("Eliminated") == true
			local bleedEndsAt = if character then character:GetAttribute("BleedEndsAt") or 0 else 0
			table.insert(s.squad, {
				name = player.DisplayName,
				class = player:GetAttribute("Class") or "Merc",
				hp = if character and not eliminated then character:GetAttribute("HP") or 0 else 0,
				maxHp = if character then character:GetAttribute("MaxHP") or Config.Health.MercMax else Config.Health.MercMax,
				downed = character ~= nil and character:GetAttribute("Downed") == true,
				bleedLeft = math.max(0, bleedEndsAt - now),
				eliminated = eliminated,
			})
		end
	end
	table.sort(s.squad, function(a, b)
		return a.name < b.name
	end)

	-- The event log: what changed since the last read. The first read only takes a baseline.
	local snapshot = {
		phase = phase,
		threat = s.threat,
		lockdown = s.lockdown,
		winner = s.winner,
		terminals = {},
		cameras = {},
		dark = {},
		emergency = {},
		doors = {},
		squad = {},
	}
	for _, t in s.terminals do
		snapshot.terminals[t.id] = { done = t.done, locked = t.locked, operator = t.operator ~= nil }
	end
	for _, c in s.cameras do
		snapshot.cameras[c.id] = c.broken
	end
	for id, r in s.rooms do
		snapshot.dark[id] = r.dark
		if r.emergency and r.wing ~= "" then
			snapshot.emergency[r.wing] = true
		end
	end
	for _, d in s.doors do
		snapshot.doors[d.id] = { locked = d.locked, welded = d.welded }
	end
	for _, m in s.squad do
		snapshot.squad[m.name] = { downed = m.downed, eliminated = m.eliminated }
	end
	local p = prev
	if p then
		if p.phase ~= phase then
			if phase == "Lobby" then
				table.clear(log)
				table.clear(s.alerts)
				table.clear(s.wingAlerts)
				event("SYSTEM STANDBY", "info")
			elseif phase == "Deployment" then
				event("INSERTION TEAM DEPLOYING", "info")
			elseif phase == "Race" then
				event("SECURITY BREACH · NETWORK INTRUSION", "crit")
			elseif phase == "Finale" then
				event(if s.finale == "Upload" then "UPLOAD SEQUENCE ACTIVE" else "PURGE PROTOCOL ENGAGED", "crit", s.coreRoom)
			elseif phase == "Results" then
				event(if s.winner == "Mercs" then "CONTAINMENT HELD" else "SYSTEM COMPROMISED", if s.winner == "Mercs" then "good" else "crit")
			end
		end
		if s.threat > p.threat then
			event("THREAT LEVEL " .. s.threat, "warn")
		end
		if s.lockdown and not p.lockdown then
			event("LOCKDOWN INITIATED", "crit", s.coreRoom)
		end
		for _, t in s.terminals do
			local before = p.terminals[t.id]
			if before then
				local name = string.upper(t.name)
				if t.done and not before.done then
					event("TERMINAL SECURED · " .. name, "good", t.room)
				elseif t.locked and not before.locked then
					event("TERMINAL FAULT · " .. name, "crit", t.room)
				elseif t.operator and not before.operator then
					event("REBOOT STARTED · " .. name, "info", t.room)
				end
			end
		end
		for _, c in s.cameras do
			if c.broken and p.cameras[c.id] == false then
				event("CAMERA OFFLINE · " .. string.upper(c.name), "warn", c.room)
			end
		end
		for id, r in s.rooms do
			local was = p.dark[id]
			if was ~= nil and r.dark ~= was then
				if r.dark then
					event("POWER FAILURE · " .. string.upper(r.name), "crit", id)
				else
					event("POWER RESTORED · " .. string.upper(r.name), "info")
				end
			end
		end
		for wing in snapshot.emergency do
			if not p.emergency[wing] then
				event("EMERGENCY POWER · WING " .. wing, "warn")
			end
		end
		for _, d in s.doors do
			local before = p.doors[d.id]
			if before then
				if d.welded and not before.welded then
					event("DOOR WELDED · " .. string.upper(d.name), "info")
				elseif d.locked and not before.locked then
					event("DOOR SEALED · " .. string.upper(d.name), "warn", d.rooms[1])
					local other = d.rooms[2]
					if other and other ~= "" then
						s.alerts[other] = s.alerts[d.rooms[1]]
					end
				end
			end
		end
		for _, m in s.squad do
			local before = p.squad[m.name]
			if before then
				if m.eliminated and not before.eliminated then
					event("SIGNAL LOST · " .. string.upper(m.name), "crit")
				elseif m.downed and not before.downed then
					event("VITALS CRITICAL · " .. string.upper(m.name), "crit")
				end
			end
		end
	end
	prev = snapshot
end

local function updateActivity(dt: number)
	boost = math.max(0, boost - dt * 0.25)
	local active = state.phase == "Race" or state.phase == "Finale"
	local base = if active then 0.14 + state.upload * 0.5 + (state.threat - 1) * 0.07 else 0.06
	local value = math.clamp(base + boost + (math.random() - 0.5) * 0.12, 0.02, 1)
	state.load = state.load + (value - state.load) * 0.5
	table.insert(state.activity, value)
	if #state.activity > 32 then
		table.remove(state.activity, 1)
	end
end

------------------------------------------------------------------------------------------------------------
-- The pieces

local function addScreen(part: Instance)
	if seen[part] or not part:IsA("BasePart") or not part:IsDescendantOf(workspace) then
		return
	end
	local gui = part:FindFirstChild("Display")
	if not (gui and gui:IsA("SurfaceGui")) then
		return
	end
	seen[part] = true
	local w, h = faceSize(part.Size, gui.Face)
	local roomId, room = roomOf(part.Position)
	local terminal = terminalModelOf(part)
	local cameraId = part:GetAttribute("CameraId")
	table.insert(screens, {
		part = part,
		gui = gui,
		feed = part:GetAttribute("Feed") or "Status",
		ctx = {
			width = ScreenFeeds.HEIGHT * w / math.max(h, 0.01),
			room = roomId,
			wing = if room then room.wing else nil,
			roomName = if room then room.displayName else nil,
			cameraId = if type(cameraId) == "string" and cameraId ~= "" then cameraId else nil,
			terminalId = if terminal then terminal:GetAttribute("TerminalId") else nil,
			pos = Vector2.new(part.Position.X, part.Position.Z),
			seed = ScreenFeeds.hash(part:GetFullName()),
		},
		handle = nil,
		brightness = gui.Brightness,
		nextAt = 0,
	})
end

local function addLeds(part: Instance)
	if seen[part] or not part:IsA("BasePart") or not part:IsDescendantOf(workspace) then
		return
	end
	seen[part] = true
	local group: LedGroup = { part = part, frames = {}, colors = {}, mode = "normal" }
	for _, d in part:GetDescendants() do
		if d:IsA("Frame") then
			table.insert(group.frames, d)
			table.insert(group.colors, d.BackgroundColor3)
		end
	end
	table.insert(ledGroups, group)
end

local function addLit(list: { Lit }, part: Instance, modeAttr: string, default: string)
	if seen[part] or not part:IsA("BasePart") or not part:IsDescendantOf(workspace) then
		return
	end
	seen[part] = true
	local roomId, room = roomOf(part.Position)
	local lit: Lit = {
		part = part,
		mode = part:GetAttribute(modeAttr) or default,
		room = roomId,
		wing = if room then room.wing else nil,
		terminal = terminalModelOf(part),
		door = nil,
		key = "",
	}
	if list == doorLights then
		local best, bestDistance = nil, 10
		for _, door in doors do
			local d = (door.closed.Position - part.Position).Magnitude
			if d < bestDistance then
				best, bestDistance = door, d
			end
		end
		lit.door = best
	end
	if list == signs and (lit.mode == "Room" or lit.mode == "Through") then
		local shown = room
		if lit.mode == "Through" then
			-- A doorframe header names the room beyond the wall it's mounted on.
			local _, beyond = roomOf(part.Position - part.CFrame.LookVector * 6)
			shown = beyond
		end
		local gui = part:FindFirstChild("SignText")
		local label = gui and gui:FindFirstChild("Text")
		if shown and label and label:IsA("TextLabel") then
			label.Text = string.upper(shown.displayName)
		end
	end
	table.insert(list, lit)
end

local function paint(lit: Lit, key: string, color: Color3, neon: boolean)
	if lit.key == key then
		return
	end
	lit.key = key
	lit.part.Color = color
	lit.part.Material = if neon then Enum.Material.Neon else Enum.Material.SmoothPlastic
end

local function updateLights()
	local s = state
	local alarm = s.lockdown or s.finale ~= nil
	local flash = math.floor(os.clock() * 2) % 2 == 0
	for _, lit in statusLights do
		local room = lit.room and s.rooms[lit.room]
		if lit.mode == "Terminal" and lit.terminal then
			local t = s.terminalsById[lit.terminal:GetAttribute("TerminalId")]
			if t then
				if t.done then
					paint(lit, "done", STATUS_COLORS.secure, true)
				elseif t.locked then
					paint(lit, if flash then "fault" else "fault2", if flash then STATUS_COLORS.fault else STATUS_COLORS.off, flash)
				elseif t.operator then
					paint(lit, "busy", STATUS_COLORS.busy, true)
				else
					paint(lit, "idle", STATUS_COLORS.normal, true)
				end
			end
		elseif lit.mode == "Power" then
			if room and room.dark then
				paint(lit, if flash then "dark" else "dark2", if flash then STATUS_COLORS.alarm else STATUS_COLORS.off, flash)
			else
				paint(lit, "ok", STATUS_COLORS.secure, true)
			end
		else
			if alarm then
				paint(lit, "alarm", STATUS_COLORS.alarm, true)
			elseif room and room.dark then
				paint(lit, "dark", STATUS_COLORS.dark, true)
			elseif lit.wing and s.wingSecure[lit.wing] then
				paint(lit, "secure", STATUS_COLORS.secure, true)
			else
				paint(lit, "normal", STATUS_COLORS.normal, true)
			end
		end
	end
	for _, lit in doorLights do
		local door = lit.door
		if not door then
			paint(lit, "none", STATUS_COLORS.off, false)
		else
			local info = nil
			for _, d in s.doors do
				if d.id == door.id then
					info = d
					break
				end
			end
			if info and info.welded then
				paint(lit, "welded", DOOR_COLORS.welded, true)
			elseif info and info.locked then
				paint(lit, if flash then "sealed" else "sealed2", if flash then DOOR_COLORS.sealed else STATUS_COLORS.off, flash)
			else
				paint(lit, "open", DOOR_COLORS.open, true)
			end
		end
	end
	for _, lit in signs do
		if lit.mode == "Lockdown" then
			local gui = lit.part:FindFirstChild("SignText")
			local label = gui and gui:FindFirstChild("Text")
			local message, color, on = "STANDBY", Color3.fromRGB(70, 74, 80), false
			if s.finale == "Upload" then
				message, color, on = "UPLOAD IN PROGRESS", ScreenFeeds.COLORS.upload, flash
			elseif s.finale == "Purge" then
				message, color, on = "PURGE IN PROGRESS", STATUS_COLORS.alarm, flash
			elseif s.lockdown then
				message, color, on = "LOCKDOWN", STATUS_COLORS.alarm, flash
			elseif s.phase == "Results" then
				message, color = if s.winner == "Mercs" then "ALL CLEAR" else "CONTAINMENT LOST", if s.winner == "Mercs" then STATUS_COLORS.secure else ScreenFeeds.COLORS.upload
			end
			if label and label:IsA("TextLabel") then
				label.Text = message
				label.TextColor3 = if on then Color3.fromRGB(20, 6, 6) else color
			end
			paint(lit, message .. tostring(on), if on then color else Color3.fromRGB(16, 17, 20), on)
		end
	end
end

local function updateLeds(cameraPos: Vector3)
	local s = state
	local mode = if s.finale == "Upload" then "upload" elseif s.lockdown or s.finale then "alarm" else "normal"
	local chance = 0.04 + s.load * 0.3
	for _, group in ledGroups do
		if (group.part.Position - cameraPos).Magnitude <= LED_RANGE then
			local repaint = group.mode ~= mode
			group.mode = mode
			for i, f in group.frames do
				if repaint then
					f.BackgroundColor3 = if mode == "upload" then (if i % 3 == 0 then STATUS_COLORS.alarm else ScreenFeeds.COLORS.upload) elseif mode == "alarm" then STATUS_COLORS.dark else group.colors[i]
				end
				if math.random() < chance then
					f.BackgroundTransparency = if f.BackgroundTransparency < 0.5 then 0.85 else 0.05
				end
			end
		end
	end
end

local function updateScreens(cameraPos: Vector3)
	local t = os.clock()
	for _, screen in screens do
		if t >= screen.nextAt then
			local distance = (screen.part.Position - cameraPos).Magnitude
			if distance <= FAR then
				screen.nextAt = t + (if distance <= NEAR then 0.125 else 0.5)
				if not screen.handle then
					screen.handle = ScreenFeeds.mount(screen.gui, screen.feed, screen.ctx)
					mounted += 1
				end
				local room = screen.ctx.room and state.rooms[screen.ctx.room]
				local brightness = if room and room.dark then screen.brightness * 0.35 else screen.brightness
				if screen.gui.Brightness ~= brightness then
					screen.gui.Brightness = brightness
				end
				local ok, err = pcall((screen.handle :: ScreenFeeds.Handle).update, state)
				if not ok then
					warn(`[Chimera] screen {screen.part:GetFullName()} ({screen.feed}): {err}`)
					screen.nextAt = math.huge
				end
			else
				screen.nextAt = t + 1
			end
		end
	end
end

local function step(dt: number)
	local t = os.clock()
	if t - lastStateAt >= 0.25 then
		lastStateAt = t
		collect()
		updateLights()
	end
	if t - lastActivityAt >= 0.5 then
		updateActivity(t - lastActivityAt)
		lastActivityAt = t
	end
	if t - lastFxAt >= 0.125 then
		lastFxAt = t
		local camera = workspace.CurrentCamera
		local cameraPos = if camera then camera.CFrame.Position else Vector3.zero
		state.now = t
		updateScreens(cameraPos)
		updateLeds(cameraPos)
	end
end

function FacilityScreens.init()
	matchState = ReplicatedStorage:WaitForChild("MatchState") :: Configuration
	local map, facility = FacilityMap.folders()
	rooms = FacilityMap.rooms()
	for id, room in rooms do
		local lights = {}
		for _, fixture in room.fixtures do
			for _, d in fixture:GetDescendants() do
				if d:IsA("Light") then
					table.insert(lights, d)
				end
			end
		end
		roomLights[id] = lights
	end
	emergencyParts = FacilityMap.emergencyLights()
	doors = FacilityMap.doors()
	for _, model in (map:WaitForChild("Terminals")):GetChildren() do
		if model:IsA("Model") and type(model:GetAttribute("TerminalId")) == "string" then
			table.insert(terminalModels, model)
		end
	end
	table.sort(terminalModels, function(a, b)
		return a.Name < b.Name
	end)
	for _, model in (facility:WaitForChild("Cameras")):GetChildren() do
		if type(model:GetAttribute("CameraId")) == "string" then
			table.insert(cameraModels, model)
		end
	end
	table.sort(cameraModels, function(a, b)
		return a.Name < b.Name
	end)
	buildStatic()
	collect()

	local handlers = {
		KitScreen = addScreen,
		KitLeds = addLeds,
		KitStatus = function(part)
			addLit(statusLights, part, "StatusMode", "Room")
		end,
		KitDoorLight = function(part)
			addLit(doorLights, part, "DoorMode", "Nearest")
		end,
		KitSign = function(part)
			addLit(signs, part, "SignMode", "Static")
		end,
	}
	for tag, handler in handlers do
		for _, instance in CollectionService:GetTagged(tag) do
			handler(instance)
		end
		CollectionService:GetInstanceAddedSignal(tag):Connect(handler)
	end
	RunService.Heartbeat:Connect(step)
end

function FacilityScreens.describe(): { [string]: any }
	local lines = {}
	for i = math.max(1, #log - 4), #log do
		table.insert(lines, `[{log[i].stamp}] {log[i].text}`)
	end
	local feeds = {}
	for _, screen in screens do
		feeds[screen.feed] = (feeds[screen.feed] or 0) + 1
	end
	local darkRooms = {}
	if state then
		for id, r in state.rooms do
			if r.dark then
				table.insert(darkRooms, id)
			end
		end
	end
	return {
		screens = #screens,
		mounted = mounted,
		feeds = feeds,
		ledGroups = #ledGroups,
		statusLights = #statusLights,
		doorLights = #doorLights,
		signs = #signs,
		load = if state then math.floor(state.load * 100) / 100 else 0,
		darkRooms = darkRooms,
		log = lines,
	}
end

return FacilityScreens
