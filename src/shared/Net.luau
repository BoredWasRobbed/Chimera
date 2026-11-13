-- Remote names, created by the server at startup and fetched by clients.
-- Anything about the Chimera that a merc's client receives goes through ShellView, DockView or Cue,
-- and the server only fires those to mercs who can perceive the thing (see server/Perception).
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Net = {}

local DEFINITIONS = {
	ChimeraAction = "RemoteEvent", -- Chimera client -> server: hops, Interface, holds
	ChimeraState = "RemoteEvent", -- server -> Chimera client only
	ShellInput = "UnreliableRemoteEvent", -- Chimera client -> server: movement inputs
	ShellAuth = "UnreliableRemoteEvent", -- server -> Chimera client: authoritative shell state
	ShellView = "RemoteEvent", -- server -> mercs who perceive a shell
	DockView = "RemoteEvent", -- server -> clients: dock contents (perception-gated for mercs)
	Cue = "RemoteEvent", -- server -> clients in earshot of a tell
	MercSprint = "RemoteEvent", -- merc client -> server
	MercState = "RemoteEvent", -- server -> merc client: stamina
	Debug = "RemoteEvent", -- Studio only
}

local folder: Folder? = nil

function Net.init()
	assert(RunService:IsServer(), "Net.init runs on the server")
	local f = Instance.new("Folder")
	f.Name = "Remotes"
	for name, className in DEFINITIONS do
		local remote = Instance.new(className)
		remote.Name = name
		remote.Parent = f
	end
	f.Parent = ReplicatedStorage
	folder = f
end

function Net.get(name: string): any
	assert(DEFINITIONS[name], `unknown remote {name}`)
	if not folder then
		assert(not RunService:IsServer(), "call Net.init before Net.get on the server")
		folder = ReplicatedStorage:WaitForChild("Remotes") :: Folder
	end
	return (folder :: Folder):WaitForChild(name)
end

return Net
