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
}

return Config
