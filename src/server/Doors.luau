-- Doors stand open. The Chimera's Lock door action slams one shut for 8 s; a merc can force it open
-- by holding the prompt for 3 s. A Technician can weld an open door shut (hold 3 s); the weld holds
-- until the Chimera breaks it with 4 s of claw attacks. Doors never open for a shell walking by, so
-- door movement can't give the shell's position away.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage.Shared.Config)
local Cues = require(script.Parent.Cues)
local Health = require(script.Parent.Health)
local MapData = require(script.Parent.MapData)

local Doors = {}

local LOCKED_COLOR = Color3.fromRGB(255, 160, 40)
local UNLOCKED_COLOR = Color3.fromRGB(45, 45, 48)
local WELD_COLOR = Color3.fromRGB(255, 205, 140)
local SLIDE = TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.In)

local locks: { [string]: { untilTime: number, token: {} } } = {}
local welds: { [string]: { progress: number, seam: BasePart } } = {}
local forcePrompts: { [string]: ProximityPrompt } = {}
local weldPrompts: { [string]: ProximityPrompt } = {}
local weldHolds: { [string]: { [Player]: number } } = {}
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
	for model in Health.all() do
		table.insert(characters, model)
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

local function refreshPrompts(id: string)
	local locked = Doors.isLocked(id)
	local welded = welds[id] ~= nil
	if forcePrompts[id] then
		forcePrompts[id].Enabled = locked and not welded
	end
	if weldPrompts[id] then
		weldPrompts[id].Enabled = not locked and not welded
	end
end

function Doors.isLocked(id: string): boolean
	local lock = locks[id]
	return lock ~= nil and lock.untilTime > os.clock()
end

function Doors.isWelded(id: string): boolean
	return welds[id] ~= nil
end

local function unlock(id: string, forced: boolean)
	local door = MapData.doors[id]
	if not door then
		return
	end
	locks[id] = nil
	setLockLights(door, false)
	if not welds[id] then
		TweenService:Create(door.panel, SLIDE, { CFrame = door.open }):Play()
	end
	refreshPrompts(id)
	if forced then
		Cues.emit("DoorForced", door.closed.Position, Config.Interface.LockDoor.SoundRange)
	end
end

function Doors.lock(id: string): (boolean, string?)
	local door = MapData.doors[id]
	if not door then
		return false, "No such door"
	end
	if welds[id] then
		return false, "That door is welded shut"
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
	refreshPrompts(id)
	Cues.emit("LockClunk", door.closed.Position, settings.SoundRange)
	task.delay(settings.DurationSeconds, function()
		local lock = locks[id]
		if lock and lock.token == token then
			unlock(id, false)
		end
	end)
	return true
end

-- Technician passive: weld an open door shut until the Chimera claws through it.
function Doors.weld(id: string): (boolean, string?)
	local door = MapData.doors[id]
	if not door then
		return false, "No such door"
	end
	if welds[id] or Doors.isLocked(id) then
		return false, "That door is already shut"
	end
	if obstructed(door) then
		return false, "Something is in the doorway"
	end
	local seam = Instance.new("Part")
	seam.Name = "WeldSeam"
	seam.Size = Vector3.new(0.3, door.panel.Size.Y - 0.6, door.panel.Size.Z + 0.2)
	seam.CFrame = door.closed * CFrame.new(door.panel.Size.X / 2 - 0.4, 0, 0)
	seam.Color = WELD_COLOR
	seam.Material = Enum.Material.Neon
	seam.Anchored = true
	seam.CanCollide = false
	seam.CanQuery = false
	seam.CanTouch = false
	seam.Parent = door.model
	welds[id] = { progress = 0, seam = seam }
	door.model:SetAttribute("Welded", true)
	TweenService:Create(door.panel, SLIDE, { CFrame = door.closed }):Play()
	refreshPrompts(id)
	return true
end

-- Claw swipes on a welded door. The weld breaks after WeldBreakSeconds of attacks.
function Doors.weldDamage(id: string, seconds: number)
	local weld = welds[id]
	local door = MapData.doors[id]
	if not weld or not door then
		return
	end
	weld.progress += seconds
	if weld.progress >= Config.Gear.WeldBreakSeconds - 1e-6 then
		weld.seam:Destroy()
		welds[id] = nil
		door.model:SetAttribute("Welded", nil)
		TweenService:Create(door.panel, SLIDE, { CFrame = door.open }):Play()
		refreshPrompts(id)
		Cues.emit("WeldBroken", door.closed.Position, 60)
	end
end

local function canWeld(player: Player, id: string): boolean
	if player:GetAttribute("Role") ~= "Merc" or player:GetAttribute("Class") ~= "Technician" then
		return false
	end
	local body = Health.ofPlayer(player)
	local door = MapData.doors[id]
	if not body or body.downed or not door then
		return false
	end
	return (body.root.Position - door.closed.Position).Magnitude <= 12
end

-- getShellFeet lists where every active shell stands, so a door never slams shut on one.
function Doors.init(getShellFeet: () -> { Vector3 })
	shellFeet = getShellFeet
	for id, door in MapData.doors do
		door.panel.CFrame = door.open
		setLockLights(door, false)

		local force = Instance.new("ProximityPrompt")
		force.Name = "ForceOpen"
		force.ActionText = "Force open"
		force.ObjectText = "Locked door"
		force.HoldDuration = Config.Interface.LockDoor.ForceOpenSeconds
		force.MaxActivationDistance = 9
		force.RequiresLineOfSight = false
		force.Enabled = false
		force.Parent = door.panel
		force.Triggered:Connect(function(player)
			if player:GetAttribute("Role") == "Merc" and Doors.isLocked(id) and not welds[id] then
				unlock(id, true)
			end
		end)
		forcePrompts[id] = force

		-- Clients show this one only to Technicians.
		local weld = Instance.new("ProximityPrompt")
		weld.Name = "WeldPrompt"
		weld.ActionText = "Weld shut"
		weld.ObjectText = "Door"
		weld.HoldDuration = Config.Gear.WeldSeconds
		weld.MaxActivationDistance = 9
		weld.RequiresLineOfSight = false
		weld.Enabled = true
		-- An open door's panel sits in the wall pocket, so anchor this prompt over the doorway itself.
		weld.Parent = door.lockLights[1] or door.panel
		weldHolds[id] = {}
		weld.PromptButtonHoldBegan:Connect(function(player)
			weldHolds[id][player] = os.clock()
		end)
		weld.Triggered:Connect(function(player)
			local started = weldHolds[id][player]
			weldHolds[id][player] = nil
			if started and os.clock() - started >= Config.Gear.WeldSeconds - 0.25 and canWeld(player, id) then
				Doors.weld(id)
			end
		end)
		weldPrompts[id] = weld
	end
end

return Doors
