-- Dormant shells in their docks, drawn on this client only. The server tells a merc about a dock only
-- when the merc can see it or stands near it, so this is what this player believes, not the truth.
-- The Chimera's client gets every change and uses these models as Take shell targets.
-- A dormant shell stands unformed, its panels hanging open (see ShellRig). While the Chimera boots it,
-- its frame glows and its panels twitch part-way shut; if the take is cancelled they fall open again.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)
local FacilityMap = require(ReplicatedStorage.Shared.FacilityMap)
local Net = require(ReplicatedStorage.Shared.Net)
local ShellRig = require(ReplicatedStorage.Shared.ShellRig)

type Boot = { startedAt: number, cancelledAt: number?, from: number }

local DockViews = {}

local RELAX_SECONDS = 0.4 -- a cancelled boot's panels falling open again
local SOLID = { Torso = true, Head = true, LeftArm = true, RightArm = true, LeftLeg = true, RightLeg = true }

local docks: { [string]: FacilityMap.DockInfo } = {}
local states: { [string]: string } = {}
local models: { [string]: Model } = {}
local boots: { [string]: Boot } = {}
local folder: Folder

-- How far a boot has drawn the panels in, how hard they twitch, and whether a cancelled one is over.
local function bootPose(boot: Boot, now: number): (number, number, boolean)
	if boot.cancelledAt then
		local p = math.clamp((now - boot.cancelledAt) / RELAX_SECONDS, 0, 1)
		return boot.from * (1 - p * p * (3 - 2 * p)), 0, p >= 1
	end
	local p = math.clamp((now - boot.startedAt) / Config.Interface.TakeShell.HoldSeconds, 0, 1)
	return ShellRig.PRIMED * p * p * (3 - 2 * p), p, false
end

local function ensureModel(id: string): Model?
	local dock = docks[id]
	if not dock then
		return nil
	end
	local model = models[id]
	if model then
		return model
	end
	model = ShellRig.build(`Dormant_{id}`)
	model:SetAttribute("TargetKind", "TakeShell")
	model:SetAttribute("TargetId", id)
	for _, part in model:GetChildren() do
		if part:IsA("BasePart") then
			-- Aimable by the Chimera, and its R6 blocks are solid for mercs walking into it.
			part.CanQuery = true
			part.CanCollide = SOLID[part.Name] == true
		end
	end
	ShellRig.setDormant(model, 0, 0, 0)
	ShellRig.pose(model, dock.spawn, 0, 0, 0)
	model.Parent = folder
	models[id] = model
	return model
end

local function apply(id: string, state: string)
	states[id] = state
	-- "offline": a shut-down dock (its wing's terminal was rebooted, or Lockdown) holds no usable shell.
	if state == "empty" or state == "offline" then
		boots[id] = nil
		local model = models[id]
		if model then
			models[id] = nil
			model:Destroy()
		end
		return
	end
	local model = ensureModel(id)
	if not model then
		return
	end
	local now = os.clock()
	local boot = boots[id]
	if state == "booting" then
		if not boot or boot.cancelledAt then
			boots[id] = { startedAt = now, cancelledAt = nil, from = 0 }
		end
	elseif boot and not boot.cancelledAt then
		-- Back to stocked: the boot was cancelled.
		boot.from = bootPose(boot, now)
		boot.cancelledAt = now
	end
	ShellRig.setLook(model, if state == "booting" then "booting" else "dormant")
end

local function animate()
	if next(boots) == nil then
		return
	end
	local now = os.clock()
	for id, boot in boots do
		local model, dock = models[id], docks[id]
		if not model or not dock then
			boots[id] = nil
			continue
		end
		local closure, twitch, done = bootPose(boot, now)
		ShellRig.setDormant(model, closure, twitch, now)
		ShellRig.pose(model, dock.spawn, 0, 0, now)
		if done then
			boots[id] = nil
		end
	end
end

function DockViews.init(clientFolder: Folder)
	folder = Instance.new("Folder")
	folder.Name = "Docks"
	folder.Parent = clientFolder
	docks = FacilityMap.docks()
	Net.get("DockView").OnClientEvent:Connect(function(batch)
		if type(batch) ~= "table" then
			return
		end
		for _, entry in batch do
			if type(entry) == "table" and type(entry[1]) == "string" and type(entry[2]) == "string" then
				apply(entry[1], entry[2])
			end
		end
	end)
	RunService.RenderStepped:Connect(animate)
end

function DockViews.state(id: string): string?
	return states[id]
end

function DockViews.all(): { [string]: string }
	return table.clone(states)
end

function DockViews.folder(): Folder
	return folder
end

return DockViews
