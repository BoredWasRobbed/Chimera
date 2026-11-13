-- Merc movement: walk at 14 studs/s, sprint at 20 for up to 5 s. The client predicts its own sprint so
-- it feels instant; the server runs the same stamina model, owns the result, sets the replicated
-- WalkSpeed and corrects the client's stamina twice a second.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)
local Net = require(ReplicatedStorage.Shared.Net)

local MercMovement = {}

local M = Config.Merc

type SprintState = {
	stamina: number,
	wantSprint: boolean,
	sprinting: boolean,
	exhausted: boolean,
	lastSprintAt: number,
	lastSync: number,
}

local states: { [Player]: SprintState } = {}
local stateRemote: RemoteEvent

-- Walk or sprint speed, scaled by being downed (crawl at 30%) and by any slow (a conduit trap).
-- The client runs the same rule to predict its own speed.
function MercMovement.speedFor(character: Model, sprinting: boolean): number
	local speed = if sprinting then M.SprintSpeed else M.WalkSpeed
	if character:GetAttribute("Downed") == true then
		speed = M.WalkSpeed * Config.Health.DownedSpeedScale
	end
	local slowUntil = character:GetAttribute("SlowUntil")
	if type(slowUntil) == "number" and workspace:GetServerTimeNow() < slowUntil then
		speed *= character:GetAttribute("SlowScale") or 1
	end
	return speed
end

local function sync(player: Player, s: SprintState)
	s.lastSync = os.clock()
	stateRemote:FireClient(player, s.stamina, s.exhausted)
end

local function update(dt: number)
	local now = os.clock()
	for player, s in states do
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if not humanoid or not root or humanoid.Health <= 0 then
			continue
		end
		local v = root.AssemblyLinearVelocity
		local moving = Vector3.new(v.X, 0, v.Z).Magnitude > 2
		local wasExhausted = s.exhausted
		local downed = character:GetAttribute("Downed") == true
		if s.wantSprint and moving and not downed and not s.exhausted and s.stamina > 0 then
			s.sprinting = true
			s.lastSprintAt = now
			s.stamina = math.max(0, s.stamina - dt)
			if s.stamina <= 0 then
				s.exhausted = true
				s.sprinting = false
			end
		else
			s.sprinting = false
			if now - s.lastSprintAt >= M.StaminaRegenDelay then
				s.stamina = math.min(M.SprintSeconds, s.stamina + M.StaminaRegenPerSecond * dt)
			end
			if s.exhausted and s.stamina >= M.SprintRestartSeconds then
				s.exhausted = false
			end
		end
		local speed = MercMovement.speedFor(character, s.sprinting)
		if humanoid.WalkSpeed ~= speed then
			humanoid.WalkSpeed = speed
		end
		if s.exhausted ~= wasExhausted or now - s.lastSync >= 0.5 then
			sync(player, s)
		end
	end
end

function MercMovement.addMerc(player: Player)
	states[player] = {
		stamina = M.SprintSeconds,
		wantSprint = false,
		sprinting = false,
		exhausted = false,
		lastSprintAt = -math.huge,
		lastSync = 0,
	}
end

function MercMovement.removeMerc(player: Player)
	states[player] = nil
end

-- A fresh body starts with full stamina.
function MercMovement.resetStamina(player: Player)
	local s = states[player]
	if s then
		s.stamina = M.SprintSeconds
		s.exhausted = false
		s.sprinting = false
		s.wantSprint = false
		sync(player, s)
	end
end

function MercMovement.init()
	stateRemote = Net.get("MercState")
	Net.get("MercSprint").OnServerEvent:Connect(function(player, want)
		local s = states[player]
		if s and type(want) == "boolean" then
			s.wantSprint = want
		end
	end)
	RunService.Heartbeat:Connect(update)
end

return MercMovement
