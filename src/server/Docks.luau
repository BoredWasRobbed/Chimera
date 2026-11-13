-- Shell docks: each holds one dormant shell. A dock is "stocked", "booting" (the Chimera is mid-take:
-- the shell's eyes light red) or "empty" until it reprints 45 s after its shell left. A rebooted terminal
-- shuts its wing's docks down for the rest of the match, and Lockdown shuts down every dock: "offline".
-- Mercs don't get these states directly; Perception passes each change on to mercs who can see the dock.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local MapData = require(script.Parent.MapData)

export type DockState = "stocked" | "booting" | "empty" | "offline"

local Docks = {}

local states: { [string]: DockState } = {}
local reprintAt: { [string]: number } = {}
local listeners: { (string, DockState) -> () } = {}
local dormantHp: { [string]: number } = {}
local hitListeners: { (string, boolean) -> () } = {}

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
	dormantHp[id] = nil
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

-- Shut a dock down for the rest of the match: no shell to take, no reprint.
function Docks.shutDown(id: string)
	if not states[id] or states[id] == "offline" then
		return
	end
	reprintAt[id] = nil
	dormantHp[id] = nil
	set(id, "offline")
end

-- Every dock in one of these rooms.
function Docks.inRooms(rooms: { [string]: boolean }): { string }
	local out = {}
	for id, dock in MapData.docks do
		if rooms[dock.room] then
			table.insert(out, id)
		end
	end
	table.sort(out)
	return out
end

-- A new round: every dock stocked and online.
function Docks.reset()
	table.clear(reprintAt)
	table.clear(dormantHp)
	for id in MapData.docks do
		set(id, "stocked")
	end
end

-- listener(id, destroyed) runs whenever a dormant shell is hit, so the Chimera gets its alert.
function Docks.onHit(listener: (string, boolean) -> ())
	table.insert(hitListeners, listener)
end

-- Mercs smashing a dormant shell (300 HP). Destroying it empties the dock until it reprints.
function Docks.damage(id: string, amount: number): string?
	local state = states[id]
	if (state ~= "stocked" and state ~= "booting") or amount <= 0 then
		return nil
	end
	local hp = (dormantHp[id] or Config.Combat.DormantHP) - amount
	local destroyed = hp <= 0
	if destroyed then
		Docks.take(id)
	else
		dormantHp[id] = hp
	end
	for _, listener in hitListeners do
		task.spawn(listener, id, destroyed)
	end
	return if destroyed then "destroyed" else "hit"
end

return Docks
