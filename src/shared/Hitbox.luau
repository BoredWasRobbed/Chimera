-- Hit-test math shared by the server (which owns every hit) and clients (which only predict visuals).
local Hitbox = {}

-- Distance along a unit ray to an axis-aligned box, or nil if it misses.
function Hitbox.rayBox(origin: Vector3, direction: Vector3, minCorner: Vector3, maxCorner: Vector3): number?
	local tMin, tMax = -math.huge, math.huge
	for _, axis in { "X", "Y", "Z" } do
		local o = (origin :: any)[axis]
		local d = (direction :: any)[axis]
		local lo = (minCorner :: any)[axis]
		local hi = (maxCorner :: any)[axis]
		if math.abs(d) < 1e-9 then
			if o < lo or o > hi then
				return nil
			end
		else
			local t1 = (lo - o) / d
			local t2 = (hi - o) / d
			if t1 > t2 then
				t1, t2 = t2, t1
			end
			tMin = math.max(tMin, t1)
			tMax = math.min(tMax, t2)
			if tMin > tMax then
				return nil
			end
		end
	end
	if tMax < 0 then
		return nil
	end
	return math.max(tMin, 0)
end

-- The upright box around a body standing at `feet`.
function Hitbox.bodyBox(feet: Vector3, width: number, height: number): (Vector3, Vector3)
	local half = width / 2
	return feet + Vector3.new(-half, 0, -half), feet + Vector3.new(half, height, half)
end

-- A random direction within `degrees` of `direction`, evenly spread over the cone's disc.
function Hitbox.spread(direction: Vector3, degrees: number, rng: Random): Vector3
	if degrees <= 0 then
		return direction
	end
	local angle = math.rad(degrees) * math.sqrt(rng:NextNumber())
	local spin = rng:NextNumber() * 2 * math.pi
	local frame = CFrame.lookAt(Vector3.zero, direction)
	return (frame * CFrame.Angles(0, 0, spin) * CFrame.Angles(angle, 0, 0)).LookVector
end

-- Is `point` inside a cone from `origin` along unit `direction`, within `range` and `halfAngle` degrees?
function Hitbox.inCone(origin: Vector3, direction: Vector3, point: Vector3, range: number, halfAngle: number): boolean
	local offset = point - origin
	local distance = offset.Magnitude
	if distance > range then
		return false
	end
	if distance < 1e-3 then
		return true
	end
	return direction:Dot(offset / distance) >= math.cos(math.rad(halfAngle))
end

function Hitbox.finiteVector(v: any): boolean
	if typeof(v) ~= "Vector3" then
		return false
	end
	for _, c in { v.X, v.Y, v.Z } do
		if c ~= c or c == math.huge or c == -math.huge then
			return false
		end
	end
	return true
end

return Hitbox
