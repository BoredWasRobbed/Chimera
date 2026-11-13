-- Line-of-sight checks. The server runs every Interface action and shell take through these, so a client
-- that sees through walls still can't act through them.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CameraMath = require(ReplicatedStorage.Shared.CameraMath)
local Config = require(ReplicatedStorage.Shared.Config)
local FacilityMap = require(ReplicatedStorage.Shared.FacilityMap)

local Sight = {}

local params = RaycastParams.new()
params.FilterType = Enum.RaycastFilterType.Include
params.IgnoreWater = true

function Sight.init()
	params.FilterDescendantsInstances = { workspace:WaitForChild("Map") }
end

-- Nothing in the map blocks the line from `from` to `to`. A hit on `target` itself counts as clear.
function Sight.clear(from: Vector3, to: Vector3, target: Instance?): boolean
	local delta = to - from
	if delta.Magnitude < 0.05 then
		return true
	end
	local hit = workspace:Raycast(from, delta, params)
	if not hit then
		return true
	end
	if target and (hit.Instance == target or hit.Instance:IsDescendantOf(target)) then
		return true
	end
	return false
end

function Sight.anyClear(from: Vector3, points: { Vector3 }, target: Instance?, range: number?): boolean
	for _, point in points do
		if (range == nil or (point - from).Magnitude <= range) and Sight.clear(from, point, target) then
			return true
		end
	end
	return false
end

-- A security camera can see a point if it's in range, inside the area the camera can pan and tilt over,
-- and nothing blocks the line.
function Sight.cameraSees(cam: FacilityMap.CameraInfo, points: { Vector3 }, target: Instance?): boolean
	local c = Config.Camera
	for _, point in points do
		if
			(point - cam.origin).Magnitude <= Config.Interface.CameraRange
			and CameraMath.canFrame(cam.origin, cam.baseYaw, cam.basePitch, point, cam.panLimit, cam.tiltLimit, c.MaxFov, c.MaxAspect)
			and Sight.clear(cam.origin, point, target)
		then
			return true
		end
	end
	return false
end

-- A shell sees from its eyes, in any direction (it can turn), out to its Interface range.
function Sight.shellSees(feet: Vector3, points: { Vector3 }, target: Instance?): boolean
	local eye = feet + Vector3.new(0, Config.Shell.EyeHeight, 0)
	return Sight.anyClear(eye, points, target, Config.Shell.SightRange)
end

return Sight
