-- Match events, for the upload meter (milestone 3) and anything else that scores a match:
--   MercDowned      { victim, by }        the Chimera downed a merc (+10% upload)
--   MercAssimilated { victim, by }        the Chimera finished a downed merc (+15%)
--   MercBledOut     { victim }            a downed merc bled out (+5%)
--   ShellDestroyed  { agent, by }         a shell was destroyed with the Chimera inside (-10%)
--   TerminalCorrupted { terminal }        Corrupt landed on a terminal (+3%)
-- `victim` is the merc's character model; `victimPlayer` is set when it belongs to a player.
local RunService = game:GetService("RunService")

local MatchEvents = {}

local listeners: { [string]: { (any) -> () } } = {}

function MatchEvents.connect(name: string, listener: (any) -> ())
	listeners[name] = listeners[name] or {}
	table.insert(listeners[name], listener)
end

function MatchEvents.fire(name: string, data: { [string]: any })
	if RunService:IsStudio() then
		local detail = {}
		for key, value in data do
			local shown = if typeof(value) == "Instance" then value.Name elseif type(value) == "table" then (value.key or "table") else tostring(value)
			table.insert(detail, `{key}={shown}`)
		end
		print(`[Chimera] event {name}: {table.concat(detail, " ")}`)
	end
	for _, listener in listeners[name] or {} do
		task.spawn(listener, data)
	end
end

return MatchEvents
