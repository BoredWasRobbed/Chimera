-- Static Decoy (the default Utility module, from a camera or a shell): a hologram of a living merc,
-- name tag included, that walks where the Chimera aimed for 10 s. It flickers when shot or caught in a
-- flashlight within 6 studs. 30 s cooldown. It's a server-owned R6 body, so it replicates exactly like a
-- real merc would; the client name tags read the same MercTag attribute real mercs carry.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Hitbox = require(ReplicatedStorage.Shared.Hitbox)
local Net = require(ReplicatedStorage.Shared.Net)
local Flashlights = require(script.Parent.Flashlights)
local Health = require(script.Parent.Health)
local Sight = require(script.Parent.Sight)

local D = Config.Modules.StaticDecoy
local WALK_ANIMATION = "rbxassetid://180426354" -- Roblox's default R6 walk

local Decoys = {}

local folder: Folder
local combat: RemoteEvent
local active: { [Model]: { endsAt: number, flickerAt: number } } = {}
local floorParams = RaycastParams.new()
floorParams.FilterType = Enum.RaycastFilterType.Include

local function buildBody(source: Model?): Model?
	local clone: Model? = nil
	if source then
		local was = source.Archivable
		source.Archivable = true
		local ok, result = pcall(function()
			return source:Clone()
		end)
		source.Archivable = was
		if ok then
			clone = result
		end
	end
	if not clone then
		local ok, result = pcall(function()
			return Players:CreateHumanoidModelFromDescription(Instance.new("HumanoidDescription"), Enum.HumanoidRigType.R6)
		end)
		if ok then
			clone = result
		end
	end
	if not clone then
		return nil
	end
	for _, d in clone:GetDescendants() do
		if d:IsA("BaseScript") or d:IsA("ProximityPrompt") or d:IsA("Tool") or d:IsA("ForceField") then
			d:Destroy()
		end
	end
	return clone
end

local function flicker(model: Model)
	local entry = active[model]
	local now = os.clock()
	if entry and now >= entry.flickerAt then
		entry.flickerAt = now + 0.6
		combat:FireAllClients("decoyFlicker", model)
	end
end

function Decoys.isDecoy(model: Instance?): boolean
	return model ~= nil and active[model :: Model] ~= nil
end

-- A shot hit this decoy.
function Decoys.hit(model: Model)
	flicker(model)
end

-- origin: the camera lens or the shell's eyes it was cast from. Returns ok, reason.
function Decoys.cast(origin: Vector3, point: any, range: number): (boolean, string?)
	if not Hitbox.finiteVector(point) then
		return false, "No target"
	end
	if (point - origin).Magnitude > range then
		return false, "Too far"
	end
	local floorHit = workspace:Raycast(point + Vector3.new(0, 2, 0), Vector3.new(0, -12, 0), floorParams)
	if not floorHit or floorHit.Normal.Y < 0.7 then
		return false, "Aim at the floor"
	end
	local floor = floorHit.Position
	if not Sight.clear(origin, floor + Vector3.new(0, 1.5, 0)) then
		return false, "Can't see that from here"
	end

	-- Copy a standing merc, name tag and all.
	local sources = {}
	for model, body in Health.all() do
		if body.player and not body.downed then
			table.insert(sources, model)
		end
	end
	local source = if #sources > 0 then sources[math.random(1, #sources)] else nil
	local tag = if source then source:GetAttribute("MercTag") or source.Name else "Merc"
	local model = buildBody(source)
	local humanoid = model and model:FindFirstChildOfClass("Humanoid")
	local root = model and model:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not model or not humanoid or not root then
		return false, "Decoy failed"
	end
	local joint = root:FindFirstChild("RootJoint")
	if joint and joint:IsA("Motor6D") then
		joint.C0 = CFrame.new(0, 0, 0, -1, 0, 0, 0, 0, 1, 0, 1, 0) -- stand up, in case the source was crouched
	end

	local flat = Vector3.new(point.X - origin.X, 0, point.Z - origin.Z)
	local direction = if flat.Magnitude > 0.1 then flat.Unit else Vector3.new(0, 0, -1)
	model.Name = "Decoy"
	model:SetAttribute("MercTag", tag)
	model:SetAttribute("HP", Config.Health.MercMax)
	model:SetAttribute("Downed", false)
	model:SetAttribute("Aim", direction)
	humanoid.WalkSpeed = D.WalkSpeed
	humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	model:PivotTo(CFrame.lookAt(floor + Vector3.new(0, 3, 0), floor + Vector3.new(0, 3, 0) + direction))
	model.Parent = folder
	pcall(function()
		root:SetNetworkOwner(nil)
	end)

	local animator = humanoid:FindFirstChildOfClass("Animator") or Instance.new("Animator", humanoid)
	local animation = Instance.new("Animation")
	animation.AnimationId = WALK_ANIMATION
	local ok, track = pcall(function()
		return (animator :: Animator):LoadAnimation(animation)
	end)
	if ok and track then
		track.Looped = true
		track:Play()
	end
	humanoid:MoveTo(floor + direction * (D.Duration * D.WalkSpeed + 10))

	active[model] = { endsAt = os.clock() + D.Duration, flickerAt = 0 }
	return true
end

function Decoys.tick(_dt: number)
	local now = os.clock()
	for model, entry in active do
		if now >= entry.endsAt or not model.Parent then
			active[model] = nil
			if model.Parent then
				combat:FireAllClients("decoyFade", model)
				task.delay(0.4, function()
					model:Destroy()
				end)
			end
			continue
		end
		local head = model:FindFirstChild("Head") :: BasePart?
		if head and Flashlights.covers(head.Position, D.FlickerRange) then
			flicker(model)
		end
	end
end

function Decoys.folder(): Folder
	return folder
end

function Decoys.init()
	combat = Net.get("Combat")
	floorParams.FilterDescendantsInstances = { workspace:WaitForChild("Map") }
	folder = Instance.new("Folder")
	folder.Name = "Decoys"
	folder.Parent = workspace
end

return Decoys
