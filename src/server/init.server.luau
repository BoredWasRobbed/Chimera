-- Server entry point. Rojo syncs src/server to ServerScriptService.Server.
-- ModuleScripts added to src/server become children of this script.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local version = require(ReplicatedStorage.Shared.Version)

print(`[Chimera] server running {version}`)
