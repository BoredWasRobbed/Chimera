-- Cameras mercs shoot out: one hit breaks a camera for 45 s. A broken camera is dark for everyone, the
-- Chimera can't hop to it, and if the Chimera was watching through it, it's thrown to a linked camera
-- with 2 s of static (see Chimera). The camera model's BrokenUntil attribute (server time) tells clients.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Net = require(ReplicatedStorage.Shared.Net)
local Cues = require(script.Parent.Cues)
local MapData = require(script.Parent.MapData)

local SecurityCameras = {}

local brokenUntil: { [string]: number } = {}
local saved: { [BasePart]: Color3 } = {}
local listeners: { (string) -> () } = {}
local combat: RemoteEvent

function SecurityCameras.isBroken(id: string): boolean
	return (brokenUntil[id] or 0) > os.clock()
end

function SecurityCameras.onBroken(listener: (string) -> ())
	table.insert(listeners, listener)
end

local function setDark(id: string, dark: boolean)
	local cam = MapData.cameras[id]
	if not cam then
		return
	end
	for _, name in { "Lens", "Housing" } do
		local part = cam.model:FindFirstChild(name)
		if part and part:IsA("BasePart") then
			if not saved[part] then
				saved[part] = part.Color
			end
			part.Color = if dark then Color3.fromRGB(12, 12, 12) else saved[part]
		end
	end
end

function SecurityCameras.breakCamera(id: string): boolean
	local cam = MapData.cameras[id]
	if not cam or SecurityCameras.isBroken(id) then
		return false
	end
	local seconds = Config.Combat.CameraBrokenSeconds
	local untilTime = os.clock() + seconds
	brokenUntil[id] = untilTime
	cam.model:SetAttribute("BrokenUntil", workspace:GetServerTimeNow() + seconds)
	setDark(id, true)
	Cues.emit("CameraBroken", cam.origin, 40)
	combat:FireAllClients("sparks", cam.origin)
	for _, listener in listeners do
		task.spawn(listener, id)
	end
	task.delay(seconds, function()
		if brokenUntil[id] == untilTime then
			brokenUntil[id] = nil
			cam.model:SetAttribute("BrokenUntil", nil)
			setDark(id, false)
		end
	end)
	return true
end

-- The camera a model part belongs to, if any.
function SecurityCameras.idOf(instance: Instance): string?
	local model = instance:FindFirstAncestorOfClass("Model")
	local id = model and model:GetAttribute("CameraId")
	return if type(id) == "string" then id else nil
end

function SecurityCameras.init()
	combat = Net.get("Combat")
end

return SecurityCameras
