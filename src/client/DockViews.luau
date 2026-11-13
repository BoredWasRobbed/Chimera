-- Dormant shells in their docks, drawn on this client only. The server tells a merc about a dock only
-- when the merc can see it or stands near it, so this is what this player believes, not the truth.
-- The Chimera's client gets every change and uses these models as Take shell targets.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local FacilityMap = require(ReplicatedStorage.Shared.FacilityMap)
local Net = require(ReplicatedStorage.Shared.Net)
local ShellRig = require(ReplicatedStorage.Shared.ShellRig)

local DockViews = {}

local docks: { [string]: FacilityMap.DockInfo } = {}
local states: { [string]: string } = {}
local models: { [string]: Model } = {}
local folder: Folder

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
			-- Aimable by the Chimera, solid for mercs walking into it.
			part.CanQuery = true
			part.CanCollide = part.Name ~= "EyeL" and part.Name ~= "EyeR" and string.sub(part.Name, 1, 4) ~= "Tail"
		end
	end
	ShellRig.pose(model, dock.spawn, 0, 0, 0)
	model.Parent = folder
	models[id] = model
	return model
end

local function apply(id: string, state: string)
	states[id] = state
	if state == "empty" then
		local model = models[id]
		if model then
			models[id] = nil
			model:Destroy()
		end
		return
	end
	local model = ensureModel(id)
	if model then
		ShellRig.setLook(model, if state == "booting" then "booting" else "dormant")
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
