-- Active shells and their server-authoritative movement. A shell is not a replicated character: it's a
-- position the server simulates from its driver's inputs with the shared ShellMotor. The Chimera's client
-- sends inputs and predicts locally; the server consumes at most one input per tick (so sending more
-- inputs can't make a shell faster), sends the owner its authoritative state, and Perception decides
-- which mercs hear about it at all.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Net = require(ReplicatedStorage.Shared.Net)
local ShellMotor = require(ReplicatedStorage.Shared.ShellMotor)
local MatchState = require(script.Parent.MatchState)

export type Visibility = "Cloaked" | "Exposed" | "Revealed"

export type QueuedInput = { seq: number, mx: number, mz: number, jump: boolean, yaw: number }

export type Shell = {
	id: string,
	nonce: number,
	owner: any,
	player: Player?,
	brain: ((any, number) -> ShellMotor.Input)?,
	state: ShellMotor.State,
	yaw: number,
	visibility: Visibility,
	buffer: { QueuedInput },
	lastSeq: number,
	lastInput: ShellMotor.Input,
	lastInputAt: number,
	debt: number,
	dockId: string?,
	bornAt: number, -- server time it was taken: clients time the panels locking into place from it
	-- Combat state, driven by ShellCombat.
	hp: number,
	maxHp: number,
	dead: boolean,
	revealedUntil: number,
	taggedUntil: number, -- an Overwatch Tag outlines the shell for living mercs until then
	staggerUntil: number,
	slowScale: number,
	slowUntil: number,
	speedScale: number,
	exposed: boolean,
	forcedVisibility: Visibility?,
	attackReadyAt: number,
	leapReadyAt: number,
	assimilating: any?,
	leap: any?,
	anim: { kind: string, startedAt: number, seconds: number }?,
	epoch: number, -- bumps on teleports, so viewers don't slide the body across the map
	history: { { t: number, pos: Vector3 } },
	statusKey: string,
	statusSentAt: number,
}

local Shells = {}

local S = Config.Shell
local TWO_PI = 2 * math.pi

local shells: { [string]: Shell } = {}
local byPlayer: { [Player]: Shell } = {}
local nextNonce = 0
local removedListeners: { (Shell, string) -> () } = {}
local fellListeners: { (Shell) -> () } = {}
local authRemote: UnreliableRemoteEvent

local function finite(x: any): boolean
	return type(x) == "number" and x == x and x ~= math.huge and x ~= -math.huge
end

function Shells.onRemoved(listener: (Shell, string) -> ())
	table.insert(removedListeners, listener)
end

function Shells.onFell(listener: (Shell) -> ())
	table.insert(fellListeners, listener)
end

function Shells.all(): { [string]: Shell }
	return shells
end

function Shells.ofPlayer(player: Player): Shell?
	return byPlayer[player]
end

function Shells.feetPositions(): { Vector3 }
	local out = {}
	for _, shell in shells do
		table.insert(out, shell.state.pos)
	end
	return out
end

-- `feet` is the dock's spawn marker: the shell's feet, facing out of the dock.
function Shells.spawn(owner: any, player: Player?, feet: CFrame, dockId: string?): Shell
	nextNonce += 1
	local look = feet.LookVector
	local yaw = math.atan2(-look.X, -look.Z)
	-- Phase Weave's 1,000 HP, 10% less for each merc short of five.
	local hp = math.round(Config.Modules.PhaseWeave.HP * MatchState.shellHpScale())
	local shell: Shell = {
		id = `S{nextNonce}`,
		nonce = nextNonce,
		owner = owner,
		player = player,
		brain = nil,
		state = ShellMotor.new(feet.Position),
		yaw = yaw,
		visibility = "Cloaked",
		buffer = {},
		lastSeq = 0,
		lastInput = { mx = 0, mz = 0, jump = false, yaw = yaw },
		lastInputAt = os.clock(),
		debt = 0,
		dockId = dockId,
		bornAt = workspace:GetServerTimeNow(),
		hp = hp,
		maxHp = hp,
		dead = false,
		revealedUntil = 0,
		taggedUntil = 0,
		staggerUntil = 0,
		slowScale = 1,
		slowUntil = 0,
		speedScale = 1,
		exposed = false,
		forcedVisibility = nil,
		attackReadyAt = 0,
		leapReadyAt = 0,
		assimilating = nil,
		leap = nil,
		anim = nil,
		epoch = 0,
		history = { { t = workspace:GetServerTimeNow(), pos = feet.Position } },
		statusKey = "",
		statusSentAt = 0,
	}
	shells[shell.id] = shell
	if player then
		byPlayer[player] = shell
	end
	return shell
end

-- reason: "collapse" (it left or ran dry: perceiving mercs see it fall apart), "destroyed" (shot to
-- pieces) or "gone".
function Shells.remove(shell: Shell, reason: string)
	if shells[shell.id] ~= shell then
		return
	end
	shells[shell.id] = nil
	if shell.player and byPlayer[shell.player] == shell then
		byPlayer[shell.player] = nil
	end
	for _, listener in removedListeners do
		listener(shell, reason)
	end
end

local function receive(player: Player, nonce: any, batch: any)
	local shell = byPlayer[player]
	if not shell or nonce ~= shell.nonce or type(batch) ~= "table" then
		return
	end
	local accepted = 0
	for index, raw in batch do
		if index > 8 then
			break
		end
		if type(raw) ~= "table" then
			continue
		end
		local seq, mx, mz, jump, yaw = raw[1], raw[2], raw[3], raw[4], raw[5]
		if not (finite(seq) and finite(mx) and finite(mz) and finite(yaw)) then
			continue
		end
		seq = math.floor(seq)
		if seq <= shell.lastSeq or seq > shell.lastSeq + 240 then
			continue
		end
		local duplicate = false
		for _, queued in shell.buffer do
			if queued.seq == seq then
				duplicate = true
				break
			end
		end
		if duplicate then
			continue
		end
		local length = math.sqrt(mx * mx + mz * mz)
		if length > 1 then
			mx /= length
			mz /= length
		end
		table.insert(shell.buffer, { seq = seq, mx = mx, mz = mz, jump = jump == true, yaw = yaw % TWO_PI })
		accepted += 1
	end
	if accepted > 0 then
		table.sort(shell.buffer, function(a, b)
			return a.seq < b.seq
		end)
		shell.lastInputAt = os.clock()
	end
end

-- One input per tick. If the client fell behind (debt) or flooded the queue, drop the oldest inputs
-- but keep their jump presses. If nothing arrived, carry on briefly, then stop.
local function nextInput(shell: Shell): ShellMotor.Input
	local buffer = shell.buffer
	if #buffer > 0 then
		while #buffer > 1 and (shell.debt > 0 or #buffer > S.InputBufferMax) do
			local dropped = table.remove(buffer, 1) :: QueuedInput
			if dropped.jump then
				buffer[1].jump = true
			end
			shell.lastSeq = dropped.seq
			shell.debt = math.max(0, shell.debt - 1)
		end
		local input = table.remove(buffer, 1) :: QueuedInput
		shell.lastSeq = input.seq
		shell.lastInput = input
		return input
	end
	shell.debt = math.min(shell.debt + 1, 8)
	local last = shell.lastInput
	if os.clock() - shell.lastInputAt > S.InputStaleSeconds then
		return { mx = 0, mz = 0, jump = false, yaw = last.yaw }
	end
	return { mx = last.mx, mz = last.mz, jump = false, yaw = last.yaw }
end

local HISTORY_SECONDS = 0.6

function Shells.tick(dt: number)
	local params = ShellMotor.params()
	local now = workspace:GetServerTimeNow()
	for _, shell in shells do
		local input = if shell.brain then shell.brain(shell, dt) else nextInput(shell)
		input.speedScale = shell.speedScale
		shell.state = ShellMotor.step(shell.state, input, dt, params)
		shell.yaw = input.yaw
		local history = shell.history
		table.insert(history, { t = now, pos = shell.state.pos })
		while #history > 2 and now - history[1].t > HISTORY_SECONDS do
			table.remove(history, 1)
		end
		if shell.state.pos.Y < S.KillY then
			for _, listener in fellListeners do
				listener(shell)
			end
		end
	end
	for player, shell in byPlayer do
		local s = shell.state
		authRemote:FireClient(player, shell.nonce, shell.lastSeq, s.pos.X, s.pos.Y, s.pos.Z, s.vel.X, s.vel.Y, s.vel.Z, s.grounded, shell.speedScale)
	end
end

-- Where the shell's feet were at server time `t` (for lag-compensated hits), from recent history.
function Shells.positionAt(shell: Shell, t: number): Vector3
	local history = shell.history
	if #history == 0 or t >= history[#history].t then
		return shell.state.pos
	end
	if t <= history[1].t then
		return history[1].pos
	end
	for i = #history - 1, 1, -1 do
		local a, b = history[i], history[i + 1]
		if a.t <= t then
			local span = b.t - a.t
			local alpha = if span > 1e-4 then (t - a.t) / span else 1
			return a.pos:Lerp(b.pos, alpha)
		end
	end
	return shell.state.pos
end

-- Moves a shell instantly (System Leap). Viewers see it vanish and reappear rather than slide.
function Shells.teleport(shell: Shell, feet: CFrame)
	local look = feet.LookVector
	shell.state = { pos = feet.Position, vel = Vector3.zero, grounded = false }
	shell.yaw = math.atan2(-look.X, -look.Z)
	shell.lastInput = { mx = 0, mz = 0, jump = false, yaw = shell.yaw }
	shell.epoch += 1
	shell.history = { { t = workspace:GetServerTimeNow(), pos = feet.Position } }
end

-- Merc bodies shells can't walk through.
function Shells.setObstacles(characters: { Instance })
	ShellMotor.setObstacles(characters)
end

function Shells.init()
	authRemote = Net.get("ShellAuth")
	Net.get("ShellInput").OnServerEvent:Connect(receive)
end

return Shells
