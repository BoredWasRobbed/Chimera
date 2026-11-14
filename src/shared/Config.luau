-- Tunable numbers for the vertical slice. Values come from the design doc (v2.1) where it gives them;
-- the rest are starting values to tune in playtests. Shared by the server and every client.
local Config = {}

Config.Merc = {
	WalkSpeed = 14,
	SprintSpeed = 20,
	SprintSeconds = 5, -- a full stamina bar is 5 s of sprinting
	StaminaRegenDelay = 1, -- seconds after sprinting stops before stamina refills
	StaminaRegenPerSecond = 1, -- seconds of sprint regained per second
	SprintRestartSeconds = 1.5, -- after running dry, stamina needed before sprinting again
	RespawnSeconds = 3,
}

Config.Chimera = {
	EnergyMax = 100,
	EnergyStart = 100,
	EnergyRegen = 2, -- per second in facility mode
	HopSeconds = 0.5,
	StartCamera = "CORE_NE",
	ActionRateLimit = 15, -- remote requests per second before the server ignores them
}

Config.Shell = {
	TakeCost = 20,
	TakeHoldSeconds = 1.5,
	Drain = 2, -- energy per second while in a shell
	LeaveHoldSeconds = 1,
	ReprintSeconds = 45,
	WhineRange = 20, -- the boot whine is audible this far
	CollapseRange = 30,
	SightRange = 60, -- Interface reach from a shell's eyes

	-- Custom server-authoritative character controller
	TickRate = 30,
	WalkSpeed = 19,
	Height = 5.2,
	Width = 2.2,
	StepHeight = 1.1,
	EyeHeight = 4.6,
	JumpVelocity = 42,
	Gravity = 196.2,
	GroundAccel = 160,
	AirAccel = 30,
	InputBufferMax = 6, -- server-side input queue cap (inputs past this are dropped)
	InputStaleSeconds = 0.25, -- no input for this long and the server stops the shell
	KillY = -60,
}

Config.Interface = {
	Blackout = { Cost = 25, HoldSeconds = 0, DurationSeconds = 20, SoundRange = 60 },
	LockDoor = { Cost = 20, HoldSeconds = 0, DurationSeconds = 8, ForceOpenSeconds = 3, SoundRange = 40 },
	CorruptTerminal = { Cost = 15, HoldSeconds = 2, ProgressLoss = 0.2, LockSeconds = 10, SoundRange = 40 },
	TakeShell = { Cost = 20, HoldSeconds = 1.5 },
	CameraRange = 160, -- how far a security camera can act
}

Config.Camera = {
	Fov = 70,
	MinFov = 30,
	MaxFov = 80,
	PanLimit = 55, -- degrees either side of the mount's resting direction
	TiltLimit = 30,
	KeyPanSpeed = 80, -- degrees per second with A/D/W/S
	DragSensitivity = 0.25, -- degrees per pixel with the right mouse button
	MaxAspect = 16 / 9, -- widest screen the server allows for when checking what a camera can see
}

-- Who receives the shell's position (see "Exploit resistance" in the design doc):
-- Cloaked: within CloakedRange with line of sight. Exposed: line of sight at any range up to ExposedRange.
-- Revealed: every living merc. Overwatch: when the camera they watch can see it.
Config.Perception = {
	TickRate = 15,
	CloakedRange = 45,
	ExposedRange = 250,
	RangeHysteresis = 1.5, -- once seen, a shell stays seen out to range + this
	LostGraceSeconds = 0.2, -- line of sight must stay broken this long before the shell is hidden
	LeadSeconds = 0.15, -- also test where the merc and shell will be, so shells don't pop in late at corners
	SidePadding = 1.3, -- extra sample points either side of the shell's chest
	DockSightRange = 250,
	DockNearRange = 25, -- dock contents reach mercs this close even through walls
	InterpolationDelay = 0.12, -- clients render remote shells this far in the past
}

Config.Cues = {
	-- SoundId = "" plays nothing yet; in Studio a floating label shows where each cue played.
	ServoWhine = { Label = "servo whine", SoundId = "", Volume = 0.8 },
	ShellCollapse = { Label = "shell collapses", SoundId = "", Volume = 0.8 },
	PowerDown = { Label = "power-down", SoundId = "", Volume = 0.8 },
	LockClunk = { Label = "lock clunk", SoundId = "", Volume = 0.8 },
	DoorForced = { Label = "door forced", SoundId = "", Volume = 0.8 },
	TerminalCorrupt = { Label = "terminal glitch", SoundId = "", Volume = 0.8 },
	ClawSwipe = { Label = "shriek", SoundId = "", Volume = 1 },
	ShellDestroyed = { Label = "shell destroyed", SoundId = "", Volume = 1 },
	DormantHit = { Label = "dormant shell hit", SoundId = "", Volume = 0.6 },
	LeapCharge = { Label = "leap charge", SoundId = "", Volume = 0.8 },
	LeapLand = { Label = "leap arrival", SoundId = "", Volume = 0.8 },
	TrapArmed = { Label = "hiss", SoundId = "", Volume = 0.6 },
	SteamBurst = { Label = "steam burst", SoundId = "", Volume = 1 },
	ConduitShock = { Label = "conduit shock", SoundId = "", Volume = 1 },
	TripAlarm = { Label = "trip-mine alarm", SoundId = "", Volume = 1 },
	WeldBroken = { Label = "weld breaks", SoundId = "", Volume = 1 },
	CameraBroken = { Label = "camera shot out", SoundId = "", Volume = 0.6 },
	RebootStart = { Label = "reboot whir", SoundId = "", Volume = 0.8 },
	TerminalRebooted = { Label = "reboot chime", SoundId = "", Volume = 1 },
	LockdownAlarm = { Label = "lockdown alarm", SoundId = "", Volume = 1 },
	ScanPulse = { Label = "scan pulse", SoundId = "", Volume = 1 },
}

-- Milestone 2: combat, visibility states, downs and assimilation.

Config.Health = {
	MercMax = 100,
	StimHeal = 40, -- over StimSeconds, one per life
	StimSeconds = 3,
	BleedOutSeconds = { 45, 30, 15 }, -- first, second, later downs in a match
	DownedSpeedScale = 0.3,
	ReviveSeconds = 5,
	MedicReviveSeconds = 2.5,
	ReviveRange = 7,
	ReviveHealth = 30,
	AssimilateSeconds = 3,
	AssimilateRange = 6,
	AssimilateCancelFraction = 0.25, -- of the shell's max HP lost during the hold
	TrapFloor = 1, -- traps and facility damage never take a merc below this
}

-- Revealed beats Exposed beats Cloaked. Perception (above) decides who receives each state.
Config.Visibility = {
	HitRevealSeconds = 1, -- after every hit
	AttackRevealSeconds = 1, -- after every swipe
	FlashRevealSeconds = 2,
	DartRevealSeconds = 3,
	ExposeRange = 15, -- a flashlight beam this close turns Cloaked into Exposed
}

Config.Flashlight = {
	BatterySeconds = 200, -- a full battery, 0.5% a second
	BeamHalfAngle = 22, -- degrees: the beam a shell must be inside
	RenderRange = 45,
	FlashCost = 20, -- percent of the battery
	FlashCooldown = 20,
	FlashRange = 12,
	FlashHalfAngle = 30,
	FlashStagger = 0.5,
	ChargePerSecond = 25, -- percent, standing at a charging station
	ChargeRange = 5,
	ChimeraSeesBeamsWithin = 40, -- through walls, from its camera or shell
}

Config.Detection = {
	TrackerRange = 40,
	TrackerMinSpeed = 2, -- a shell slower than this is still, and invisible to trackers
	TrackerInterval = 0.5,
	HeartbeatRange = 10,
	ScoutHeartbeatRange = 15,
	HeartbeatInterval = 0.5,
}

-- Tuned so five mercs at ~70% accuracy burst a 1,000 HP Revealed shell in about 3 s, and one Assault
-- alone needs about 12 s with reloads. Ammo reserves are unlimited; reloads are what costs.
Config.Weapons = {
	PulseRifle = { Name = "Pulse Rifle", Auto = true, Interval = 0.125, Damage = 16, Pellets = 1, Spread = 1.2, Magazine = 32, Reload = 2.5, Range = 150 },
	Shotgun = { Name = "Shotgun", Auto = false, Interval = 1.0, Damage = 11, Pellets = 8, Spread = 6, Magazine = 6, Reload = 3.0, Range = 60, FalloffStart = 20, FalloffMin = 0.4 },
	Sidearm = { Name = "Sidearm", Auto = false, Interval = 0.25, Damage = 20, Pellets = 1, Spread = 0.6, Magazine = 12, Reload = 1.4, Range = 150 },
	SilencedSMG = { Name = "Silenced SMG", Auto = true, Interval = 0.09, Damage = 8, Pellets = 1, Spread = 2.0, Magazine = 36, Reload = 1.8, Range = 100, Silenced = true },
}

Config.Classes = {
	-- Order is the order new mercs are assigned to, within each class's cap.
	Order = { "Assault", "Technician", "Medic", "Scout" },
	Assault = { Cap = 2, Weapon = "PulseRifle", Gear = "FragGrenade", GearCount = 2 },
	Technician = { Cap = 2, Weapon = "Shotgun", Gear = "TripMine", GearCount = 2 },
	Medic = { Cap = 1, Weapon = "Sidearm", Gear = "NanoRegen", GearCount = 1 },
	Scout = { Cap = 1, Weapon = "SilencedSMG", Gear = "SensorDart", GearCount = 2 },
}

Config.Gear = {
	FragGrenade = { Name = "Frag Grenade", Damage = 150, Radius = 10, Stagger = 1, Fuse = 2.5, ThrowSpeed = 70, Gravity = 120 },
	TripMine = { Name = "Trip Mine", PlaceRange = 10, TriggerRadius = 5, SlowScale = 0.6, SlowSeconds = 2, AlarmRange = 120 },
	NanoRegen = { Name = "Nano-Regen Station", HealPerSecond = 8, Radius = 8, Duration = 30, Cooldown = 60 },
	SensorDart = { Name = "Sensor Dart", Range = 80, TriggerRadius = 8, RevealSeconds = 3 },
	AssaultSlow = { Scale = 0.9, Seconds = 1 }, -- Assault passive: hits slow the shell
	WeldSeconds = 3, -- Technician passive
	WeldBreakSeconds = 4, -- seconds of claw attacks to break a weld
}

-- The Chimera's five default modules. Chassis, Attack and Traversal shape every shell; Utility and
-- Sabotage also work from a camera.
Config.Modules = {
	PhaseWeave = { Name = "Phase Weave", HP = 1000 },
	EnergyClaws = { Name = "Energy Claws", Range = 6, Damage = 35, Interval = 0.8, HalfArc = 60 },
	SystemLeap = { Name = "System Leap", Range = 80, Channel = 2, Cooldown = 25, TrailSeconds = 4, TrailRange = 80 },
	StaticDecoy = { Name = "Static Decoy", Duration = 10, Cooldown = 30, FlickerRange = 6, WalkSpeed = 14 },
	Overload = { Name = "Overload", MaxTraps = 2, TriggerRadius = 5, SteamDps = 10, SteamSeconds = 4, SteamRadius = 7, BlindSeconds = 2, ConduitDamage = 30, ConduitSlowScale = 0.6, ConduitSlowSeconds = 2 },
}

Config.Combat = {
	ShellHitboxWidth = 2.6,
	ShellHitboxHeight = 5.4,
	DormantHP = 300,
	DestroyedTakeBlock = 20, -- seconds before the Chimera can take another shell
	CameraBrokenSeconds = 45,
	ForcedHopSeconds = 2, -- static when the Chimera's camera is shot out
	LagCompensationMax = 0.35, -- seconds a shot may rewind the shell
	MaxOriginError = 6, -- how far a shot's origin may be from the shooter's head
	ShotBroadcastRange = 250,
}

-- Milestone 3: the full match. Rounds, terminals, the upload meter, Threat Level, finales and pings.

Config.Match = {
	LobbySeconds = 20,
	LoadoutSeconds = 25,
	DeploymentSeconds = 15,
	RaceSeconds = 480, -- the race ends at 8:00 at the latest
	FinaleSeconds = 120,
	HardCapSeconds = 600, -- 10:00 from the start of the race
	ResultsSeconds = 10,
	MinPlayers = 4,
	MaxMercs = 5,
	IdleSeconds = 45, -- no input for this long in a match sends a player to the lobby
	ActivityReportSeconds = 5, -- clients report recent input this often
}

Config.Terminals = {
	RebootSeconds = 40,
	TechnicianRebootSeconds = 28,
	OperateRange = 8, -- the operator must stay this close to the terminal
	PromptDistance = 7,
	ForLockdown = 3, -- the full map's 5 terminals: rebooting any 3 triggers Lockdown (the slice was 2 of 3)
	AlertCooldown = 8, -- seconds between reboot alerts for one terminal
}

Config.Upload = {
	PassiveSeconds = 480, -- 0 to 100% with nothing else happening (12.5% a minute)
	MercDowned = 0.10,
	MercAssimilated = 0.15,
	MercBledOut = 0.05,
	TerminalCorrupted = 0.03,
	ShellDestroyed = -0.10, -- with the Chimera inside
}

Config.Threat = {
	RisesAt = { 120, 240, 360 }, -- race seconds: Threat 1 -> 2 -> 3 -> 4
	Max = 4, -- reached at once in either finale
	RegenPerLevel = 0.15, -- energy regen bonus per level above 1
	CooldownPerLevel = 0.10, -- ability cooldown cut per level above 1
}

Config.Finale = {
	HoldSeconds = 45,
	ScanSeconds = 15,
	ScanRevealSeconds = 2, -- Purge: each scan pulse Reveals the Chimera this long
	ScanShowSeconds = 2, -- Upload: each network scan outlines the mercs in the Core this long
	BootSeconds = 5, -- a bodiless Chimera boots a last shell at a Core dock after this
	UploadRespawnSeconds = 10,
	UploadLossSeconds = 5, -- held time lost per body in the Upload finale
}

Config.PlayerCount = {
	RebootFasterPerMissing = 0.10, -- per merc short of five at deployment
	ShellHpLessPerMissing = 0.10,
}

Config.Pings = {
	Seconds = 8, -- how long a ping stays up
	RateCount = 4, -- a merc may send this many pings...
	RateWindow = 3, -- ...per this many seconds
	MaxDistance = 400,
	WheelHoldSeconds = 0.25, -- holding the ping button longer than this opens the wheel
	OverwatchCharges = 3,
	OverwatchRecharge = 20,
	TagSeconds = 3,
	TagCooldown = 30,
	Wheel = { "Chimera", "Going", "Terminal", "Revive", "Battery", "Door" },
	Labels = {
		Ping = "Ping",
		Chimera = "Chimera here",
		Going = "Going here",
		Terminal = "Terminal",
		Revive = "Need revive",
		Battery = "Low battery",
		Door = "Watch this door",
		Overwatch = "Overwatch",
	},
	OnSelf = { Revive = true, Battery = true }, -- these mark the sender, not the aim point
}

return Config
