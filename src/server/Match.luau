-- One full match, round after round:
--   Lobby (20 s)       Chimera Chance picks the AI: each player's weight starts at 1, gains 1 for every
--                      round played as a merc and resets when they're picked. Merc only opts out. A round
--                      needs at least 4 players (Studio: 1, see the DEV panel).
--   Loadout (25 s)     mercs pick a class within the slice caps; the Chimera keeps the default build.
--   Deployment (15 s)  mercs enter at the Insertion lift. The Chimera boots in the network: it can hop
--                      cameras but can't use Interface or take a shell yet. Each merc short of five makes
--                      reboots 10% faster and shells 10% weaker.
--   Race (up to 8:00)  terminals against the upload meter. Rebooting 2 terminals triggers Lockdown and
--                      the Purge finale; a full meter (or 8:00) triggers the Upload finale. Threat Level
--                      rises at 2:00, 4:00 and 6:00.
--   Finale (2:00)      see Finale. The match never runs past 10:00 from the start of the race.
--   Results            then back to the Lobby.
-- At any point the Chimera wins by eliminating every merc, and the mercs win if the Chimera leaves.
-- A merc who leaves is removed and gives no upload. 45 s idle in a match sends a player to the lobby
-- (an idle Chimera at deployment is re-picked instead).
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)
local FacilityMap = require(ReplicatedStorage.Shared.FacilityMap)
local Net = require(ReplicatedStorage.Shared.Net)
local Chimera = require(script.Parent.Chimera)
local Cues = require(script.Parent.Cues)
local Decoys = require(script.Parent.Decoys)
local Docks = require(script.Parent.Docks)
local Doors = require(script.Parent.Doors)
local Finale = require(script.Parent.Finale)
local Gear = require(script.Parent.Gear)
local Health = require(script.Parent.Health)
local Lights = require(script.Parent.Lights)
local MapData = require(script.Parent.MapData)
local MatchState = require(script.Parent.MatchState)
local Pings = require(script.Parent.Pings)
local Roles = require(script.Parent.Roles)
local SecurityCameras = require(script.Parent.SecurityCameras)
local Terminals = require(script.Parent.Terminals)
local Traps = require(script.Parent.Traps)
local Upload = require(script.Parent.Upload)

local Match = {}

local M = Config.Match
local IS_STUDIO = RunService:IsStudio()

local phaseEndsAt = 0 -- os.clock(); 0 while the lobby waits for players
local raceStartedAt = 0
local matchStartedAt = 0 -- the start of Deployment, for idle checks
local mercsAtDeploy = 0
local chimeraDeployed = false
local chimeraIdled = false
local lastActive: { [Player]: number } = {}
local tokens: { [Player]: number } = {}
local checkAccumulator = 0
local wingRooms: { [string]: { [string]: boolean } } = {}
local feed: RemoteEvent
local rng = Random.new()
-- Studio testing: one player is enough to start, and idle players aren't sent to the lobby (a second
-- test client sits idle while you play the first). The DEV panel switches both back to the real rules.
local studio = { minPlayers = IS_STUDIO, afk = not IS_STUDIO, keepGoing = false } -- keepGoing (hook only): no "every merc eliminated" win, for solo Overwatch tests

local function serverTime(clockTime: number): number
	return workspace:GetServerTimeNow() + (clockTime - os.clock())
end

local function notice(text: string)
	feed:FireAllClients("notice", text)
end

local function setPhase(phase: MatchState.Phase, seconds: number?)
	MatchState.phase = phase
	phaseEndsAt = if seconds then os.clock() + seconds else 0
	MatchState.publish("Phase", phase)
	MatchState.publish("PhaseEndsAt", if seconds then serverTime(phaseEndsAt) else 0)
	if IS_STUDIO then
		print(`[Chimera] match phase: {phase}`)
	end
end

local function setThreat(level: number)
	if MatchState.threat ~= level then
		MatchState.threat = level
		MatchState.publish("Threat", level)
		if level > 1 then
			Chimera.alertAll(`Threat Level {level}: faster energy, shorter cooldowns`)
		end
	end
end

local function weightOf(player: Player): number
	return player:GetAttribute("ChimeraWeight") or 1
end

local function withTeam(team: string): { Player }
	local out = {}
	for _, player in Players:GetPlayers() do
		if player:GetAttribute("Team") == team then
			table.insert(out, player)
		end
	end
	return out
end

local function mercPlayers(): { Player }
	local out = {}
	for _, player in Players:GetPlayers() do
		if player:GetAttribute("Role") == "Merc" then
			table.insert(out, player)
		end
	end
	return out
end

local function minPlayers(): number
	return if studio.minPlayers then 1 else M.MinPlayers
end

-- The match's Chimera: the Chimera player's agent, or in Studio the DEV test shell's.
local function chimeraAgent(): any
	local player = Roles.chimera()
	if player then
		return Chimera.agentOf(player)
	end
	if IS_STUDIO then
		for _, agent in Chimera.agents() do
			if not agent.player then
				return agent
			end
		end
	end
	return nil
end

-- Weighted by Chimera Chance, skipping Merc only players. With nobody eligible: a mercs-only test round
-- in Studio (the DEV test shell can play the Chimera), otherwise anyone.
local function pickChimera(candidates: { Player }): Player?
	local pool = {}
	for _, player in candidates do
		if not player:GetAttribute("MercOnly") then
			table.insert(pool, player)
		end
	end
	if #pool == 0 then
		if IS_STUDIO and studio.minPlayers then
			return nil
		end
		pool = candidates
	end
	if #pool == 0 then
		return nil
	end
	local total = 0
	for _, player in pool do
		total += weightOf(player)
	end
	local roll = rng:NextNumber() * total
	for _, player in pool do
		roll -= weightOf(player)
		if roll <= 0 then
			return player
		end
	end
	return pool[#pool]
end

local function makeChimera(player: Player)
	player:SetAttribute("Team", "Chimera")
	player:SetAttribute("Class", nil)
	player:SetAttribute("ChimeraWeight", 1)
end

local function resetWorld()
	Finale.stop()
	Upload.reset()
	Chimera.clear()
	Terminals.reset()
	Docks.reset()
	Doors.reset()
	Lights.reset()
	SecurityCameras.reset()
	Traps.reset()
	Decoys.clear()
	Gear.clear()
	Health.resetDownCounts()
	Health.clearDummies()
	Pings.reset()
	MatchState.finale = nil
	MatchState.lockdown = false
	MatchState.missingMercs = 0
	setThreat(1)
	raceStartedAt = 0
	chimeraDeployed = false
	chimeraIdled = false
	mercsAtDeploy = 0
	for name, value in {
		Finale = false,
		FinaleEndsAt = 0,
		Lockdown = false,
		Threat = 1,
		Hold = 0,
		TerminalsDone = 0,
		RaceStartedAt = 0,
		MissingMercs = 0,
		Winner = false,
		WinReason = false,
		MatchSeconds = 0,
	} do
		MatchState.publish(name, if value == false then nil else value)
	end
	MatchState.publish("HoldState", nil)
end

local function enterLobby()
	resetWorld()
	for _, player in Players:GetPlayers() do
		Roles.assign(player, "Lobby")
		player:SetAttribute("Team", nil)
	end
	setPhase("Lobby")
	MatchState.publish("Waiting", true)
end

local function enterLoadout()
	local players = Players:GetPlayers()
	local chimera = pickChimera(players)
	if chimera then
		makeChimera(chimera)
	end
	local mercs = 0
	for _, player in players do
		if player ~= chimera then
			if mercs < M.MaxMercs then
				mercs += 1
				player:SetAttribute("Team", "Merc")
				player:SetAttribute("Class", nil)
				player:SetAttribute("Class", Roles.pickClass(player))
			else
				player:SetAttribute("Team", "Spectator")
			end
		end
	end
	MatchState.publish("Waiting", false)
	setPhase("Loadout", M.LoadoutSeconds)
end

local function enterDeployment()
	local now = os.clock()
	-- An idle Chimera at deployment is re-picked.
	local picked = withTeam("Chimera")[1]
	if picked and studio.afk and now - (lastActive[picked] or 0) >= M.IdleSeconds then
		picked:SetAttribute("Team", "Spectator")
		feed:FireClient(picked, "notice", "You were idle, so another player was picked as the Chimera")
		local replacement = pickChimera(withTeam("Merc"))
		if replacement then
			makeChimera(replacement)
		end
	end

	matchStartedAt = now
	mercsAtDeploy = 0
	chimeraDeployed = false
	for _, player in Players:GetPlayers() do
		local team = player:GetAttribute("Team")
		if team == "Chimera" then
			chimeraDeployed = true
			Roles.setRole(player, "Chimera")
		elseif team == "Merc" then
			mercsAtDeploy += 1
			Roles.setRole(player, "Merc", player:GetAttribute("Class"))
		else
			player:SetAttribute("Team", "Spectator")
			Roles.assign(player, "Spectator")
		end
	end
	MatchState.missingMercs = math.max(0, M.MaxMercs - mercsAtDeploy)
	MatchState.publish("MissingMercs", MatchState.missingMercs)
	setPhase("Deployment", M.DeploymentSeconds)
end

local function enterRace()
	raceStartedAt = os.clock()
	MatchState.publish("RaceStartedAt", serverTime(raceStartedAt))
	setPhase("Race", M.RaceSeconds)
	Upload.start()
	setThreat(1)
	notice("The race is on: reboot the terminals")
	Chimera.alertAll("Interface online: the race is on")
end

local function lockdown()
	MatchState.lockdown = true
	MatchState.publish("Lockdown", true)
	for id in MapData.docks do
		Docks.shutDown(id)
	end
	local room = MatchState.coreRoom and MapData.rooms[MatchState.coreRoom]
	Cues.emit("LockdownAlarm", if room then room.bounds.Position else Vector3.zero, 2000)
	Chimera.alertAll("LOCKDOWN: every dock is shut down and you're locked into one body")
end

local function startFinale(kind: "Purge" | "Upload")
	if MatchState.phase ~= "Race" then
		return
	end
	Upload.stop()
	if kind == "Purge" then
		lockdown()
	else
		Upload.set(1)
	end
	local now = os.clock()
	local endsAt = math.min(now + M.FinaleSeconds, raceStartedAt + M.HardCapSeconds)
	MatchState.finale = kind
	setThreat(Config.Threat.Max)
	setPhase("Finale", endsAt - now)
	MatchState.publish("Finale", kind)
	MatchState.publish("FinaleEndsAt", serverTime(endsAt))
	Finale.start(kind, endsAt)
	if kind == "Purge" then
		notice("LOCKDOWN. Purge finale: hold the Core platform for 45 s")
		Chimera.alertAll("Purge finale: stall them anywhere in the Core. Your body is mortal")
	else
		notice("Upload finale: get into the Core and stall the upload")
		Chimera.alertAll("Upload finale: hold the Core platform for 45 s")
	end
end

local function endMatch(winner: string, reason: string)
	local phase = MatchState.phase
	if phase == "Lobby" or phase == "Results" then
		return
	end
	Upload.stop()
	Finale.stop()
	local seconds = if raceStartedAt > 0 then os.clock() - raceStartedAt else 0
	MatchState.publish("Winner", winner)
	MatchState.publish("WinReason", reason)
	MatchState.publish("MatchSeconds", math.floor(seconds))
	MatchState.publish("Finale", nil)
	MatchState.finale = nil
	-- Chimera Chance: everyone who played this round as a merc gains 1.
	for _, player in withTeam("Merc") do
		player:SetAttribute("ChimeraWeight", weightOf(player) + 1)
	end
	for _, player in Players:GetPlayers() do
		Roles.assign(player, "Lobby")
	end
	Chimera.clear()
	setPhase("Results", M.ResultsSeconds)
	if IS_STUDIO then
		print(`[Chimera] match over: {winner} win ({reason}) after {math.floor(seconds)} s`)
	end
end

local function onTerminalDone(id: string, wing: string)
	for _, dockId in Docks.inRooms(wingRooms[wing] or {}) do
		Docks.shutDown(dockId)
	end
	Lights.setEmergency(wing, true)
	local done = Terminals.doneCount()
	MatchState.publish("TerminalsDone", done)
	local name = MapData.terminals[id].displayName
	notice(`{name} rebooted: emergency lights on, the wing's docks shut down ({done}/{Config.Terminals.ForLockdown})`)
	Chimera.alertAll(`{name} rebooted: that wing's docks are shut down`)
	if done >= Config.Terminals.ForLockdown then
		startFinale("Purge")
	end
end

local function onRebootStarted(id: string)
	local terminal = MapData.terminals[id]
	local room = MapData.rooms[terminal.room]
	Chimera.alertAll(`Reboot started: {terminal.displayName} ({if room then room.displayName else terminal.room})`, { terminalId = id })
end

local function sendToLobby(player: Player)
	if player:GetAttribute("Role") == "Chimera" then
		chimeraIdled = true
	end
	player:SetAttribute("Team", "Spectator")
	Roles.assign(player, "Spectator")
	feed:FireClient(player, "notice", `Idle for {M.IdleSeconds} s: you're out until the next round`)
end

-- Win checks, leavers and idle players: twice a second during Deployment, the race and the finale.
local function checkPlayers()
	local now = os.clock()
	if studio.afk then
		for _, player in Players:GetPlayers() do
			local role = player:GetAttribute("Role")
			local playing = role == "Chimera" or (role == "Merc" and not player:GetAttribute("Eliminated"))
			if playing and now - math.max(lastActive[player] or 0, matchStartedAt) >= M.IdleSeconds then
				sendToLobby(player)
			end
		end
	end
	if chimeraDeployed then
		local present = false
		for _, player in Players:GetPlayers() do
			if player:GetAttribute("Role") == "Chimera" then
				present = true
				break
			end
		end
		if not present then
			endMatch("Mercs", if chimeraIdled then "The Chimera went idle" else "The Chimera left")
			return
		end
	end
	if mercsAtDeploy > 0 and not studio.keepGoing then
		local mercs = mercPlayers()
		local standing = 0
		for _, player in mercs do
			if not player:GetAttribute("Eliminated") then
				standing += 1
			end
		end
		if standing == 0 then
			endMatch("Chimera", if #mercs == 0 then "Every merc left" else "Every merc was eliminated")
		end
	end
end

local function lobbyTick(now: number)
	local count = #Players:GetPlayers()
	local needed = minPlayers()
	MatchState.publish("PlayerCount", count)
	MatchState.publish("PlayersNeeded", needed)
	if count < needed then
		if phaseEndsAt ~= 0 then
			phaseEndsAt = 0
			MatchState.publish("PhaseEndsAt", 0)
		end
		MatchState.publish("Waiting", true)
		return
	end
	MatchState.publish("Waiting", false)
	if phaseEndsAt == 0 then
		phaseEndsAt = now + M.LobbySeconds
		MatchState.publish("PhaseEndsAt", serverTime(phaseEndsAt))
	elseif now >= phaseEndsAt then
		enterLoadout()
	end
end

local function raceTick(dt: number, now: number)
	local elapsed = now - raceStartedAt
	local threat = 1
	for _, at in Config.Threat.RisesAt do
		if elapsed >= at then
			threat += 1
		end
	end
	setThreat(math.min(threat, Config.Threat.Max))
	Upload.tick(dt)
	if MatchState.phase == "Race" and elapsed >= M.RaceSeconds then
		-- The meter is built to fill by 8:00, so the race never runs longer.
		startFinale("Upload")
	end
end

function Match.tick(dt: number)
	local now = os.clock()
	local phase = MatchState.phase
	if phase == "Lobby" then
		lobbyTick(now)
	elseif phase == "Loadout" then
		if now >= phaseEndsAt then
			enterDeployment()
		end
	elseif phase == "Deployment" then
		if now >= phaseEndsAt then
			enterRace()
		end
	elseif phase == "Race" then
		raceTick(dt, now)
	elseif phase == "Finale" then
		Finale.tick(dt)
	elseif phase == "Results" then
		if now >= phaseEndsAt then
			enterLobby()
		end
	end
	phase = MatchState.phase
	if phase == "Deployment" or phase == "Race" or phase == "Finale" then
		checkAccumulator += dt
		if checkAccumulator >= 0.5 then
			checkAccumulator = 0
			checkPlayers()
		end
	end
	Pings.tick(dt)
end

local function pickClass(player: Player, class: any)
	if MatchState.phase ~= "Loadout" or player:GetAttribute("Team") ~= "Merc" or type(class) ~= "string" or not Config.Classes[class] then
		return
	end
	if player:GetAttribute("Class") == class then
		return
	end
	local counts = Roles.classCounts(player)
	if (counts[class] or 0) >= Config.Classes[class].Cap then
		feed:FireClient(player, "notice", `{class} is full`)
		return
	end
	player:SetAttribute("Class", class)
end

local function onAction(player: Player, kind: any, a: any, b: any)
	local now = os.clock()
	tokens[player] = math.min(20, (tokens[player] or 20) + (now - (lastActive[player] or now)) * 10)
	lastActive[player] = now
	if tokens[player] < 1 then
		return
	end
	tokens[player] -= 1
	if kind == "mercOnly" then
		player:SetAttribute("MercOnly", if a == true then true else nil)
	elseif kind == "class" then
		pickClass(player, a)
	elseif kind == "ping" then
		Pings.merc(player, a, b)
	elseif kind == "owPing" then
		Pings.overwatchPing(player, a)
	elseif kind == "owTag" then
		Pings.tag(player)
	elseif kind == "spectate" then
		Roles.spectate(player, a)
	end
	-- "active": recent input, nothing else to do.
end

local function playerJoined(player: Player)
	lastActive[player] = os.clock()
	if player:GetAttribute("ChimeraWeight") == nil then
		player:SetAttribute("ChimeraWeight", 1)
	end
	if MatchState.phase == "Lobby" then
		Roles.assign(player, "Lobby")
	else
		-- Players who join mid-match spectate until the next round.
		player:SetAttribute("Team", "Spectator")
		Roles.assign(player, "Spectator")
	end
end

local function playerLeft(player: Player)
	lastActive[player] = nil
	tokens[player] = nil
	-- A Chimera who leaves before deployment is simply re-picked.
	if MatchState.phase == "Loadout" and player:GetAttribute("Team") == "Chimera" then
		local others = {}
		for _, other in withTeam("Merc") do
			if other ~= player then
				table.insert(others, other)
			end
		end
		local replacement = pickChimera(others)
		if replacement then
			makeChimera(replacement)
			feed:FireClient(replacement, "notice", "The Chimera left: you're the Chimera now")
		end
	end
end

-- Studio controls (the DEV panel and ChimeraTestHook).

function Match.skipPhase(): string
	local phase = MatchState.phase
	if phase == "Lobby" then
		enterLoadout()
	elseif phase == "Loadout" then
		enterDeployment()
	elseif phase == "Deployment" then
		enterRace()
	elseif phase == "Race" then
		startFinale("Upload")
	elseif phase == "Finale" then
		Finale.shiftEnd(-1e6)
	elseif phase == "Results" then
		enterLobby()
	end
	return `skipped {phase}`
end

-- Move the clock forward: the race clock in the race, the finale's end in a finale.
function Match.addTime(seconds: number): string
	if MatchState.phase == "Race" then
		raceStartedAt -= seconds
		MatchState.publish("RaceStartedAt", serverTime(raceStartedAt))
		phaseEndsAt = raceStartedAt + M.RaceSeconds
		MatchState.publish("PhaseEndsAt", serverTime(phaseEndsAt))
		return string.format("race clock %d:%02d", (os.clock() - raceStartedAt) // 60, math.floor(os.clock() - raceStartedAt) % 60)
	elseif MatchState.phase == "Finale" then
		Finale.shiftEnd(-seconds)
		local endsAt = Finale.endsAt() or os.clock()
		phaseEndsAt = endsAt
		MatchState.publish("PhaseEndsAt", serverTime(endsAt))
		MatchState.publish("FinaleEndsAt", serverTime(endsAt))
		return "finale clock moved"
	end
	return "the clock only runs in the race and the finale"
end

function Match.setUpload(value: number): string
	Upload.set(value)
	return string.format("upload %d%%", math.round(Upload.get() * 100))
end

-- Get to the race if needed, then start a finale.
function Match.forceFinale(kind: "Purge" | "Upload"): string
	local guard = 0
	while MatchState.phase ~= "Race" and guard < 6 do
		guard += 1
		if MatchState.phase == "Finale" or MatchState.phase == "Results" then
			return "a finale is already running"
		end
		Match.skipPhase()
	end
	startFinale(kind)
	return `{kind} finale`
end

function Match.setStudioOption(name: string, value: boolean): string
	if name == "minPlayers" then
		studio.minPlayers = value
	elseif name == "afk" then
		studio.afk = value
	elseif name == "keepGoing" then
		studio.keepGoing = value
		return if value then "the match keeps going with every merc eliminated" else "every merc eliminated ends the match"
	end
	MatchState.publish("StudioMinPlayers", studio.minPlayers)
	MatchState.publish("StudioAfk", studio.afk)
	return if name == "minPlayers"
		then (if value then "a round starts with 1 player" else `a round needs {M.MinPlayers} players`)
		else (if value then "idle players are sent to the lobby" else "idle kicks off")
end

function Match.studioOption(name: string): boolean
	return studio[name] == true
end

-- Pretend this player has been idle for `seconds`.
function Match.setIdle(player: Player, seconds: number)
	lastActive[player] = os.clock() - seconds
	matchStartedAt = math.min(matchStartedAt, os.clock() - seconds)
end

function Match.endMatch(winner: string, reason: string)
	endMatch(winner, reason)
end

-- A MatchAction as if the player's client sent it.
function Match.action(player: Player, kind: any, a: any, b: any)
	onAction(player, kind, a, b)
end

function Match.chimeraAgent(): any
	return chimeraAgent()
end

function Match.describe(): { [string]: any }
	local now = os.clock()
	return {
		phase = MatchState.phase,
		phaseLeft = if phaseEndsAt > 0 then math.max(0, phaseEndsAt - now) else nil,
		raceClock = if raceStartedAt > 0 then now - raceStartedAt else nil,
		upload = Upload.get(),
		threat = MatchState.threat,
		finale = MatchState.finale,
		held = Finale.held(),
		holdState = MatchState.read("HoldState"),
		lockdown = MatchState.lockdown,
		terminalsDone = Terminals.doneCount(),
		missingMercs = MatchState.missingMercs,
		mercsAtDeploy = mercsAtDeploy,
		winner = MatchState.read("Winner"),
		reason = MatchState.read("WinReason"),
		studio = table.clone(studio),
	}
end

function Match.init()
	feed = Net.get("MatchFeed")
	MatchState.coreRoom = FacilityMap.core(MapData.rooms)
	for id, room in MapData.rooms do
		wingRooms[room.wing] = wingRooms[room.wing] or {}
		wingRooms[room.wing][id] = true
	end
	MatchState.publish("TerminalsNeeded", Config.Terminals.ForLockdown)
	Match.setStudioOption("minPlayers", studio.minPlayers)
	Terminals.init(onTerminalDone, onRebootStarted)
	Upload.init(function()
		startFinale("Upload")
	end)
	Finale.init(chimeraAgent, endMatch)
	Pings.init()
	Net.get("MatchAction").OnServerEvent:Connect(onAction)
	Players.PlayerAdded:Connect(playerJoined)
	Players.PlayerRemoving:Connect(playerLeft)
	enterLobby()
	for _, player in Players:GetPlayers() do
		playerJoined(player)
	end
end

return Match
