-- Combat on the Chimera's side of a shell: HP (Phase Weave, 1,000), damage and destruction, the
-- visibility state, staggers, slows and roots, and the shell's own actions: Energy Claws, Assimilate and
-- System Leap. Static Decoy and Overload also work from a camera, so they live in Decoys and Traps.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Hitbox = require(ReplicatedStorage.Shared.Hitbox)
local Cues = require(script.Parent.Cues)
local Detection = require(script.Parent.Detection)
local Docks = require(script.Parent.Docks)
local Doors = require(script.Parent.Doors)
local Flashlights = require(script.Parent.Flashlights)
local Health = require(script.Parent.Health)
local MapData = require(script.Parent.MapData)
local MatchState = require(script.Parent.MatchState)
local Shells = require(script.Parent.Shells)
local Sight = require(script.Parent.Sight)

local M = Config.Modules
local V = Config.Visibility
local H = Config.Health

type LeapNode = { id: string, name: string, feet: CFrame }

local ShellCombat = {}

local notify: (any, { [string]: any }) -> () = function() end
local onDestroyed: (Shells.Shell, any) -> () = function() end
local leapNodes: { [string]: LeapNode } = {}
local floorParams = RaycastParams.new()
floorParams.FilterType = Enum.RaycastFilterType.Include

local function serverTime(clockTime: number): number
	return workspace:GetServerTimeNow() + (clockTime - os.clock())
end

local function chestOf(shell: Shells.Shell): Vector3
	return shell.state.pos + Vector3.new(0, 3, 0)
end

local function forwardOf(shell: Shells.Shell): Vector3
	return Vector3.new(-math.sin(shell.yaw), 0, -math.cos(shell.yaw))
end

local function toast(shell: Shells.Shell, text: string)
	notify(shell.owner, { type = "toast", text = text })
end

function ShellCombat.reveal(shell: Shells.Shell, seconds: number)
	shell.revealedUntil = math.max(shell.revealedUntil, os.clock() + seconds)
end

-- Overwatch Tag: outline the shell for living mercs.
function ShellCombat.tag(shell: Shells.Shell, seconds: number)
	shell.taggedUntil = math.max(shell.taggedUntil, os.clock() + seconds)
end

function ShellCombat.slow(shell: Shells.Shell, scale: number, seconds: number)
	local now = os.clock()
	if now >= shell.slowUntil or scale <= shell.slowScale then
		shell.slowScale = scale
		shell.slowUntil = math.max(if now >= shell.slowUntil then 0 else shell.slowUntil, now + seconds)
	end
end

local function cancelAssimilate(shell: Shells.Shell, reason: string)
	if shell.assimilating then
		shell.assimilating = nil
		notify(shell.owner, { type = "assimilate", state = "cancelled", reason = reason })
	end
end

local function cancelLeap(shell: Shells.Shell, reason: string)
	if shell.leap then
		shell.leap = nil
		notify(shell.owner, { type = "leap", state = "cancelled", reason = reason })
	end
end

-- Any stagger cancels Assimilate and a leap channel.
function ShellCombat.stagger(shell: Shells.Shell, seconds: number)
	shell.staggerUntil = math.max(shell.staggerUntil, os.clock() + seconds)
	cancelAssimilate(shell, "staggered")
	cancelLeap(shell, "staggered")
end

-- opts.by: the Player who did it (if any). opts.assault: an Assault hit, which slows the shell.
function ShellCombat.damage(shell: Shells.Shell, amount: number, opts: { by: Player?, assault: boolean? })
	if shell.dead or amount <= 0 then
		return
	end
	shell.hp -= amount
	ShellCombat.reveal(shell, V.HitRevealSeconds)
	if opts.assault then
		ShellCombat.slow(shell, Config.Gear.AssaultSlow.Scale, Config.Gear.AssaultSlow.Seconds)
	end
	local a = shell.assimilating
	if a and a.startHp - shell.hp >= shell.maxHp * H.AssimilateCancelFraction then
		cancelAssimilate(shell, "damage")
	end
	if shell.hp <= 0 then
		shell.hp = 0
		shell.dead = true
		cancelAssimilate(shell, "destroyed")
		cancelLeap(shell, "destroyed")
		Cues.emit("ShellDestroyed", chestOf(shell), 80)
		onDestroyed(shell, opts.by)
	end
end

-- Flash: Reveal and stagger every shell in the burst.
function ShellCombat.flashAt(_player: Player, origin: Vector3, aim: Vector3)
	local F = Config.Flashlight
	for _, shell in Shells.all() do
		local chest = chestOf(shell)
		if not shell.dead and Hitbox.inCone(origin, aim, chest, F.FlashRange, F.FlashHalfAngle) and Sight.clear(origin, chest) then
			ShellCombat.reveal(shell, V.FlashRevealSeconds)
			ShellCombat.stagger(shell, F.FlashStagger)
		end
	end
end

-- Frag Grenade: heavy damage falling off to 30% at the edge, and a 1 s stagger.
function ShellCombat.explosion(center: Vector3, radius: number, damage: number, stagger: number, by: Player?)
	local origin = center + Vector3.new(0, 0.5, 0)
	for _, shell in Shells.all() do
		local chest = chestOf(shell)
		local distance = (chest - center).Magnitude
		if not shell.dead and distance <= radius and Sight.clear(origin, chest) then
			local falloff = 1 - 0.7 * (distance / radius)
			ShellCombat.damage(shell, damage * falloff, { by = by })
			ShellCombat.stagger(shell, stagger)
		end
	end
	for id, dock in MapData.docks do
		local chest = (dock.spawn * CFrame.new(0, 3, 0)).Position
		local distance = (chest - center).Magnitude
		if distance <= radius and Sight.clear(origin, chest, dock.model) then
			Docks.damage(id, damage * (1 - 0.7 * (distance / radius)))
		end
	end
end

-- Sensor Dart: outline the shell for every merc.
function ShellCombat.dartReveal(shell: Shells.Shell)
	ShellCombat.reveal(shell, V.DartRevealSeconds)
end

function ShellCombat.speedScale(shell: Shells.Shell): number
	local now = os.clock()
	if now < shell.staggerUntil or shell.assimilating or shell.leap then
		return 0
	end
	return if now < shell.slowUntil then shell.slowScale else 1
end

function ShellCombat.visibilityOf(shell: Shells.Shell): Shells.Visibility
	if shell.forcedVisibility then
		return shell.forcedVisibility
	end
	if os.clock() < shell.revealedUntil or shell.assimilating then
		return "Revealed"
	end
	return if shell.exposed then "Exposed" else "Cloaked"
end

-- Energy Claws: a 6-stud swipe every 0.8 s for 35, at the nearest standing merc in front.
-- Swipes also count toward breaking a weld. Attacking Reveals the shell.
function ShellCombat.attack(agent: any): string?
	local shell: Shells.Shell? = agent.shell
	if not shell or shell.dead then
		return nil
	end
	local now = os.clock()
	if now < shell.attackReadyAt or now < shell.staggerUntil or shell.assimilating or shell.leap then
		return nil
	end
	local claws = M.EnergyClaws
	shell.attackReadyAt = now + claws.Interval
	shell.anim = { kind = "attack", startedAt = now, seconds = 0.35 }
	ShellCombat.reveal(shell, V.AttackRevealSeconds)
	local chest = chestOf(shell)
	local forward = forwardOf(shell)
	local minDot = math.cos(math.rad(claws.HalfArc))
	Cues.emit("ClawSwipe", chest, 35)

	local target = nil
	for _, body in Health.near(chest, claws.Range + 1.5, false) do
		local offset = body.root.Position - chest
		local flat = Vector3.new(offset.X, 0, offset.Z)
		if math.abs(offset.Y) < 4 and (flat.Magnitude < 1 or forward:Dot(flat.Unit) >= minDot) then
			target = body
			break
		end
	end
	local result = nil
	if target then
		result = Health.damage(target.model, claws.Damage, { canDown = true, by = agent })
	end
	for id, door in MapData.doors do
		if Doors.isWelded(id) then
			local offset = door.closed.Position - chest
			local flat = Vector3.new(offset.X, 0, offset.Z)
			if flat.Magnitude <= claws.Range + 1 and (flat.Magnitude < 1 or forward:Dot(flat.Unit) >= minDot) then
				Doors.weldDamage(id, claws.Interval)
			end
		end
	end
	return result
end

-- Assimilate: hold 3 s on a downed merc in reach, Revealed and rooted the whole time.
function ShellCombat.beginAssimilate(agent: any): boolean
	local shell: Shells.Shell? = agent.shell
	if not shell or shell.dead or shell.assimilating or shell.leap then
		return false
	end
	if os.clock() < shell.staggerUntil then
		toast(shell, "Staggered")
		return false
	end
	local target = Health.near(chestOf(shell), H.AssimilateRange, true)[1]
	if not target then
		toast(shell, "No downed merc in reach")
		return false
	end
	shell.assimilating = { body = target, startHp = shell.hp, endsAt = os.clock() + H.AssimilateSeconds }
	shell.anim = { kind = "assimilate", startedAt = os.clock(), seconds = H.AssimilateSeconds }
	notify(agent, { type = "assimilate", state = "started", endsAt = serverTime(shell.assimilating.endsAt), name = target.model:GetAttribute("MercTag") })
	return true
end

function ShellCombat.cancelAssimilate(agent: any)
	if agent.shell then
		cancelAssimilate(agent.shell, "released")
	end
end

local function floorBelow(point: Vector3): Vector3?
	local hit = workspace:Raycast(point, Vector3.new(0, -60, 0), floorParams)
	return if hit then hit.Position else nil
end

local function buildLeapNodes()
	floorParams.FilterDescendantsInstances = { workspace:WaitForChild("Map") }
	for id, cam in MapData.cameras do
		local flat = Vector3.new(-math.sin(cam.baseYaw), 0, -math.cos(cam.baseYaw))
		local floor = floorBelow(cam.origin + flat * 4)
		if floor then
			leapNodes[id] = { id = id, name = cam.displayName, feet = CFrame.lookAt(floor, floor + flat) }
		end
	end
	for id, terminal in MapData.terminals do
		local console = terminal.model.PrimaryPart
		if console then
			local look = console.CFrame.LookVector
			local flat = Vector3.new(look.X, 0, look.Z).Unit
			local floor = floorBelow(console.Position + flat * 4 + Vector3.new(0, 2, 0))
			if floor then
				leapNodes[id] = { id = id, name = terminal.displayName, feet = CFrame.lookAt(floor, floor + flat) }
			end
		end
	end
end

function ShellCombat.leapNodes(): { [string]: LeapNode }
	return leapNodes
end

-- System Leap: to a camera or terminal within 80 studs. 2 s channel (rooted), 25 s cooldown.
function ShellCombat.beginLeap(agent: any, nodeId: any): boolean
	local shell: Shells.Shell? = agent.shell
	if not shell or shell.dead or shell.leap or shell.assimilating then
		return false
	end
	local now = os.clock()
	if now < shell.leapReadyAt then
		toast(shell, string.format("System Leap ready in %d s", math.ceil(shell.leapReadyAt - now)))
		return false
	end
	if now < shell.staggerUntil then
		toast(shell, "Staggered")
		return false
	end
	local node = if type(nodeId) == "string" then leapNodes[nodeId] else nil
	if not node then
		toast(shell, "No leap target")
		return false
	end
	if (node.feet.Position - shell.state.pos).Magnitude > M.SystemLeap.Range then
		toast(shell, "Too far to leap")
		return false
	end
	shell.leap = { node = node, from = shell.state.pos, endsAt = now + M.SystemLeap.Channel }
	shell.anim = { kind = "leap", startedAt = now, seconds = M.SystemLeap.Channel }
	Cues.emit("LeapCharge", chestOf(shell), 30)
	notify(agent, { type = "leap", state = "started", target = node.name, endsAt = serverTime(shell.leap.endsAt) })
	return true
end

local function finishLeap(shell: Shells.Shell)
	local leap = shell.leap
	shell.leap = nil
	shell.anim = nil
	local from = shell.state.pos
	Shells.teleport(shell, leap.node.feet)
	shell.leapReadyAt = os.clock() + M.SystemLeap.Cooldown * MatchState.cooldownScale()
	Cues.emit("LeapLand", leap.node.feet.Position + Vector3.new(0, 3, 0), 30)
	-- Every traversal leaves a trail the Scout can see.
	Detection.sendTrail(from, leap.node.feet.Position)
	notify(shell.owner, { type = "leap", state = "done", target = leap.node.name })
end

local function sendStatus(shell: Shells.Shell, force: boolean)
	local now = os.clock()
	local status = {
		type = "shellStatus",
		hp = math.ceil(shell.hp),
		maxHp = shell.maxHp,
		visibility = shell.visibility,
		speedScale = shell.speedScale,
		staggered = now < shell.staggerUntil,
		attackReadyAt = serverTime(shell.attackReadyAt),
		leapReadyAt = serverTime(shell.leapReadyAt),
	}
	local key = `{status.hp}|{status.visibility}|{status.speedScale}|{status.staggered}|{math.floor(status.leapReadyAt)}`
	if force or key ~= shell.statusKey or now - shell.statusSentAt > 1 then
		shell.statusKey = key
		shell.statusSentAt = now
		notify(shell.owner, status)
	end
end

function ShellCombat.update(_dt: number)
	local now = os.clock()
	for _, shell in Shells.all() do
		if shell.dead then
			continue
		end
		local feet = shell.state.pos
		shell.exposed = Flashlights.covers(feet + Vector3.new(0, 3, 0), V.ExposeRange)
			or Flashlights.covers(feet + Vector3.new(0, 4.6, 0), V.ExposeRange)
		shell.visibility = ShellCombat.visibilityOf(shell)

		local a = shell.assimilating
		if a then
			local target = a.body
			if target.eliminated or not target.downed or (target.root.Position - (feet + Vector3.new(0, 3, 0))).Magnitude > H.AssimilateRange + 2 then
				cancelAssimilate(shell, "target lost")
			elseif now >= a.endsAt then
				shell.assimilating = nil
				shell.anim = nil
				Health.eliminate(target, "assimilated", shell.owner)
				notify(shell.owner, { type = "assimilate", state = "done", name = target.model:GetAttribute("MercTag") })
			end
		end
		if shell.leap and now >= shell.leap.endsAt then
			finishLeap(shell)
		end
		if shell.anim and now - shell.anim.startedAt > shell.anim.seconds then
			shell.anim = nil
		end
		shell.speedScale = ShellCombat.speedScale(shell)
		sendStatus(shell, false)
	end
end

function ShellCombat.statusOf(shell: Shells.Shell)
	sendStatus(shell, true)
end

-- send(agent, message) reaches the Chimera's client; destroyed(shell, by) hands a destroyed shell back
-- to the Chimera module.
function ShellCombat.init(send: (any, { [string]: any }) -> (), destroyed: (Shells.Shell, any) -> ())
	notify = send
	onDestroyed = destroyed
	buildLeapNodes()
end

return ShellCombat
