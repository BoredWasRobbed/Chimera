-- Security-camera view math shared by the Chimera's client (what it draws) and the server
-- (what a camera is allowed to act on).
local CameraMath = {}

local TAU = 2 * math.pi

function CameraMath.wrap(angle: number): number
	return (angle + math.pi) % TAU - math.pi
end

-- Yaw and pitch (radians) of a look direction, in the same convention as CFrame.Angles(0, yaw, 0) * CFrame.Angles(pitch, 0, 0).
function CameraMath.anglesFromLook(look: Vector3): (number, number)
	return math.atan2(-look.X, -look.Z), math.asin(math.clamp(look.Y, -1, 1))
end

function CameraMath.viewCFrame(position: Vector3, yaw: number, pitch: number): CFrame
	return CFrame.new(position) * CFrame.Angles(0, yaw, 0) * CFrame.Angles(pitch, 0, 0)
end

-- Can a camera that pans and tilts within its limits (degrees) bring `point` on screen?
function CameraMath.canFrame(
	origin: Vector3,
	baseYaw: number,
	basePitch: number,
	point: Vector3,
	panLimit: number,
	tiltLimit: number,
	maxFov: number,
	maxAspect: number
): boolean
	local d = point - origin
	local horizontal = math.sqrt(d.X * d.X + d.Z * d.Z)
	if horizontal < 1e-3 and math.abs(d.Y) < 1e-3 then
		return true
	end
	local yaw = math.atan2(-d.X, -d.Z)
	local pitch = math.atan2(d.Y, horizontal)
	local halfV = math.rad(maxFov) / 2
	local halfH = math.atan(math.tan(halfV) * maxAspect)
	return math.abs(CameraMath.wrap(yaw - baseYaw)) <= math.rad(panLimit) + halfH
		and math.abs(pitch - basePitch) <= math.rad(tiltLimit) + halfV
end

return CameraMath
