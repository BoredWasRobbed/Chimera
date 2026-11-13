-- The upload meter: the Chimera's progress, seen by both teams. It fills on its own over 8:00 during the
-- race, and MatchEvents move it: a down +10%, an assimilation +15%, a bleed-out +5%, a corrupted
-- terminal +3%, and a shell destroyed with the Chimera inside -10%. The server owns it; clients read the
-- Upload attribute on ReplicatedStorage.MatchState.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local MatchEvents = require(script.Parent.MatchEvents)
local MatchState = require(script.Parent.MatchState)

local Upload = {}

local U = Config.Upload

local value = 0
local running = false
local full: () -> () = function() end
local lastPublished = -1

local function publish(force: boolean?)
	local rounded = math.floor(value * 1000 + 0.5) / 1000
	if force or rounded ~= lastPublished then
		lastPublished = rounded
		MatchState.publish("Upload", rounded)
	end
end

function Upload.get(): number
	return value
end

function Upload.set(v: number)
	value = math.clamp(v, 0, 1)
	publish(true)
	if running and value >= 1 then
		full()
	end
end

function Upload.add(delta: number)
	if running then
		Upload.set(value + delta)
	end
end

function Upload.start()
	running = true
end

function Upload.stop()
	running = false
end

function Upload.reset()
	running = false
	value = 0
	publish(true)
end

function Upload.tick(dt: number)
	if running then
		value = math.min(1, value + dt / U.PassiveSeconds)
		publish(false)
		if value >= 1 then
			full()
		end
	end
end

-- onFull runs (every tick) while the meter is full during the race; Match starts the Upload finale.
function Upload.init(onFull: () -> ())
	full = onFull
	MatchEvents.connect("MercDowned", function()
		Upload.add(U.MercDowned)
	end)
	MatchEvents.connect("MercAssimilated", function()
		Upload.add(U.MercAssimilated)
	end)
	MatchEvents.connect("MercBledOut", function()
		Upload.add(U.MercBledOut)
	end)
	MatchEvents.connect("TerminalCorrupted", function()
		Upload.add(U.TerminalCorrupted)
	end)
	MatchEvents.connect("ShellDestroyed", function()
		Upload.add(U.ShellDestroyed)
	end)
	publish(true)
end

return Upload
