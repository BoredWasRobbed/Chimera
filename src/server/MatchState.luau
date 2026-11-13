-- Match-wide facts other modules read: the phase, the finale, Lockdown, Threat Level and the player-count
-- scaling. It requires no game modules, so anything can depend on it; Match writes it.
--
-- Clients read a replicated copy: ReplicatedStorage.MatchState, a Configuration whose attributes are
--   Phase, PhaseEndsAt, Waiting, PlayerCount, PlayersNeeded, RaceStartedAt, Upload, Threat, Lockdown,
--   Finale, FinaleEndsAt, Hold, HoldState, TerminalsDone, TerminalsNeeded, MissingMercs, Winner,
--   WinReason, MatchSeconds, StudioMinPlayers, StudioAfk
-- (times are server time: workspace:GetServerTimeNow()).
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)

export type Phase = "Lobby" | "Loadout" | "Deployment" | "Race" | "Finale" | "Results"

local MatchState = {}

MatchState.phase = "Lobby" :: Phase
MatchState.finale = nil :: ("Purge" | "Upload")?
MatchState.lockdown = false
MatchState.threat = 1
MatchState.missingMercs = 0
MatchState.coreRoom = nil :: string?

local folder: Configuration

function MatchState.init()
	folder = Instance.new("Configuration")
	folder.Name = "MatchState"
	folder.Parent = ReplicatedStorage
end

function MatchState.publish(name: string, value: any)
	if folder:GetAttribute(name) ~= value then
		folder:SetAttribute(name, value)
	end
end

function MatchState.read(name: string): any
	return folder:GetAttribute(name)
end

-- Interface, shells, traps and decoys are offline while the Chimera boots in the network (Deployment).
function MatchState.interfaceOnline(): boolean
	return MatchState.phase ~= "Deployment"
end

-- Energy regen multiplier: +15% per Threat level above 1.
function MatchState.regenScale(): number
	return 1 + Config.Threat.RegenPerLevel * (MatchState.threat - 1)
end

-- Ability cooldown multiplier: -10% per Threat level above 1.
function MatchState.cooldownScale(): number
	return math.max(0.1, 1 - Config.Threat.CooldownPerLevel * (MatchState.threat - 1))
end

-- Each merc short of five at deployment: reboots take 10% less time and shells have 10% less HP.
function MatchState.rebootScale(): number
	return math.max(0.1, 1 - Config.PlayerCount.RebootFasterPerMissing * MatchState.missingMercs)
end

function MatchState.shellHpScale(): number
	return math.max(0.1, 1 - Config.PlayerCount.ShellHpLessPerMissing * MatchState.missingMercs)
end

return MatchState
