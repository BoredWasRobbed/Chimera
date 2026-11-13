-- Movement for a Chimera shell: a custom kinematic character controller with no Humanoid and no physics.
-- The server runs it to hold the shell's true position. The Chimera's own client runs the same code to
-- predict its body between server updates, then rewinds and replays when the server disagrees.
-- Everything here must stay deterministic: same state + same input + same map = same result.
local Config = require(script.Parent.Config)

local S = Config.Shell

local ShellMotor = {}

ShellMotor.DT = 1 / S.TickRate

export type State = { pos: Vector3, vel: Vector3, grounded: boolean }
-- speedScale (default 1) comes from the server: slows lower it, staggers and roots set it to 0.
export type Input = { mx: number, mz: number, jump: boolean, yaw: number, speedScale: number? }

local SKIN = 0.05
local BODY_SIZE = Vector3.new(S.Width, S.Height - S.StepHeight, S.Width)
local BODY_OFFSET = Vector3.new(0, S.StepHeight + BODY_SIZE.Y / 2, 0)
local PROBE_SIZE = Vector3.new(S.Width - 0.2, 0.2, S.Width - 0.2)
local MIN_FLOOR_NORMAL_Y = 0.6

local params: RaycastParams? = nil
local obstacles: { Instance } = {}

-- Shells collide with the map (walls, floors, closed doors, props) and with merc bodies.
function ShellMotor.params(): RaycastParams
	if not params then
		local p = RaycastParams.new()
		p.FilterType = Enum.RaycastFilterType.Include
		p.FilterDescendantsInstances = { workspace:WaitForChild("Map"), table.unpack(obstacles) }
		p.RespectCanCollide = true
		p.IgnoreWater = true
		params = p
	end
	return params :: RaycastParams
end

-- The merc characters a shell can't walk through. Both the server and the Chimera's client keep this
-- current, so prediction and the server agree (up to where each sees the mercs).
function ShellMotor.setObstacles(list: { Instance })
	obstacles = list
	if params then
		params.FilterDescendantsInstances = { workspace:WaitForChild("Map"), table.unpack(list) }
	end
end

function ShellMotor.new(feet: Vector3): State
	return { pos = feet, vel = Vector3.zero, grounded = true }
end

function ShellMotor.copy(s: State): State
	return { pos = s.pos, vel = s.vel, grounded = s.grounded }
end

-- Collide and slide: sweep the body (from step height up) along the move, sliding along whatever it hits.
local function slide(pos: Vector3, displacement: Vector3, p: RaycastParams): Vector3
	local remaining = displacement
	for _ = 1, 4 do
		local length = remaining.Magnitude
		if length < 1e-4 then
			break
		end
		local dir = remaining / length
		local hit = workspace:Blockcast(CFrame.new(pos + BODY_OFFSET), BODY_SIZE, dir * (length + SKIN), p)
		if not hit then
			return pos + remaining
		end
		local travel = math.max(0, hit.Distance - SKIN)
		pos += dir * travel
		remaining -= dir * travel
		local normal = Vector3.new(hit.Normal.X, 0, hit.Normal.Z)
		if normal.Magnitude < 1e-3 then
			break
		end
		normal = normal.Unit
		remaining -= normal * remaining:Dot(normal)
	end
	return pos
end

-- Height of the walkable floor under the shell, searching from StepHeight above the feet to `drop` below.
local function floorBelow(pos: Vector3, drop: number, p: RaycastParams): number?
	local start = pos + Vector3.new(0, S.StepHeight, 0)
	local hit = workspace:Blockcast(CFrame.new(start), PROBE_SIZE, Vector3.new(0, -(S.StepHeight + drop), 0), p)
	if hit and hit.Normal.Y >= MIN_FLOOR_NORMAL_Y then
		return start.Y - PROBE_SIZE.Y / 2 - hit.Distance
	end
	return nil
end

function ShellMotor.step(s: State, input: Input, dt: number, p: RaycastParams?): State
	local rp = p or ShellMotor.params()
	local pos, vel, grounded = s.pos, s.vel, s.grounded

	local mx, mz = input.mx, input.mz
	local magnitude = math.sqrt(mx * mx + mz * mz)
	if magnitude > 1 then
		mx /= magnitude
		mz /= magnitude
	end
	local scale = math.clamp(input.speedScale or 1, 0, 1)
	local speed = S.WalkSpeed * scale
	local wish = Vector3.new(mx * speed, 0, mz * speed)
	local horizontal = Vector3.new(vel.X, 0, vel.Z)
	local maxChange = (if grounded then S.GroundAccel else S.AirAccel) * dt
	local change = wish - horizontal
	if change.Magnitude <= maxChange then
		horizontal = wish
	else
		horizontal += change.Unit * maxChange
	end

	local vy = vel.Y
	if grounded and input.jump and scale > 0 then
		vy = S.JumpVelocity
		grounded = false
	end

	local before = pos
	pos = slide(pos, horizontal * dt, rp)
	local moved = pos - before
	horizontal = Vector3.new(moved.X, 0, moved.Z) / dt

	if grounded then
		-- Stay on the floor, stepping up or down anything up to StepHeight.
		local floorY = floorBelow(pos, S.StepHeight, rp)
		if floorY then
			pos = Vector3.new(pos.X, floorY, pos.Z)
			vy = 0
		else
			grounded = false
		end
	end

	if not grounded then
		vy -= S.Gravity * dt
		local dy = vy * dt
		if dy > 0 then
			local hit = workspace:Blockcast(CFrame.new(pos + BODY_OFFSET), BODY_SIZE, Vector3.new(0, dy + SKIN, 0), rp)
			if hit then
				pos += Vector3.new(0, math.max(0, hit.Distance - SKIN), 0)
				vy = 0
			else
				pos += Vector3.new(0, dy, 0)
			end
		else
			local floorY = floorBelow(pos, -dy, rp)
			if floorY then
				pos = Vector3.new(pos.X, floorY, pos.Z)
				vy = 0
				grounded = true
			else
				pos += Vector3.new(0, dy, 0)
			end
		end
	end

	return { pos = pos, vel = Vector3.new(horizontal.X, vy, horizontal.Z), grounded = grounded }
end

return ShellMotor
