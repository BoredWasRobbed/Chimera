-- Merc health, owned by the server. 100 HP, no regen, one Stim per life (+40 over 3 s). At 0 HP a merc
-- is downed: only the Chimera's claws can do that (traps stop at 1 HP). A downed merc crawls at 30%
-- speed and bleeds out after 45, then 30, then 15 s. A teammate revives by holding the prompt (5 s,
-- Medic 2.5 s) and the merc gets up with 30 HP; the Chimera finishes them with Assimilate.
-- Works for player characters and for Studio test dummies alike. The Humanoid's own Health is unused.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local MatchEvents = require(script.Parent.MatchEvents)

local H = Config.Health

export type Body = {
	model: Model,
	player: Player?,
	key: string,
	humanoid: Humanoid,
	root: BasePart,
	hp: number,
	downed: boolean,
	bleedEndsAt: number,
	stimAvailable: boolean,
	stimRemaining: number,
	prompt: ProximityPrompt,
	holdStarts: { [Player]: number },
	eliminated: boolean,
	rootJointC0: CFrame?,
	jumpPower: number,
}

local Health = {}

local bodies: { [Model]: Body } = {}
local downCounts: { [string]: number } = {}
local onEliminated: (Body, string) -> () = function() end

local function serverTime(clockTime: number): number
	return workspace:GetServerTimeNow() + (clockTime - os.clock())
end

local function publish(body: Body)
	local m = body.model
	m:SetAttribute("HP", math.ceil(body.hp))
	m:SetAttribute("MaxHP", H.MercMax)
	m:SetAttribute("Downed", body.downed)
	m:SetAttribute("BleedEndsAt", if body.downed then serverTime(body.bleedEndsAt) else 0)
	m:SetAttribute("Stim", body.stimAvailable)
end

-- Lying face down: tilt the torso forward at the root joint and lower it. Set on the server, so it
-- replicates to every client, including the one simulating the body.
local function setDownedPose(body: Body, downed: boolean)
	local joint = body.root:FindFirstChild("RootJoint")
	if not joint or not joint:IsA("Motor6D") then
		return
	end
	if downed then
		body.rootJointC0 = body.rootJointC0 or joint.C0
		joint.C0 = CFrame.new(0, -2.2, 0) * CFrame.Angles(math.rad(-80), 0, 0) * (body.rootJointC0 :: CFrame)
	elseif body.rootJointC0 then
		joint.C0 = body.rootJointC0
	end
end

local function bodyOfPlayer(player: Player): Body?
	local character = player.Character
	return if character then bodies[character] else nil
end

function Health.revive(body: Body)
	if not body.downed or body.eliminated then
		return
	end
	body.downed = false
	body.hp = H.ReviveHealth
	body.prompt.Enabled = false
	table.clear(body.holdStarts)
	setDownedPose(body, false)
	body.humanoid.JumpPower = body.jumpPower
	publish(body)
end

local function tryRevive(body: Body, reviver: Player)
	local started = body.holdStarts[reviver]
	body.holdStarts[reviver] = nil
	if not body.downed or body.eliminated or reviver == body.player then
		return
	end
	if reviver:GetAttribute("Role") ~= "Merc" then
		return
	end
	local helper = bodyOfPlayer(reviver)
	if not helper or helper.downed or helper.eliminated then
		return
	end
	if (helper.root.Position - body.root.Position).Magnitude > H.ReviveRange + 3 then
		return
	end
	local required = if reviver:GetAttribute("Class") == "Medic" then H.MedicReviveSeconds else H.ReviveSeconds
	if not started or os.clock() - started < required - 0.25 then
		return
	end
	Health.revive(body)
end

function Health.register(model: Model, player: Player?): Body?
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	local root = model:FindFirstChild("HumanoidRootPart")
	if not humanoid or not root or not root:IsA("BasePart") then
		return nil
	end
	humanoid.BreakJointsOnDeath = false
	humanoid.MaxHealth = H.MercMax
	humanoid.Health = H.MercMax
	humanoid.UseJumpPower = true

	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "Revive"
	prompt.ActionText = "Revive"
	prompt.ObjectText = if player then player.DisplayName else model.Name
	prompt.HoldDuration = H.ReviveSeconds
	prompt.MaxActivationDistance = H.ReviveRange
	prompt.RequiresLineOfSight = false
	prompt.Enabled = false
	prompt.Parent = root

	local body: Body = {
		model = model,
		player = player,
		key = if player then tostring(player.UserId) else model.Name,
		humanoid = humanoid,
		root = root,
		hp = H.MercMax,
		downed = false,
		bleedEndsAt = 0,
		stimAvailable = true,
		stimRemaining = 0,
		prompt = prompt,
		holdStarts = {},
		eliminated = false,
		rootJointC0 = nil,
		jumpPower = if humanoid.JumpPower > 0 then humanoid.JumpPower else 50,
	}
	prompt.PromptButtonHoldBegan:Connect(function(reviver)
		body.holdStarts[reviver] = os.clock()
	end)
	prompt.PromptButtonHoldEnded:Connect(function(reviver)
		task.defer(function()
			body.holdStarts[reviver] = nil
		end)
	end)
	prompt.Triggered:Connect(function(reviver)
		tryRevive(body, reviver)
	end)

	model:SetAttribute("MercTag", if player then player.DisplayName else model.Name)
	bodies[model] = body
	publish(body)
	model.AncestryChanged:Connect(function()
		if not model:IsDescendantOf(workspace) and bodies[model] == body then
			bodies[model] = nil
		end
	end)
	return body
end

function Health.get(model: Model?): Body?
	return if model then bodies[model] else nil
end

function Health.ofPlayer(player: Player): Body?
	return bodyOfPlayer(player)
end

function Health.all(): { [Model]: Body }
	return bodies
end

function Health.isDowned(model: Model?): boolean
	local body = Health.get(model)
	return body ~= nil and body.downed
end

local function down(body: Body, by: any)
	body.downed = true
	body.hp = 0
	body.stimRemaining = 0
	local count = (downCounts[body.key] or 0) + 1
	downCounts[body.key] = count
	body.bleedEndsAt = os.clock() + H.BleedOutSeconds[math.min(count, #H.BleedOutSeconds)]
	setDownedPose(body, true)
	body.humanoid.JumpPower = 0
	body.prompt.Enabled = true
	publish(body)
	MatchEvents.fire("MercDowned", { victim = body.model, victimPlayer = body.player, by = by })
end

-- canDown: only the Chimera's attacks can down a merc; everything else stops at 1 HP.
-- Returns "downed", "hit" or nil (no effect).
function Health.damage(model: Model, amount: number, opts: { canDown: boolean, by: any? }): string?
	local body = bodies[model]
	if not body or body.eliminated or body.downed or amount <= 0 then
		return nil
	end
	local hp = body.hp - amount
	if opts.canDown then
		if hp <= 0 then
			down(body, opts.by)
			return "downed"
		end
	else
		hp = math.max(hp, H.TrapFloor)
	end
	body.hp = hp
	publish(body)
	return "hit"
end

function Health.heal(model: Model, amount: number)
	local body = bodies[model]
	if not body or body.eliminated or body.downed or amount <= 0 or body.hp >= H.MercMax then
		return
	end
	local before = math.ceil(body.hp)
	body.hp = math.min(H.MercMax, body.hp + amount)
	if math.ceil(body.hp) ~= before then
		publish(body)
	end
end

function Health.useStim(player: Player): boolean
	local body = bodyOfPlayer(player)
	if not body or body.downed or body.eliminated or not body.stimAvailable then
		return false
	end
	body.stimAvailable = false
	body.stimRemaining = H.StimHeal
	publish(body)
	return true
end

-- reason: "assimilated" or "bledOut".
function Health.eliminate(body: Body, reason: string, by: any?)
	if body.eliminated then
		return
	end
	body.eliminated = true
	body.prompt.Enabled = false
	bodies[body.model] = nil
	local event = if reason == "assimilated" then "MercAssimilated" else "MercBledOut"
	MatchEvents.fire(event, { victim = body.model, victimPlayer = body.player, by = by })
	onEliminated(body, reason)
end

-- Bodies standing (not downed) or downed within `radius` of a point, nearest first.
function Health.near(position: Vector3, radius: number, downed: boolean): { Body }
	local out = {}
	for _, body in bodies do
		if not body.eliminated and body.downed == downed then
			local d = (body.root.Position - position).Magnitude
			if d <= radius then
				table.insert(out, body)
			end
		end
	end
	table.sort(out, function(a, b)
		return (a.root.Position - position).Magnitude < (b.root.Position - position).Magnitude
	end)
	return out
end

function Health.tick(dt: number)
	local now = os.clock()
	for _, body in bodies do
		if body.eliminated then
			continue
		end
		if body.downed then
			if now >= body.bleedEndsAt then
				Health.eliminate(body, "bledOut")
			end
		elseif body.stimRemaining > 0 then
			local amount = math.min(body.stimRemaining, H.StimHeal / H.StimSeconds * dt)
			body.stimRemaining -= amount
			Health.heal(body.model, amount)
		end
	end
end

-- Studio tests: a fresh match for bleed-out timers.
function Health.resetDownCounts()
	table.clear(downCounts)
end

function Health.init(eliminated: (Body, string) -> ())
	onEliminated = eliminated
end

return Health
