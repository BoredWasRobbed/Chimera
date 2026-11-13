-- Live screens for the map kit. Every kit monitor, wall display and console screen draws one feed from the
-- match's real state: src/client/FacilityScreens gathers that state and calls update here, and the kit
-- generator (tools/mapkit) draws the same layouts with sample data so the kit previews look right.
-- No requires: the generator loads a clone of this module from the command bar.
--
-- A kit screen is a part tagged "KitScreen" with a SurfaceGui named "Display" and these attributes:
--   Feed       one of ScreenFeeds.FEEDS
--   CameraId   Camera feed only: the camera to show. Empty shows the camera in the screen's own room, or
--              cycles through every camera when the room has none.
--
-- Feeds:
--   Status     phase and clock, Threat Level, the upload meter, terminals secured, Lockdown and finales
--   Upload     the Chimera's upload meter, shown as a network intrusion
--   Terminals  every Mainframe Terminal: reboot progress, operator, faults, secured
--   Camera     a security camera's feed: NO SIGNAL while shot out, infrared while its room is dark
--   Room       the screen's own room: lights, power, doors, shell docks and the wing's terminal
--   Squad      every merc's vitals: HP, downed with the bleed-out clock, signal lost
--   Log        facility events as they happen: doors sealed, power failures, faults, downs
--   Map        the facility drawn from the real room layout: power, secured wings, terminals, you are here
--   Graph      network load, rising with the upload and spiking on events
--   Alert      security alerts for the screen's room and wing, and the Lockdown and finale banners
--   Terminal   one Mainframe Terminal's side screen (the screen sits inside the terminal's model)
--   Off        a dead screen
-- Nothing here shows where the Chimera or a merc is: every fact on a screen is already public.
local ScreenFeeds = {}

ScreenFeeds.HEIGHT = 240 -- every canvas is 240 px tall; its width follows the screen's shape

local ZEKTON = "rbxasset://fonts/families/Zekton.json"
local ROBOTO_MONO = "rbxasset://fonts/families/RobotoMono.json"

-- The kit's fonts: Zekton for headings, signs and big numbers, Roboto Mono for data lines.
ScreenFeeds.FONTS = {
	display = Font.new(ZEKTON, Enum.FontWeight.Bold),
	body = Font.new(ZEKTON, Enum.FontWeight.Regular),
	mono = Font.new(ROBOTO_MONO, Enum.FontWeight.Medium),
}
local FONT = ScreenFeeds.FONTS

ScreenFeeds.FEEDS = { "Status", "Upload", "Terminals", "Camera", "Room", "Squad", "Log", "Map", "Graph", "Alert", "Terminal", "Off" }

local C = {
	bg = Color3.fromRGB(6, 13, 17),
	panel = Color3.fromRGB(11, 24, 30),
	ink = Color3.fromRGB(120, 230, 210),
	dim = Color3.fromRGB(66, 132, 124),
	faint = Color3.fromRGB(26, 52, 54),
	warn = Color3.fromRGB(255, 190, 80),
	crit = Color3.fromRGB(255, 72, 60),
	good = Color3.fromRGB(90, 255, 140),
	upload = Color3.fromRGB(205, 80, 255),
	merc = Color3.fromRGB(110, 210, 255),
	white = Color3.fromRGB(225, 235, 235),
}
ScreenFeeds.COLORS = C
local THREAT = { C.ink, Color3.fromRGB(255, 215, 90), Color3.fromRGB(255, 145, 60), C.crit }
ScreenFeeds.THREAT_COLORS = THREAT

export type Terminal = { id: string, name: string, room: string, wing: string, progress: number, done: boolean, locked: boolean, operator: string?, pos: Vector2? }
export type Camera = { id: string, name: string, room: string, broken: boolean }
export type Room = { id: string, name: string, wing: string, dark: boolean, emergency: boolean, rect: { number }? }
export type Door = { id: string, name: string, rooms: { string }, locked: boolean, welded: boolean }
export type Merc = { name: string, class: string, hp: number, maxHp: number, downed: boolean, bleedLeft: number, eliminated: boolean }
export type LogLine = { stamp: string, text: string, level: string }
export type State = {
	now: number, -- os.clock(), drives blinking and noise
	phase: string,
	phaseLabel: string,
	clock: number,
	clockLabel: string,
	threat: number,
	upload: number,
	lockdown: boolean,
	finale: string?,
	finaleLeft: number,
	hold: number,
	holdNeeded: number,
	winner: string?,
	terminalsDone: number,
	terminalsNeeded: number,
	terminals: { Terminal },
	terminalsById: { [string]: Terminal },
	cameras: { Camera },
	camerasById: { [string]: Camera },
	rooms: { [string]: Room },
	roomOrder: { string },
	extent: { number }?,
	coreRoom: string?,
	wingSecure: { [string]: boolean },
	doors: { Door },
	docks: { [string]: number },
	squad: { Merc },
	log: { LogLine },
	alerts: { [string]: { text: string, at: number } },
	wingAlerts: { [string]: { text: string, at: number } },
	activity: { number },
	load: number,
	glitch: boolean,
}
export type Context = {
	width: number,
	room: string?,
	wing: string?,
	roomName: string?,
	cameraId: string?,
	terminalId: string?,
	pos: Vector2?,
	seed: number,
}
export type Handle = { feed: string, update: (State) -> () }

------------------------------------------------------------------------------------------------------------
-- UI helpers

local function frame(parent: Instance, name: string, pos: UDim2, size: UDim2, color: Color3?, transparency: number?): Frame
	local f = Instance.new("Frame")
	f.Name = name
	f.BorderSizePixel = 0
	f.Position = pos
	f.Size = size
	f.BackgroundColor3 = color or C.bg
	f.BackgroundTransparency = if color then (transparency or 0) else 1
	f.Parent = parent
	return f
end

local function text(parent: Instance, name: string, value: string, pos: UDim2, size: UDim2, px: number, font: Font, color: Color3, xAlign: Enum.TextXAlignment?, yAlign: Enum.TextYAlignment?): TextLabel
	local t = Instance.new("TextLabel")
	t.Name = name
	t.BackgroundTransparency = 1
	t.Position = pos
	t.Size = size
	t.Text = value
	t.TextSize = px
	t.FontFace = font
	t.TextColor3 = color
	t.TextXAlignment = xAlign or Enum.TextXAlignment.Left
	t.TextYAlignment = yAlign or Enum.TextYAlignment.Center
	t.TextTruncate = Enum.TextTruncate.AtEnd
	t.Parent = parent
	return t
end

local function setText(label: TextLabel, value: string, color: Color3?)
	if label.Text ~= value then
		label.Text = value
	end
	if color and label.TextColor3 ~= color then
		label.TextColor3 = color
	end
end

local function setFill(f: Frame, color: Color3, transparency: number?)
	if f.BackgroundColor3 ~= color then
		f.BackgroundColor3 = color
	end
	local t = transparency or 0
	if f.BackgroundTransparency ~= t then
		f.BackgroundTransparency = t
	end
end

local function stroke(obj: GuiObject, color: Color3, thickness: number, transparency: number?): UIStroke
	local s = Instance.new("UIStroke")
	s.Color = color
	s.Thickness = thickness
	s.Transparency = transparency or 0
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	s.Parent = obj
	return s
end

local function bar(parent: Instance, name: string, pos: UDim2, size: UDim2, fill: Color3): (Frame, Frame)
	local back = frame(parent, name, pos, size, C.faint, 0.2)
	local f = frame(back, "Fill", UDim2.new(), UDim2.fromScale(0, 1), fill, 0)
	return back, f
end

local function setBar(fill: Frame, alpha: number, color: Color3?)
	local size = UDim2.fromScale(math.clamp(alpha, 0, 1), 1)
	if fill.Size ~= size then
		fill.Size = size
	end
	if color and fill.BackgroundColor3 ~= color then
		fill.BackgroundColor3 = color
	end
end

local function clock(seconds: number): string
	seconds = math.max(0, math.floor(seconds))
	return string.format("%02d:%02d", seconds // 60, seconds % 60)
end
ScreenFeeds.clock = clock

local function hash(s: string): number
	local h = 5381
	for i = 1, #s do
		h = (h * 33 + string.byte(s, i)) % 2147483647
	end
	return h
end
ScreenFeeds.hash = hash

local function blink(s: State, rate: number): boolean
	return math.floor(s.now * rate) % 2 == 0
end

local function terminalLook(t: Terminal): (string, Color3)
	if t.done then
		return "SECURED", C.good
	elseif t.locked then
		return "FAULT · LOCKED", C.upload
	elseif t.operator then
		return "REBOOTING · " .. string.upper(t.operator), C.warn
	end
	return "IDLE", C.merc
end
ScreenFeeds.terminalLook = terminalLook

local function recent(alert: { text: string, at: number }?, now: number): boolean
	return alert ~= nil and now - alert.at < 8
end

-- Header, footer and corner brackets shared by most feeds.
type Chrome = { title: TextLabel, right: TextLabel, line: Frame, footer: TextLabel }
local function chrome(content: Frame, title: string, ctx: Context): Chrome
	local header = frame(content, "Header", UDim2.new(), UDim2.new(1, 0, 0, 30), C.panel, 0)
	local line = frame(header, "Line", UDim2.new(0, 0, 1, -2), UDim2.new(1, 0, 0, 2), C.ink, 0.15)
	local titleLabel = text(header, "Title", title, UDim2.fromOffset(10, 0), UDim2.new(0.62, -10, 1, -2), 17, FONT.display, C.ink)
	local right = text(header, "Right", "", UDim2.new(0.62, 0, 0, 0), UDim2.new(0.38, -10, 1, -2), 13, FONT.mono, C.dim, Enum.TextXAlignment.Right)
	local where = if ctx.roomName then string.upper(ctx.roomName) else "NODE " .. string.format("%02d", ctx.seed % 97)
	local footer = text(content, "Footer", "AXIOM DATA VAULT // " .. where, UDim2.new(0, 10, 1, -17), UDim2.new(1, -20, 0, 14), 11, FONT.mono, C.dim)
	for _, corner in { { 0, 0 }, { 1, 0 }, { 0, 1 }, { 1, 1 } } do
		local x, y = corner[1], corner[2]
		local hx = if x == 0 then 4 else -14
		local vx = if x == 0 then 4 else -6
		local hy = if y == 0 then 34 else -22
		local vy = if y == 0 then 34 else -30
		frame(content, "Bracket", UDim2.new(x, hx, y, hy), UDim2.fromOffset(10, 2), C.dim, 0.3)
		frame(content, "Bracket", UDim2.new(x, vx, y, vy), UDim2.fromOffset(2, 10), C.dim, 0.3)
	end
	return { title = titleLabel, right = right, line = line, footer = footer }
end

local function accent(ch: Chrome, s: State)
	setFill(ch.line, THREAT[math.clamp(s.threat, 1, 4)], 0.15)
end

------------------------------------------------------------------------------------------------------------
-- Feeds. Each builder draws into `content` and returns its update function.

type Builder = (content: Frame, ctx: Context) -> (State) -> ()
local FEED: { [string]: Builder } = {}

local function resultText(s: State): (string, Color3)
	if s.winner == "Mercs" then
		return "CONTAINMENT HELD", C.good
	elseif s.winner == "Chimera" then
		return "UPLOAD COMPLETE · SYSTEM LOST", C.upload
	end
	return "STANDBY", C.dim
end

FEED.Status = function(content, ctx)
	local ch = chrome(content, "FACILITY STATUS", ctx)
	local clockLabel = text(content, "Clock", "00:00", UDim2.fromOffset(14, 38), UDim2.new(0.52, -14, 0, 66), math.clamp(math.floor(ctx.width * 0.14), 40, 58), FONT.display, C.white)
	local sub = text(content, "Sub", "", UDim2.fromOffset(16, 104), UDim2.new(0.52, -16, 0, 16), 12, FONT.mono, C.dim)
	local col = frame(content, "Column", UDim2.new(0.52, 6, 0, 40), UDim2.new(0.48, -20, 0, 122))
	text(col, "ThreatLabel", "THREAT LEVEL", UDim2.new(), UDim2.new(1, 0, 0, 14), 12, FONT.mono, C.dim)
	local segs = {}
	for i = 1, 4 do
		segs[i] = frame(col, "Threat" .. i, UDim2.new((i - 1) * 0.25, 1, 0, 17), UDim2.new(0.25, -3, 0, 11), C.faint, 0)
	end
	text(col, "UploadLabel", "UPLOAD", UDim2.fromOffset(0, 38), UDim2.new(0.6, 0, 0, 14), 12, FONT.mono, C.dim)
	local uploadPct = text(col, "UploadPct", "0%", UDim2.new(0.5, 0, 0, 38), UDim2.new(0.5, 0, 0, 14), 13, FONT.mono, C.upload, Enum.TextXAlignment.Right)
	local _, uploadFill = bar(col, "Upload", UDim2.fromOffset(0, 55), UDim2.new(1, 0, 0, 10), C.upload)
	text(col, "TerminalsLabel", "TERMINALS SECURED", UDim2.fromOffset(0, 76), UDim2.new(1, 0, 0, 14), 12, FONT.mono, C.dim)
	local terminals = text(col, "Terminals", "0 / 2", UDim2.fromOffset(0, 92), UDim2.new(1, 0, 0, 26), 24, FONT.display, C.merc)
	local banner = frame(content, "Banner", UDim2.new(0, 10, 1, -62), UDim2.new(1, -20, 0, 38), C.panel, 0)
	local bannerStroke = stroke(banner, C.faint, 1)
	local bannerText = text(banner, "Text", "", UDim2.fromOffset(10, 0), UDim2.new(1, -20, 1, 0), 15, FONT.display, C.ink, Enum.TextXAlignment.Center)
	return function(s)
		accent(ch, s)
		setText(ch.right, s.phaseLabel)
		setText(clockLabel, clock(s.clock))
		setText(sub, s.clockLabel)
		for i, seg in segs do
			setFill(seg, if i <= s.threat then THREAT[i] else C.faint)
		end
		setText(uploadPct, string.format("%d%%", math.floor(s.upload * 100)))
		setBar(uploadFill, s.upload)
		setText(terminals, string.format("%d / %d", s.terminalsDone, s.terminalsNeeded), if s.terminalsDone >= s.terminalsNeeded then C.good else C.merc)
		local message, color, back = "ALL SYSTEMS NOMINAL", C.dim, C.panel
		if s.finale == "Upload" then
			message, color, back = "UPLOAD SEQUENCE · " .. clock(s.finaleLeft), C.upload, Color3.fromRGB(30, 8, 38)
		elseif s.finale == "Purge" then
			message, color, back = "PURGE PROTOCOL · " .. clock(s.finaleLeft), C.crit, Color3.fromRGB(36, 8, 8)
		elseif s.lockdown then
			message, color, back = "LOCKDOWN IN EFFECT", C.crit, if blink(s, 2) then Color3.fromRGB(46, 10, 10) else C.panel
		elseif s.phase == "Results" then
			message, color = resultText(s)
		elseif #s.log > 0 then
			local last = s.log[#s.log]
			message = last.text
			color = if last.level == "crit" then C.crit elseif last.level == "warn" then C.warn else C.ink
		end
		setText(bannerText, message, color)
		setFill(banner, back)
		bannerStroke.Color = if color == C.dim then C.faint else color
	end
end

FEED.Upload = function(content, ctx)
	local ch = chrome(content, "NETWORK INTRUSION", ctx)
	local pct = text(content, "Percent", "0%", UDim2.fromOffset(14, 34), UDim2.new(0.6, -14, 0, 80), 70, FONT.display, C.upload)
	local status = text(content, "Status", "", UDim2.new(0.55, 0, 0, 46), UDim2.new(0.45, -14, 0, 16), 12, FONT.mono, C.dim, Enum.TextXAlignment.Right)
	local rate = text(content, "Rate", "", UDim2.new(0.55, 0, 0, 64), UDim2.new(0.45, -14, 0, 16), 12, FONT.mono, C.dim, Enum.TextXAlignment.Right)
	local segs = {}
	local count = 24
	for i = 1, count do
		segs[i] = frame(content, "Seg", UDim2.new((i - 1) / count, if i == 1 then 14 else 2, 0, 118), UDim2.new(1 / count, -4, 0, 16), C.faint, 0)
	end
	-- The first and last segments sit inside the side margins.
	segs[1].Size = UDim2.new(1 / count, -16, 0, 16)
	segs[count].Size = UDim2.new(1 / count, -16, 0, 16)
	local lines = {}
	for i = 1, 4 do
		lines[i] = text(content, "Packet", "", UDim2.fromOffset(14, 140 + (i - 1) * 16), UDim2.new(1, -28, 0, 16), 12, FONT.mono, C.faint)
	end
	return function(s)
		accent(ch, s)
		setText(ch.right, if s.phase == "Race" or s.phase == "Finale" then "TRACE ACTIVE" else "IDLE")
		setText(pct, string.format("%d%%", math.floor(s.upload * 100)))
		local lit = s.upload * count
		for i, seg in segs do
			if i <= math.floor(lit) then
				setFill(seg, if s.upload > 0.8 then C.crit else C.upload)
			elseif i == math.floor(lit) + 1 and lit % 1 > 0.05 then
				setFill(seg, C.upload, 0.6)
			else
				setFill(seg, C.faint)
			end
		end
		local active = s.phase == "Race" or s.phase == "Finale"
		local statusText = if s.winner == "Chimera" then "UPLOAD COMPLETE" elseif s.upload >= 0.8 then "UPLINK SATURATED" elseif active then "INTRUSION IN PROGRESS" else "NO INTRUSION DETECTED"
		setText(status, statusText, if s.upload >= 0.8 or s.winner == "Chimera" then C.crit else C.dim)
		setText(rate, if active then string.format("%.1f MB/S", 2 + s.load * 38) else "0.0 MB/S")
		local rng = Random.new(math.floor(s.now * 3) + ctx.seed)
		for i, line in lines do
			if active and i <= 1 + math.floor(s.load * 4) then
				local parts = {}
				for _ = 1, 6 do
					table.insert(parts, string.format("%04X", rng:NextInteger(0, 65535)))
				end
				setText(line, "0x" .. table.concat(parts, " "), if i == 1 then C.dim else C.faint)
			else
				setText(line, if i == 1 then "-- link idle --" else "")
			end
		end
	end
end

FEED.Terminals = function(content, ctx)
	local ch = chrome(content, "MAINFRAME TERMINALS", ctx)
	local rows: { { name: TextLabel, state: TextLabel, pct: TextLabel, fill: Frame } } = {}
	local holder = frame(content, "Rows", UDim2.fromOffset(0, 34), UDim2.new(1, 0, 1, -54))
	local function rebuild(n: number)
		holder:ClearAllChildren()
		table.clear(rows)
		local h = math.clamp(math.floor(180 / math.max(n, 1)), 30, 46)
		for i = 1, n do
			local y = (i - 1) * h + 2
			local row = {
				name = text(holder, "Name", "", UDim2.fromOffset(14, y), UDim2.new(0.55, -14, 0, 18), 15, FONT.display, C.white),
				state = text(holder, "State", "", UDim2.new(0.5, 0, 0, y), UDim2.new(0.5, -14, 0, 18), 11, FONT.mono, C.dim, Enum.TextXAlignment.Right),
				pct = text(holder, "Pct", "", UDim2.new(1, -52, 0, y + 19), UDim2.fromOffset(38, 10), 11, FONT.mono, C.dim, Enum.TextXAlignment.Right),
				fill = select(2, bar(holder, "Bar", UDim2.fromOffset(14, y + 20), UDim2.new(1, -72, 0, 8), C.merc)),
			}
			rows[i] = row
		end
	end
	return function(s)
		accent(ch, s)
		setText(ch.right, string.format("%d/%d FOR LOCKDOWN", s.terminalsDone, s.terminalsNeeded))
		if #rows ~= #s.terminals then
			rebuild(#s.terminals)
		end
		for i, t in s.terminals do
			local row = rows[i]
			local label, color = terminalLook(t)
			setText(row.name, string.upper(t.name), if t.done then C.good else C.white)
			setText(row.state, label, color)
			setText(row.pct, string.format("%d%%", math.floor(t.progress * 100)))
			setBar(row.fill, if t.done then 1 else t.progress, color)
		end
	end
end

-- A security camera's view: a dim corridor drawn from the camera's id, the camera's labels, and static
-- or infrared when the camera or its room is down.
FEED.Camera = function(content, ctx)
	local w, h = ctx.width, ScreenFeeds.HEIGHT
	local scene = frame(content, "Scene", UDim2.new(), UDim2.fromScale(1, 1), Color3.fromRGB(40, 48, 46), 0)
	local shapes: { { f: Frame, lum: number } } = {}
	local function shape(name: string, x: number, y: number, sw: number, sh: number, lum: number, rotation: number?)
		local f = frame(scene, name, UDim2.fromOffset(x, y), UDim2.fromOffset(sw, sh), Color3.new(lum, lum, lum), 0)
		f.Rotation = rotation or 0
		table.insert(shapes, { f = f, lum = lum })
		return f
	end
	local function line(x1: number, y1: number, x2: number, y2: number, lum: number)
		local dx, dy = x2 - x1, y2 - y1
		local length = math.sqrt(dx * dx + dy * dy)
		shape("Edge", (x1 + x2) / 2 - length / 2, (y1 + y2) / 2 - 1, length, 2, lum, math.deg(math.atan2(dy, dx)))
	end
	local drawnFor = ""
	local function draw(id: string)
		drawnFor = id
		scene:ClearAllChildren()
		table.clear(shapes)
		local rng = Random.new(hash(id))
		-- Back wall, floor and ceiling of a corridor in one-point perspective.
		local bw, bh = w * rng:NextNumber(0.3, 0.42), h * rng:NextNumber(0.3, 0.38)
		local bx, by = (w - bw) / 2 + rng:NextNumber(-w * 0.08, w * 0.08), h * 0.3
		shape("Ceiling", 0, 0, w, by, 0.1)
		shape("Floor", 0, by + bh, w, h - by - bh, 0.2)
		shape("Back", bx, by, bw, bh, 0.16)
		shape("Door", bx + bw * rng:NextNumber(0.3, 0.55), by + bh * 0.25, bw * 0.22, bh * 0.75, 0.04)
		line(0, 0, bx, by, 0.32)
		line(w, 0, bx + bw, by, 0.32)
		line(0, h, bx, by + bh, 0.36)
		line(w, h, bx + bw, by + bh, 0.36)
		-- Racks or desks along the walls, and ceiling lights.
		for i = 1, rng:NextInteger(2, 4) do
			local t = i / 5
			local x = bx * (1 - t) + rng:NextNumber(-6, 6)
			local sh2 = (h - by - bh) * (1 - t) + bh * 0.8
			shape("Prop", x * 0.6, by + bh - sh2 * 0.55 + (h - by - bh) * (1 - t) * 0.6, 14 + 30 * (1 - t), sh2 * 0.6, 0.07)
			shape("Prop", w - x * 0.6 - (14 + 30 * (1 - t)), by + bh - sh2 * 0.55 + (h - by - bh) * (1 - t) * 0.6, 14 + 30 * (1 - t), sh2 * 0.6, 0.08)
		end
		for i = 1, 3 do
			local t = i / 4
			local lw = 40 * (1 - t) + 10
			shape("Lamp", w / 2 - lw / 2 + (bx + bw / 2 - w / 2) * t, by * (1 - t) * 0.6 + 4, lw, 4, 0.75)
		end
	end
	local vignetteTop = frame(content, "Vignette", UDim2.new(), UDim2.new(1, 0, 0, 60), Color3.new(0, 0, 0), 0.2)
	local gTop = Instance.new("UIGradient")
	gTop.Rotation = 90
	gTop.Transparency = NumberSequence.new(0.2, 1)
	gTop.Parent = vignetteTop
	local vignetteBottom = frame(content, "Vignette", UDim2.new(0, 0, 1, -60), UDim2.new(1, 0, 0, 60), Color3.new(0, 0, 0), 0.2)
	local gBottom = Instance.new("UIGradient")
	gBottom.Rotation = 90
	gBottom.Transparency = NumberSequence.new(1, 0.2)
	gBottom.Parent = vignetteBottom
	local scan = frame(content, "Scanline", UDim2.new(), UDim2.new(1, 0, 0, 10), Color3.new(1, 1, 1), 0.93)
	local noise = frame(content, "Noise", UDim2.new(), UDim2.fromScale(1, 1))
	local noiseBars = {}
	for i = 1, 14 do
		noiseBars[i] = frame(noise, "Bar", UDim2.new(), UDim2.new(1, 0, 0, 4), Color3.new(0.6, 0.6, 0.6), 0.5)
	end
	local camLabel = text(content, "Cam", "", UDim2.fromOffset(10, 6), UDim2.new(0.6, 0, 0, 16), 13, FONT.mono, C.white)
	local roomLabel = text(content, "Room", "", UDim2.fromOffset(10, 22), UDim2.new(0.6, 0, 0, 14), 12, FONT.body, C.white)
	local rec = text(content, "Rec", "● REC", UDim2.new(1, -90, 0, 6), UDim2.fromOffset(80, 16), 13, FONT.mono, C.crit, Enum.TextXAlignment.Right)
	local ir = text(content, "IR", "IR MODE", UDim2.new(1, -90, 0, 22), UDim2.fromOffset(80, 14), 11, FONT.mono, C.good, Enum.TextXAlignment.Right)
	local stamp = text(content, "Stamp", "", UDim2.new(0, 10, 1, -20), UDim2.new(0.5, 0, 0, 14), 12, FONT.mono, C.white)
	local cycle = text(content, "Cycle", "", UDim2.new(0.5, 0, 1, -20), UDim2.new(0.5, -10, 0, 14), 11, FONT.mono, C.white, Enum.TextXAlignment.Right)
	local noSignal = text(content, "NoSignal", "NO SIGNAL", UDim2.new(0, 0, 0.5, -16), UDim2.new(1, 0, 0, 32), 28, FONT.display, C.white, Enum.TextXAlignment.Center)
	return function(s)
		local cam: Camera? = nil
		local cycling = false
		if ctx.cameraId and s.camerasById[ctx.cameraId] then
			cam = s.camerasById[ctx.cameraId]
		elseif ctx.room then
			for _, c in s.cameras do
				if c.room == ctx.room then
					cam = c
					break
				end
			end
		end
		if not cam and #s.cameras > 0 then
			cycling = true
			cam = s.cameras[math.floor(s.now / 8) % #s.cameras + 1]
		end
		if not cam then
			setText(camLabel, "CAM --")
			noise.Visible = true
			noSignal.Visible = true
			return
		end
		if drawnFor ~= cam.id then
			draw(cam.id)
		end
		local room = s.rooms[cam.room]
		local dark = room ~= nil and room.dark
		setText(camLabel, "CAM " .. cam.id)
		setText(roomLabel, string.upper(if room then room.name else cam.name))
		setText(stamp, if s.phase == "Race" or s.phase == "Finale" then "T+" .. clock(s.clock) else s.phaseLabel)
		setText(cycle, if cycling then string.format("AUTO %d/%d", table.find(s.cameras, cam) or 1, #s.cameras) else "")
		rec.Visible = not cam.broken and blink(s, 1)
		ir.Visible = dark and not cam.broken
		for _, sh in shapes do
			local l = sh.lum
			sh.f.BackgroundColor3 = if dark then Color3.new(l * 0.25, l * 1.1 + 0.03, l * 0.35) else Color3.new(l * 0.88, l, l * 0.95)
		end
		scene.BackgroundColor3 = if dark then Color3.fromRGB(4, 26, 10) else Color3.fromRGB(40, 48, 46)
		noise.Visible = cam.broken
		noSignal.Visible = cam.broken
		if cam.broken then
			local rng = Random.new(math.floor(s.now * 12) + ctx.seed)
			for _, b in noiseBars do
				b.Position = UDim2.fromOffset(0, rng:NextInteger(0, h))
				b.Size = UDim2.new(1, 0, 0, rng:NextInteger(2, 12))
				b.BackgroundTransparency = rng:NextNumber(0.3, 0.85)
			end
			scene.BackgroundColor3 = Color3.fromRGB(14, 14, 14)
		end
		scan.Position = UDim2.fromOffset(0, (s.now * 40) % (h + 10) - 10)
	end
end

FEED.Room = function(content, ctx)
	local ch = chrome(content, "LOCAL STATUS", ctx)
	local name = text(content, "RoomName", string.upper(ctx.roomName or "UNASSIGNED"), UDim2.fromOffset(14, 34), UDim2.new(1, -28, 0, 30), 24, FONT.display, C.white)
	local wing = text(content, "Wing", "", UDim2.fromOffset(14, 62), UDim2.new(1, -28, 0, 14), 12, FONT.mono, C.dim)
	local keys = { "LIGHTING", "POWER", "DOORS", "SHELL DOCKS", "TERMINAL" }
	local values = {}
	for i, key in keys do
		local y = 82 + (i - 1) * 25
		frame(content, "Rule", UDim2.new(0, 14, 0, y + 22), UDim2.new(1, -28, 0, 1), C.faint, 0)
		text(content, "Key", key, UDim2.fromOffset(14, y), UDim2.new(0.5, -14, 0, 22), 12, FONT.mono, C.dim)
		values[key] = text(content, "Value", "", UDim2.new(0.4, 0, 0, y), UDim2.new(0.6, -14, 0, 22), 14, FONT.display, C.ink, Enum.TextXAlignment.Right)
	end
	return function(s)
		accent(ch, s)
		local room = ctx.room and s.rooms[ctx.room]
		if not room then
			setText(wing, "NO ROOM DATA")
			return
		end
		setText(name, string.upper(room.name))
		setText(wing, "WING " .. (if room.wing ~= "" then room.wing else "--"))
		setText(ch.right, if room.dark then "POWER FAULT" else "NOMINAL", if room.dark then C.crit else C.dim)
		setText(values.LIGHTING, if room.dark then "OFFLINE" else "ONLINE", if room.dark then C.crit else C.good)
		local secure = s.wingSecure[room.wing] == true
		if s.finale or s.lockdown then
			setText(values.POWER, "LOCKDOWN", C.crit)
		elseif room.emergency or secure then
			setText(values.POWER, "EMERGENCY", C.warn)
		else
			setText(values.POWER, "MAIN", C.ink)
		end
		local sealed, welded, total = 0, 0, 0
		for _, d in s.doors do
			if d.rooms[1] == room.id or d.rooms[2] == room.id then
				total += 1
				if d.welded then
					welded += 1
				elseif d.locked then
					sealed += 1
				end
			end
		end
		if total == 0 then
			setText(values.DOORS, "NONE", C.dim)
		elseif sealed > 0 then
			setText(values.DOORS, string.format("%d SEALED", sealed), C.warn)
		elseif welded > 0 then
			setText(values.DOORS, string.format("%d WELDED", welded), C.merc)
		else
			setText(values.DOORS, string.format("%d OPEN", total), C.ink)
		end
		local docks = s.docks[room.id] or 0
		if docks == 0 then
			setText(values["SHELL DOCKS"], "NONE", C.dim)
		elseif secure or s.lockdown or s.finale then
			setText(values["SHELL DOCKS"], "OFFLINE", C.good)
		else
			setText(values["SHELL DOCKS"], string.format("%d ACTIVE", docks), C.warn)
		end
		local term: Terminal? = nil
		for _, t in s.terminals do
			if t.wing == room.wing and room.wing ~= "" then
				term = t
				break
			end
		end
		if term then
			local label, color = terminalLook(term)
			setText(values.TERMINAL, if term.done or term.locked then label else string.format("%d%% %s", math.floor(term.progress * 100), if term.operator then "REBOOTING" else "IDLE"), color)
		else
			setText(values.TERMINAL, "NONE", C.dim)
		end
	end
end

FEED.Squad = function(content, ctx)
	local ch = chrome(content, "SQUAD TELEMETRY", ctx)
	local empty = text(content, "Empty", "NO ACTIVE PERSONNEL", UDim2.new(0, 0, 0.5, -10), UDim2.new(1, 0, 0, 20), 16, FONT.display, C.dim, Enum.TextXAlignment.Center)
	local rows = {}
	for i = 1, 5 do
		local y = 36 + (i - 1) * 35
		local row = frame(content, "Row", UDim2.fromOffset(0, y), UDim2.new(1, 0, 0, 34))
		rows[i] = {
			frame = row,
			name = text(row, "Name", "", UDim2.fromOffset(14, 2), UDim2.new(0.45, -14, 0, 17), 15, FONT.display, C.white),
			class = text(row, "Class", "", UDim2.fromOffset(14, 19), UDim2.new(0.45, -14, 0, 12), 10, FONT.mono, C.dim),
			fill = select(2, bar(row, "HP", UDim2.new(0.45, 0, 0, 12), UDim2.new(0.33, 0, 0, 9), C.good)),
			status = text(row, "Status", "", UDim2.new(0.78, 4, 0, 2), UDim2.new(0.22, -18, 0, 28), 12, FONT.mono, C.good, Enum.TextXAlignment.Right),
		}
	end
	return function(s)
		accent(ch, s)
		local alive = 0
		for _, m in s.squad do
			if not m.eliminated then
				alive += 1
			end
		end
		setText(ch.right, string.format("%d/%d SIGNAL", alive, #s.squad))
		empty.Visible = #s.squad == 0
		for i, row in rows do
			local m = s.squad[i]
			row.frame.Visible = m ~= nil
			if m then
				local hpAlpha = if m.maxHp > 0 then m.hp / m.maxHp else 0
				local color = if hpAlpha > 0.6 then C.good elseif hpAlpha > 0.3 then C.warn else C.crit
				setText(row.name, string.upper(m.name), if m.eliminated then C.dim else C.white)
				setText(row.class, string.upper(m.class))
				setBar(row.fill, if m.eliminated then 0 else hpAlpha, color)
				if m.eliminated then
					setText(row.status, "SIGNAL LOST", C.dim)
				elseif m.downed then
					setText(row.status, "DOWN " .. clock(m.bleedLeft), if blink(s, 2) then C.crit else C.warn)
				else
					setText(row.status, string.format("%d HP", math.ceil(m.hp)), color)
				end
			end
		end
	end
end

FEED.Log = function(content, ctx)
	local ch = chrome(content, "EVENT LOG", ctx)
	local lines = {}
	for i = 1, 9 do
		lines[i] = text(content, "Line", "", UDim2.fromOffset(12, 34 + (i - 1) * 20), UDim2.new(1, -24, 0, 18), 12, FONT.mono, C.ink)
	end
	return function(s)
		accent(ch, s)
		setText(ch.right, string.format("%d EVENTS", #s.log))
		local first = math.max(1, #s.log - #lines + 1)
		for i, label in lines do
			local entry = s.log[first + i - 1]
			if entry then
				local color = if entry.level == "crit" then C.crit elseif entry.level == "warn" then C.warn elseif entry.level == "good" then C.good else C.ink
				local cursor = if first + i - 1 == #s.log and blink(s, 2) then " _" else ""
				setText(label, string.format("[%s] %s%s", entry.stamp, entry.text, cursor), color)
			else
				setText(label, if i == 1 and #s.log == 0 then "> awaiting events _" else "", C.dim)
			end
		end
	end
end

-- The facility from above, drawn from the rooms' real bounds.
FEED.Map = function(content, ctx)
	local ch = chrome(content, "FACILITY MAP", ctx)
	local area = frame(content, "Area", UDim2.fromOffset(12, 36), UDim2.new(1, -24, 1, -74))
	local legend = text(content, "Legend", "", UDim2.new(0, 12, 1, -36), UDim2.new(1, -24, 0, 14), 10, FONT.mono, C.dim)
	local roomFrames: { [string]: { f: Frame, s: UIStroke } } = {}
	local termFrames: { [string]: Frame } = {}
	local here: Frame? = nil
	local builtFor = 0
	local function build(s: State)
		area:ClearAllChildren()
		table.clear(roomFrames)
		table.clear(termFrames)
		here = nil
		local e = s.extent
		if not e then
			return
		end
		local aw, ah = ctx.width - 24, ScreenFeeds.HEIGHT - 74
		local scale = math.min(aw / math.max(e[3] - e[1], 1), ah / math.max(e[4] - e[2], 1))
		local ox = (aw - (e[3] - e[1]) * scale) / 2
		local oy = (ah - (e[4] - e[2]) * scale) / 2
		local function at(x: number, z: number): (number, number)
			return ox + (x - e[1]) * scale, oy + (z - e[2]) * scale
		end
		for _, id in s.roomOrder do
			local r = s.rooms[id]
			if r.rect then
				local x0, y0 = at(r.rect[1], r.rect[2])
				local x1, y1 = at(r.rect[3], r.rect[4])
				local f = frame(area, id, UDim2.fromOffset(x0, y0), UDim2.fromOffset(math.max(x1 - x0, 2), math.max(y1 - y0, 2)), C.ink, 0.88)
				roomFrames[id] = { f = f, s = stroke(f, C.dim, 1) }
			end
		end
		for _, t in s.terminals do
			if t.pos then
				local x, y = at(t.pos.X, t.pos.Y)
				local f = frame(area, t.id, UDim2.fromOffset(x - 4, y - 4), UDim2.fromOffset(8, 8), C.merc, 0)
				f.ZIndex = 3
				termFrames[t.id] = f
			end
		end
		if ctx.pos then
			local x, y = at(ctx.pos.X, ctx.pos.Y)
			here = frame(area, "Here", UDim2.fromOffset(x - 4, y - 4), UDim2.fromOffset(8, 8), C.white, 0)
			local corner = Instance.new("UICorner")
			corner.CornerRadius = UDim.new(1, 0)
			corner.Parent = here;
			(here :: Frame).ZIndex = 4
		end
		builtFor = #s.roomOrder
	end
	return function(s)
		accent(ch, s)
		if builtFor ~= #s.roomOrder then
			build(s)
		end
		local darkCount = 0
		for id, entry in roomFrames do
			local r = s.rooms[id]
			local strokeColor, fill, fillT = C.dim, C.ink, 0.88
			if r.dark then
				darkCount += 1
				strokeColor, fill, fillT = C.faint, Color3.new(0, 0, 0), 0.2
			end
			if s.wingSecure[r.wing] then
				strokeColor = C.good
			end
			if id == s.coreRoom and s.finale then
				local pulse = blink(s, 2)
				strokeColor = if s.finale == "Upload" then C.upload else C.crit
				fill, fillT = strokeColor, if pulse then 0.6 else 0.85
			elseif s.lockdown and id == s.coreRoom then
				strokeColor = C.warn
			end
			if id == ctx.room then
				strokeColor = C.white
			end
			setFill(entry.f, fill, fillT)
			if entry.s.Color ~= strokeColor then
				entry.s.Color = strokeColor
			end
		end
		for id, f in termFrames do
			local t = s.terminalsById[id]
			if t then
				local _, color = terminalLook(t)
				setFill(f, color)
			end
		end
		if here then
			here.Visible = blink(s, 1.5)
		end
		setText(ch.right, if darkCount > 0 then string.format("%d %s DARK", darkCount, if darkCount == 1 then "ROOM" else "ROOMS") else "ALL POWERED", if darkCount > 0 then C.warn else C.dim)
		setText(legend, "WHITE: YOU ARE HERE   SQUARES: TERMINALS   GREEN: SECURED   BLACK: NO POWER")
	end
end

FEED.Graph = function(content, ctx)
	local ch = chrome(content, "NETWORK LOAD", ctx)
	local plot = frame(content, "Plot", UDim2.fromOffset(14, 40), UDim2.new(1, -28, 1, -76))
	for i = 1, 3 do
		frame(plot, "Grid", UDim2.new(0, 0, i / 4, 0), UDim2.new(1, 0, 0, 1), C.faint, 0.3)
	end
	frame(plot, "Base", UDim2.new(0, 0, 1, -1), UDim2.new(1, 0, 0, 1), C.dim, 0)
	local bars = {}
	local count = 24
	for i = 1, count do
		bars[i] = frame(plot, "Bar", UDim2.new((i - 1) / count, 1, 1, 0), UDim2.new(1 / count, -3, 0, 0), C.ink, 0.1)
		bars[i].AnchorPoint = Vector2.new(0, 1)
	end
	return function(s)
		accent(ch, s)
		setText(ch.right, string.format("LOAD %d%%", math.floor(s.load * 100)), if s.load > 0.75 then C.crit elseif s.load > 0.5 then C.warn else C.dim)
		local n = #s.activity
		for i, b in bars do
			local v = s.activity[n - count + i] or 0
			local size = UDim2.new(1 / count, -3, math.clamp(v, 0.02, 1), 0)
			if b.Size ~= size then
				b.Size = size
			end
			setFill(b, if v > 0.75 then C.crit elseif v > 0.5 then C.warn else C.ink, 0.1)
		end
	end
end

FEED.Alert = function(content, ctx)
	local back = frame(content, "Back", UDim2.new(), UDim2.fromScale(1, 1), C.bg, 0)
	local band1 = frame(content, "Band", UDim2.new(0, 0, 0, 18), UDim2.new(1, 0, 0, 6), C.faint, 0)
	local band2 = frame(content, "Band", UDim2.new(0, 0, 1, -24), UDim2.new(1, 0, 0, 6), C.faint, 0)
	local icon = text(content, "Icon", "!", UDim2.new(0.5, -22, 0, 36), UDim2.fromOffset(44, 44), 34, FONT.display, C.good, Enum.TextXAlignment.Center)
	local iconStroke = stroke(icon, C.good, 3)
	local big = text(content, "Big", "", UDim2.new(0, 10, 0, 92), UDim2.new(1, -20, 0, 40), 30, FONT.display, C.good, Enum.TextXAlignment.Center)
	local small = text(content, "Small", "", UDim2.new(0, 10, 0, 136), UDim2.new(1, -20, 0, 34), 13, FONT.mono, C.dim, Enum.TextXAlignment.Center)
	small.TextWrapped = true
	small.TextTruncate = Enum.TextTruncate.None
	local where = text(content, "Where", "", UDim2.new(0, 10, 0, 176), UDim2.new(1, -20, 0, 16), 11, FONT.mono, C.dim, Enum.TextXAlignment.Center)
	return function(s)
		local alert = (ctx.room and s.alerts[ctx.room]) or (ctx.wing and s.wingAlerts[ctx.wing]) or nil
		local room = ctx.room and s.rooms[ctx.room]
		local bigText, smallText, color, bg = "SYSTEMS NOMINAL", "THREAT LEVEL " .. s.threat, C.good, C.bg
		if s.finale == "Upload" then
			bigText, smallText, color = "CONTAINMENT FAILURE", string.format("UPLOAD %d%% · %s LEFT", math.floor(s.upload * 100), clock(s.finaleLeft)), C.upload
			bg = if blink(s, 3) then Color3.fromRGB(34, 6, 40) else C.bg
		elseif s.finale == "Purge" then
			bigText, smallText, color = "PURGE PROTOCOL", string.format("HOLD THE CORE · %d/%d S", math.floor(s.hold), s.holdNeeded), C.crit
			bg = if blink(s, 2) then Color3.fromRGB(40, 8, 8) else C.bg
		elseif s.lockdown then
			bigText, smallText, color = "LOCKDOWN", "ALL SHELL DOCKS OFFLINE", C.crit
		elseif alert and recent(alert, s.now) then
			bigText, smallText, color = "SECURITY ALERT", alert.text, C.crit
			bg = if blink(s, 4) then Color3.fromRGB(46, 10, 10) else C.bg
		elseif room and room.dark and s.phase ~= "Lobby" then
			bigText, smallText, color = "POWER FAILURE", "AUXILIARY POWER ONLY", C.warn
		elseif s.phase == "Results" then
			bigText, color = resultText(s)
			smallText = "ROUND OVER"
		elseif s.phase == "Lobby" or s.phase == "Loadout" then
			bigText, smallText, color = "STANDBY", "NO ACTIVE INCIDENT", C.dim
		elseif s.phase == "Deployment" then
			bigText, smallText, color = "INSERTION", "TEAM DEPLOYING · " .. clock(s.clock), C.merc
		end
		setText(big, bigText, color)
		setText(small, smallText, if color == C.good then C.dim else color)
		setText(icon, "!", color)
		iconStroke.Color = color
		setFill(back, bg)
		setFill(band1, if color == C.good then C.faint else color, 0.3)
		setFill(band2, if color == C.good then C.faint else color, 0.3)
		setText(where, "AXIOM SECURITY // " .. string.upper(ctx.roomName or "FACILITY"))
	end
end

FEED.Terminal = function(content, ctx)
	local ch = chrome(content, "MAINFRAME ACCESS", ctx)
	local name = text(content, "Name", "", UDim2.fromOffset(14, 36), UDim2.new(1, -28, 0, 22), 18, FONT.display, C.white)
	local pct = text(content, "Pct", "0%", UDim2.fromOffset(14, 60), UDim2.new(0.6, 0, 0, 60), 54, FONT.display, C.merc)
	local _, fill = bar(content, "Progress", UDim2.fromOffset(14, 128), UDim2.new(1, -28, 0, 14), C.merc)
	local state = text(content, "State", "", UDim2.fromOffset(14, 150), UDim2.new(1, -28, 0, 18), 14, FONT.display, C.merc)
	local hint = text(content, "Hint", "", UDim2.fromOffset(14, 172), UDim2.new(1, -28, 0, 16), 11, FONT.mono, C.dim)
	return function(s)
		accent(ch, s)
		local t = ctx.terminalId and s.terminalsById[ctx.terminalId]
		if not t then
			setText(name, "NOT LINKED")
			return
		end
		local label, color = terminalLook(t)
		setText(ch.right, t.id)
		setText(name, string.upper(t.name))
		setText(pct, string.format("%d%%", math.floor(t.progress * 100)), color)
		setBar(fill, if t.done then 1 else t.progress, color)
		setText(state, label, color)
		setText(hint, if t.done then "WING SECURE · SHELL DOCKS OFFLINE" elseif t.locked then "INTRUSION DETECTED · RETRY SHORTLY" else "HOLD [E] TO REBOOT")
	end
end

FEED.Off = function(_content, _ctx)
	return function(_s) end
end

------------------------------------------------------------------------------------------------------------

-- Draws `feed` into `gui` (clearing it) and returns a handle whose update(state) refreshes the screen.
-- Call update often (several times a second) for the blinking and noise to animate.
function ScreenFeeds.mount(gui: SurfaceGui, feed: string, ctx: Context): Handle
	gui:ClearAllChildren()
	gui.SizingMode = Enum.SurfaceGuiSizingMode.FixedSize
	gui.CanvasSize = Vector2.new(math.floor(ctx.width), ScreenFeeds.HEIGHT)
	gui.LightInfluence = 0
	local builder = FEED[feed] or FEED.Off
	local root = frame(gui, "Root", UDim2.new(), UDim2.fromScale(1, 1), C.bg, 0)
	root.ClipsDescendants = true
	local content = frame(root, "Content", UDim2.new(), UDim2.fromScale(1, 1))
	local update = builder(content, ctx)
	local glare = frame(root, "Glare", UDim2.new(), UDim2.fromScale(1, 1), Color3.new(1, 1, 1), 0)
	glare.ZIndex = 20
	local g = Instance.new("UIGradient")
	g.Rotation = 28
	g.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.93),
		NumberSequenceKeypoint.new(0.42, 0.97),
		NumberSequenceKeypoint.new(0.43, 1),
		NumberSequenceKeypoint.new(1, 1),
	})
	g.Parent = glare
	local tint = frame(root, "Glitch", UDim2.new(), UDim2.fromScale(1, 1), C.upload, 0.85)
	tint.ZIndex = 19
	tint.Visible = false
	if feed == "Off" then
		content.Visible = false
	end
	return {
		feed = feed,
		update = function(s: State)
			update(s)
			if s.glitch and feed ~= "Off" then
				local rng = Random.new(math.floor(s.now * 10) + ctx.seed)
				local on = rng:NextNumber() < 0.3
				content.Position = if on then UDim2.fromOffset(rng:NextInteger(-8, 8), rng:NextInteger(-3, 3)) else UDim2.new()
				tint.Visible = on
			elseif tint.Visible or content.Position ~= UDim2.new() then
				content.Position = UDim2.new()
				tint.Visible = false
			end
		end,
	}
end

-- A plausible mid-match state for previews. `facts` can carry the place's real rooms, terminals, cameras
-- and docks (the generator reads them from the open place); anything missing is made up.
function ScreenFeeds.sample(facts: { [string]: any }?): State
	local f = facts or {}
	local rooms: { [string]: Room } = f.rooms or {
		CORE = { id = "CORE", name = "The Core", wing = "CORE", dark = false, emergency = false, rect = { -60, -60, 60, 60 } },
		SF_RACKHALL = { id = "SF_RACKHALL", name = "Rack Hall", wing = "SF", dark = true, emergency = false, rect = { -56, -172, 56, -104 } },
		MT_BOILER = { id = "MT_BOILER", name = "Boiler Room", wing = "MT", dark = false, emergency = true, rect = { 152, -30, 212, 30 } },
		OW_CUBICLES = { id = "OW_CUBICLES", name = "Cubicle Floor", wing = "OW", dark = false, emergency = false, rect = { -190, -56, -110, 56 } },
		INSERTION = { id = "INSERTION", name = "Insertion", wing = "INSERTION", dark = false, emergency = false, rect = { -24, 60, 24, 108 } },
	}
	local order = {}
	local extent = { math.huge, math.huge, -math.huge, -math.huge }
	for id, r in rooms do
		table.insert(order, id)
		if r.rect then
			extent[1] = math.min(extent[1], r.rect[1])
			extent[2] = math.min(extent[2], r.rect[2])
			extent[3] = math.max(extent[3], r.rect[3])
			extent[4] = math.max(extent[4], r.rect[4])
		end
	end
	table.sort(order)
	local terminals: { Terminal } = f.terminals or {
		{ id = "TERM_MT", name = "Boiler Room", room = "MT_BOILER", wing = "MT", progress = 1, done = true, locked = false },
		{ id = "TERM_OW", name = "Manager's Office", room = "OW_OFFICE", wing = "OW", progress = 0.12, done = false, locked = true },
		{ id = "TERM_SF", name = "Server Farm", room = "SF_TERMINAL", wing = "SF", progress = 0.47, done = false, locked = false, operator = "Vega" },
	}
	local byId = {}
	for i, t in terminals do
		-- Show one of each state: secured, faulted, rebooting.
		if f.terminals then
			t.progress = ({ 1, 0.12, 0.47 })[(i - 1) % 3 + 1]
			t.done = i % 3 == 1
			t.locked = i % 3 == 2
			t.operator = if i % 3 == 0 then "Vega" else nil
		end
		byId[t.id] = t
	end
	local cameras: { Camera } = f.cameras or {
		{ id = "CORE_NE", name = "Core north-east", room = "CORE", broken = false },
		{ id = "SF_RACKHALL", name = "Rack Hall", room = "SF_RACKHALL", broken = false },
		{ id = "MT_BOILER", name = "Boiler Room", room = "MT_BOILER", broken = true },
	}
	local camerasById = {}
	for _, c in cameras do
		camerasById[c.id] = c
	end
	local activity = {}
	for i = 1, 32 do
		activity[i] = math.clamp(0.3 + 0.18 * math.sin(i * 0.7) + 0.12 * math.sin(i * 1.9) + (if i == 26 then 0.35 else 0), 0, 1)
	end
	return {
		now = 0.2,
		phase = "Race",
		phaseLabel = "RACE",
		clock = 192,
		clockLabel = "BREACH ELAPSED",
		threat = 2,
		upload = 0.34,
		lockdown = false,
		finale = nil,
		finaleLeft = 0,
		hold = 0,
		holdNeeded = 45,
		winner = nil,
		terminalsDone = 1,
		terminalsNeeded = 2,
		terminals = terminals,
		terminalsById = byId,
		cameras = cameras,
		camerasById = camerasById,
		rooms = rooms,
		roomOrder = order,
		extent = if extent[1] < math.huge then extent else nil,
		coreRoom = "CORE",
		wingSecure = { MT = true },
		doors = { { id = "D_SF_CORRIDOR", name = "Rack Hall door", rooms = { "SF_CORRIDOR", "SF_RACKHALL" }, locked = true, welded = false } },
		docks = f.docks or { CORE = 2, SF_RACKHALL = 1, MT_BOILER = 1, OW_CUBICLES = 1 },
		squad = {
			{ name = "Vega", class = "Technician", hp = 100, maxHp = 100, downed = false, bleedLeft = 0, eliminated = false },
			{ name = "Okafor", class = "Assault", hp = 62, maxHp = 100, downed = false, bleedLeft = 0, eliminated = false },
			{ name = "Lindqvist", class = "Medic", hp = 0, maxHp = 100, downed = true, bleedLeft = 23, eliminated = false },
			{ name = "Reyes", class = "Scout", hp = 0, maxHp = 100, downed = false, bleedLeft = 0, eliminated = true },
		},
		log = {
			{ stamp = "00:41", text = "REBOOT STARTED · BOILER ROOM", level = "info" },
			{ stamp = "01:12", text = "DOOR SEALED · RACK HALL DOOR", level = "warn" },
			{ stamp = "01:30", text = "TERMINAL SECURED · BOILER ROOM", level = "good" },
			{ stamp = "01:31", text = "EMERGENCY POWER · WING MT", level = "warn" },
			{ stamp = "02:05", text = "CAMERA OFFLINE · BOILER ROOM", level = "warn" },
			{ stamp = "02:20", text = "THREAT LEVEL 2", level = "warn" },
			{ stamp = "02:48", text = "TERMINAL FAULT · MANAGER'S OFFICE", level = "crit" },
			{ stamp = "03:02", text = "VITALS CRITICAL · LINDQVIST", level = "crit" },
			{ stamp = "03:09", text = "POWER FAILURE · RACK HALL", level = "crit" },
		},
		alerts = { SF_RACKHALL = { text = "POWER FAILURE · RACK HALL", at = 0 } },
		wingAlerts = {},
		activity = activity,
		load = 0.46,
		glitch = false,
	}
end

return ScreenFeeds
