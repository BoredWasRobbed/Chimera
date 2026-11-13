-- The finales, both played at the Core. The side that triggered one must hold the Core platform for 45 s
-- in total within two minutes; the other side stalls it by being anywhere in the Core.
--   Purge  (mercs rebooted enough terminals: Lockdown). Standing mercs on the platform hold; the
--          Chimera's body anywhere in the Core stalls. The Chimera is mortal: destroying its body ends the
--          match. The Core is floodlit (Blackout doesn't work there) and a scan pulse Reveals the Chimera
--          every 15 s. If time runs out, the Chimera wins.
--   Upload (the meter reached 100%). The Chimera's body on the platform holds; any standing merc in the
--          Core stalls. The Chimera takes a new shell at a Core dock 10 s after losing one, and each loss
--          costs 5 s of held time. Every light in the Core dies, and every 15 s a network scan shows the
--          Chimera every merc inside the Core. If time runs out, the mercs win.
-- In both, a body doesn't drain energy and the Chimera can't leave it; a bodiless Chimera boots a shell
-- at a Core dock 5 s after the finale starts.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local FacilityMap = require(ReplicatedStorage.Shared.FacilityMap)
local Net = require(ReplicatedStorage.Shared.Net)
local Chimera = require(script.Parent.Chimera)
local Cues = require(script.Parent.Cues)
local Health = require(script.Parent.Health)
local Lights = require(script.Parent.Lights)
local MapData = require(script.Parent.MapData)
local MatchState = require(script.Parent.MatchState)
local ShellCombat = require(script.Parent.ShellCombat)

local Finale = {}

local F = Config.Finale

type State = {
	kind: "Purge" | "Upload",
	endsAt: number,
	held: number,
	holdState: string,
	nextScanAt: number,
	bootAt: number?,
	over: boolean,
}

local state: State? = nil
local coreRoom: string? = nil
local platform: BasePart? = nil
local feed: RemoteEvent
local getAgent: () -> any = function()
	return nil
end
local finish: (string, string) -> () = function() end

local function inCore(position: Vector3): boolean
	local room = coreRoom and MapData.rooms[coreRoom]
	return room ~= nil and FacilityMap.inBox(room.bounds, position)
end

local function onPlatform(position: Vector3): boolean
	return platform ~= nil and FacilityMap.inBox(platform, position)
end

-- Mercs standing (not downed): player characters and Studio dummies alike.
local function standingBodies(): { Health.Body }
	local out = {}
	for _, body in Health.all() do
		if not body.eliminated and not body.downed and body.root.Parent then
			table.insert(out, body)
		end
	end
	return out
end

-- The Core dock farthest from the nearest merc.
local function safestCoreDock(): string?
	local best, bestDistance = nil, -1
	for id, dock in MapData.docks do
		if dock.room == coreRoom then
			local nearest = math.huge
			for _, body in standingBodies() do
				nearest = math.min(nearest, (body.root.Position - dock.spawn.Position).Magnitude)
			end
			if nearest > bestDistance then
				best, bestDistance = id, nearest
			end
		end
	end
	return best
end

local function body(agent: any): any
	local shell = agent and agent.shell
	return if shell and not shell.dead then shell else nil
end

local function over(winner: string, reason: string)
	local s = state
	if not s or s.over then
		return
	end
	s.over = true
	task.spawn(finish, winner, reason)
end

local function publish(s: State)
	MatchState.publish("Hold", math.floor(s.held * 10) / 10)
	MatchState.publish("HoldState", s.holdState)
end

local function scan(s: State, agent: any)
	local core = coreRoom and MapData.rooms[coreRoom]
	local center = if core then core.bounds.Position else Vector3.zero
	if s.kind == "Purge" then
		local shell = body(agent)
		if shell then
			ShellCombat.reveal(shell, F.ScanRevealSeconds)
		end
		Cues.emit("ScanPulse", center, 2000)
		feed:FireAllClients("notice", "Scan pulse: the Chimera is Revealed")
	elseif agent then
		local names = {}
		for _, b in Health.all() do
			if not b.eliminated and inCore(b.root.Position) then
				table.insert(names, b.model.Name)
			end
		end
		Chimera.notify(agent, { type = "scan", targets = names, seconds = F.ScanShowSeconds })
	end
end

function Finale.active(): ("Purge" | "Upload")?
	return if state then state.kind else nil
end

function Finale.held(): number
	return if state then state.held else 0
end

-- endsAt is os.clock() time (two minutes, cut short by the match's 10:00 cap).
function Finale.start(kind: "Purge" | "Upload", endsAt: number)
	local now = os.clock()
	local s: State = {
		kind = kind,
		endsAt = endsAt,
		held = 0,
		holdState = "open",
		nextScanAt = now + F.ScanSeconds,
		bootAt = nil,
		over = false,
	}
	state = s
	if kind == "Purge" then
		Lights.setFloodlights(true)
	elseif coreRoom then
		Lights.cutPower(coreRoom)
	end
	local agent = getAgent()
	if agent and not body(agent) then
		s.bootAt = now + F.BootSeconds
		Chimera.notify(agent, { type = "toast", text = string.format("Booting your last shell at the Core in %d s", F.BootSeconds) })
	end
	publish(s)
end

function Finale.stop()
	state = nil
	for _, agent in Chimera.agents() do
		Chimera.setLocked(agent, false)
	end
	MatchState.publish("Hold", 0)
	MatchState.publish("HoldState", nil)
end

-- Studio: add held time, or move the end of the finale.
function Finale.addHold(seconds: number)
	if state then
		state.held = math.clamp(state.held + seconds, 0, F.HoldSeconds)
		publish(state)
	end
end

function Finale.shiftEnd(seconds: number)
	if state then
		state.endsAt += seconds
	end
end

function Finale.endsAt(): number?
	return if state then state.endsAt else nil
end

function Finale.tick(dt: number)
	local s = state
	if not s or s.over then
		return
	end
	local now = os.clock()
	local agent = getAgent()

	if s.bootAt and now >= s.bootAt then
		s.bootAt = nil
		local dockId = safestCoreDock()
		if agent and not body(agent) and dockId then
			Chimera.forceBody(agent, dockId)
		end
	end
	if agent and body(agent) and not agent.locked then
		Chimera.setLocked(agent, true)
	end

	local shell = body(agent)
	local holders, stallers = false, false
	if s.kind == "Purge" then
		for _, b in standingBodies() do
			if onPlatform(b.root.Position) then
				holders = true
				break
			end
		end
		stallers = shell ~= nil and inCore(shell.state.pos + Vector3.new(0, 1, 0))
	else
		holders = shell ~= nil and onPlatform(shell.state.pos + Vector3.new(0, 1, 0))
		for _, b in standingBodies() do
			if inCore(b.root.Position) then
				stallers = true
				break
			end
		end
	end
	if holders and not stallers then
		s.held = math.min(F.HoldSeconds, s.held + dt)
		s.holdState = "holding"
	elseif holders then
		s.holdState = "stalled"
	else
		s.holdState = "open"
	end
	publish(s)

	if now >= s.nextScanAt then
		s.nextScanAt += F.ScanSeconds
		scan(s, agent)
	end

	if s.held >= F.HoldSeconds then
		if s.kind == "Purge" then
			over("Mercs", "Purge complete: the mercs held the Core")
		else
			over("Chimera", "Upload complete: the Chimera held the Core")
		end
	elseif now >= s.endsAt then
		if s.kind == "Purge" then
			over("Chimera", "Time ran out before the purge finished")
		else
			over("Mercs", "Time ran out before the upload finished")
		end
	end
end

-- getChimera() returns the match's Chimera agent; done(winner, reason) ends the match.
function Finale.init(getChimera: () -> any, done: (string, string) -> ())
	getAgent, finish = getChimera, done
	feed = Net.get("MatchFeed")
	coreRoom, platform = FacilityMap.core(MapData.rooms)
	if not platform then
		warn("[Chimera] map check: no Facility.Core.Platform; the finales can't be held")
	end
	Chimera.onBodyLost(function(agent, reason)
		local s = state
		if not s or s.over or agent ~= getAgent() then
			return
		end
		if s.kind == "Purge" then
			over("Mercs", if reason == "destroyed" then "The Chimera's last body was destroyed" else "The Chimera's last body was lost")
		else
			s.held = math.max(0, s.held - F.UploadLossSeconds)
			s.bootAt = os.clock() + F.UploadRespawnSeconds
			publish(s)
			Chimera.notify(agent, { type = "toast", text = string.format("Body lost: -%d s of upload. New shell at the Core in %d s", F.UploadLossSeconds, F.UploadRespawnSeconds) })
			feed:FireAllClients("notice", string.format("Chimera body destroyed: upload set back %d s", F.UploadLossSeconds))
		end
	end)
end

return Finale
