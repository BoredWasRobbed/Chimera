-- Client entry point. Rojo syncs src/client to StarterPlayer.StarterPlayerScripts.Client.
-- ModuleScripts added to src/client become children of this script.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local version = require(ReplicatedStorage.Shared.Version)

print(`[Chimera] client running {version}`)
