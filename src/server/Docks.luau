-- Shell docks: each holds one dormant shell. A dock is "stocked", "booting" (the Chimera is mid-take:
-- the shell's eyes light red) or "empty" until it reprints 45 s after its shell left.
-- Mercs don't get these states directly; Perception passes each change on to mercs who can see the dock.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local MapData = require(script.Parent.MapData)

export type DockState = "stocked" | "booting" | "empty"

local Docks = {}

local states: { [string]: DockState } = {}
local reprintAt: { [string]: number } = {}
local listeners: { (string, DockState) -> () } = {}

local function set(id: string, state: DockState)
	if states[id] == state then
		return
	end
	states[id] = state
	for _, listener in listeners do
		task.spawn(listener, id, state)
	end
end

function Docks.init()
	for id in MapData.docks do
		states[id] = "stocked"
	end
end

function Docks.onChanged(listener: (string, DockState) -> ())
	table.insert(listeners, listener)
end

function Docks.state(id: string): DockState?
	return states[id]
end

function Docks.all(): { [string]: DockState }
	return table.clone(states)
end

-- Seconds until an empty dock reprints, by dock id.
function Docks.reprintTimes(): { [string]: number }
	local out = {}
	local now = os.clock()
	for id, at in reprintAt do
		out[id] = math.max(0, at - now)
	end
	return out
end

function Docks.setBooting(id: string, booting: boolean)
	if booting and states[id] == "stocked" then
		set(id, "booting")
	elseif not booting and states[id] == "booting" then
		set(id, "stocked")
	end
end

-- Empties the dock and starts its reprint timer. Returns false if there was no shell to take.
function Docks.take(id: string): boolean
	local state = states[id]
	if state ~= "stocked" and state ~= "booting" then
		return false
	end
	set(id, "empty")
	local at = os.clock() + Config.Shell.ReprintSeconds
	reprintAt[id] = at
	task.delay(Config.Shell.ReprintSeconds, function()
		if reprintAt[id] == at then
			reprintAt[id] = nil
			set(id, "stocked")
		end
	end)
	return true
end

return Docks
