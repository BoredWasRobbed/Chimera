-- Doors stand open. The Chimera's Lock door action slams one shut for 8 s; a merc can force it open
-- by holding the prompt for 3 s. Doors never open for a shell walking by, so door movement can't give
-- the shell's position away.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage.Shared.Config)
local Cues = require(script.Parent.Cues)
local MapData = require(script.Parent.MapData)

local Doors = {}

local LOCKED_COLOR = Color3.fromRGB(255, 160, 40)
local UNLOCKED_COLOR = Color3.fromRGB(45, 45, 48)
local SLIDE = TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.In)

local locks: { [string]: { untilTime: number, token: {} } } = {}
local prompts: { [string]: ProximityPrompt } = {}
local shellFeet: () -> { Vector3 } = function()
	return {}
end

local function setLockLights(door, locked: boolean)
	for _, light in door.lockLights do
		light.Color = if locked then LOCKED_COLOR else UNLOCKED_COLOR
		light.Material = if locked then Enum.Material.Neon else Enum.Material.SmoothPlastic
	end
end

local function doorwayBox(door): (CFrame, Vector3)
	local size = door.panel.Size
	return door.closed, Vector3.new(size.X, size.Y, 6)
end

local function obstructed(door): boolean
	local cf, size = doorwayBox(door)
	local characters = {}
	for _, player in Players:GetPlayers() do
		if player.Character then
			table.insert(characters, player.Character)
		end
	end
	if #characters > 0 then
		local overlap = OverlapParams.new()
		overlap.FilterType = Enum.RaycastFilterType.Include
		overlap.FilterDescendantsInstances = characters
		if #workspace:GetPartBoundsInBox(cf, size, overlap) > 0 then
			return true
		end
	end
	local half = size / 2 + Vector3.new(Config.Shell.Width / 2, 0, Config.Shell.Width / 2)
	for _, feet in shellFeet() do
		local rel = cf:PointToObjectSpace(feet + Vector3.new(0, Config.Shell.Height / 2, 0))
		if math.abs(rel.X) <= half.X and math.abs(rel.Y) <= half.Y + Config.Shell.Height / 2 and math.abs(rel.Z) <= half.Z then
			return true
		end
	end
	return false
end

function Doors.isLocked(id: string): boolean
	local lock = locks[id]
	return lock ~= nil and lock.untilTime > os.clock()
end

local function unlock(id: string, forced: boolean)
	local door = MapData.doors[id]
	if not door then
		return
	end
	locks[id] = nil
	if prompts[id] then
		prompts[id].Enabled = false
	end
	setLockLights(door, false)
	TweenService:Create(door.panel, SLIDE, { CFrame = door.open }):Play()
	if forced then
		Cues.emit("DoorForced", door.closed.Position, Config.Interface.LockDoor.SoundRange)
	end
end

function Doors.lock(id: string): (boolean, string?)
	local door = MapData.doors[id]
	if not door then
		return false, "No such door"
	end
	if Doors.isLocked(id) then
		return false, "Already locked"
	end
	if obstructed(door) then
		return false, "Something is in the doorway"
	end
	local settings = Config.Interface.LockDoor
	local token = {}
	locks[id] = { untilTime = os.clock() + settings.DurationSeconds, token = token }
	TweenService:Create(door.panel, SLIDE, { CFrame = door.closed }):Play()
	setLockLights(door, true)
	if prompts[id] then
		prompts[id].Enabled = true
	end
	Cues.emit("LockClunk", door.closed.Position, settings.SoundRange)
	task.delay(settings.DurationSeconds, function()
		local lock = locks[id]
		if lock and lock.token == token then
			unlock(id, false)
		end
	end)
	return true
end

-- getShellFeet lists where every active shell stands, so a door never slams shut on one.
function Doors.init(getShellFeet: () -> { Vector3 })
	shellFeet = getShellFeet
	for id, door in MapData.doors do
		door.panel.CFrame = door.open
		setLockLights(door, false)
		local prompt = Instance.new("ProximityPrompt")
		prompt.Name = "ForceOpen"
		prompt.ActionText = "Force open"
		prompt.ObjectText = "Locked door"
		prompt.HoldDuration = Config.Interface.LockDoor.ForceOpenSeconds
		prompt.MaxActivationDistance = 9
		prompt.RequiresLineOfSight = false
		prompt.Enabled = false
		prompt.Parent = door.panel
		prompt.Triggered:Connect(function(player)
			if player:GetAttribute("Role") == "Merc" and Doors.isLocked(id) then
				unlock(id, true)
			end
		end)
		prompts[id] = prompt
	end
end

return Doors
