-- Other players' shells as this merc perceives them. The server sends a shell's position only while
-- this merc can perceive it ("show"/"update"), then "hide" or "collapse". Between updates the body is
-- interpolated slightly in the past, so movement stays smooth at the server's send rate.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage.Shared.Config)
local Net = require(ReplicatedStorage.Shared.Net)
local ShellRig = require(ReplicatedStorage.Shared.ShellRig)

type Snapshot = { t: number, pos: Vector3, yaw: number, speed: number }
type View = {
	model: Model,
	snapshots: { Snapshot },
	visibility: string,
	phase: number,
	highlight: Highlight?,
	lastLook: string,
	lastAmount: number,
}

local ShellViews = {}

local views: { [string]: View } = {}
local folder: Folder

local function lerpAngle(a: number, b: number, t: number): number
	local d = (b - a + math.pi) % (2 * math.pi) - math.pi
	return a + d * t
end

local function sample(snapshots: { Snapshot }, t: number): (Vector3, number, number)
	local first = snapshots[1]
	if t <= first.t then
		return first.pos, first.yaw, first.speed
	end
	for i = #snapshots - 1, 1, -1 do
		local a, b = snapshots[i], snapshots[i + 1]
		if a.t <= t then
			local span = b.t - a.t
			local alpha = if span > 1e-4 then math.clamp((t - a.t) / span, 0, 1) else 1
			return a.pos:Lerp(b.pos, alpha), lerpAngle(a.yaw, b.yaw, alpha), a.speed + (b.speed - a.speed) * alpha
		end
	end
	local last = snapshots[#snapshots]
	return last.pos, last.yaw, last.speed
end

local function destroyView(id: string)
	local view = views[id]
	if view then
		views[id] = nil
		view.model:Destroy()
	end
end

local function collapse(id: string, pos: Vector3, yaw: number)
	local view = views[id]
	views[id] = nil
	local model = if view then view.model else ShellRig.build(`Collapse_{id}`)
	if not view then
		ShellRig.pose(model, CFrame.new(pos) * CFrame.Angles(0, yaw, 0), 0, 0, 0)
		ShellRig.setLook(model, "cloaked", 0.5)
		model.Parent = folder
	end
	if view and view.highlight then
		view.highlight:Destroy()
	end
	-- Falls apart: every part drops to the floor, tumbling, and fades.
	local info = TweenInfo.new(0.9, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	for _, part in model:GetChildren() do
		if part:IsA("BasePart") then
			local drop = CFrame.new(part.Position.X + (math.random() - 0.5) * 2, pos.Y + 0.3, part.Position.Z + (math.random() - 0.5) * 2)
				* CFrame.Angles(math.random() * 3, math.random() * 3, math.random() * 3)
			TweenService:Create(part, info, { CFrame = drop }):Play()
			TweenService:Create(part, TweenInfo.new(1.4), { Transparency = 1 }):Play()
		end
	end
	task.delay(1.5, function()
		model:Destroy()
	end)
end

local function setLook(view: View, speed: number)
	local look = if view.visibility == "Revealed" then "revealed" elseif view.visibility == "Exposed" then "exposed" else "cloaked"
	local amount = math.floor(math.clamp(speed / Config.Shell.WalkSpeed, 0, 1) * 5 + 0.5) / 5
	if look == "exposed" then
		amount = math.random() -- flicker
	end
	if look ~= view.lastLook or amount ~= view.lastAmount then
		ShellRig.setLook(view.model, look :: any, amount)
		view.lastLook = look
		view.lastAmount = amount
	end
	if look == "revealed" and not view.highlight then
		local highlight = Instance.new("Highlight")
		highlight.FillTransparency = 1
		highlight.OutlineColor = Color3.fromRGB(255, 25, 25)
		highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
		highlight.Parent = view.model
		view.highlight = highlight
	elseif look ~= "revealed" and view.highlight then
		view.highlight:Destroy()
		view.highlight = nil
	end
end

local function push(message: { any })
	local kind, id = message[1], message[2]
	if type(id) ~= "string" then
		return
	end
	if kind == "hide" then
		destroyView(id)
		return
	end
	local t, x, y, z, yaw = message[3], message[4], message[5], message[6], message[7]
	if type(t) ~= "number" or type(x) ~= "number" or type(y) ~= "number" or type(z) ~= "number" or type(yaw) ~= "number" then
		return
	end
	if kind == "collapse" then
		collapse(id, Vector3.new(x, y, z), yaw)
		return
	end
	local view = views[id]
	if not view then
		local model = ShellRig.build(`Shell_{id}`)
		model.Parent = folder
		view = { model = model, snapshots = {}, visibility = "Cloaked", phase = 0, highlight = nil, lastLook = "", lastAmount = -1 }
		views[id] = view
	end
	view.visibility = if type(message[9]) == "string" then message[9] else "Cloaked"
	table.insert(view.snapshots, { t = t, pos = Vector3.new(x, y, z), yaw = yaw, speed = tonumber(message[8]) or 0 })
	while #view.snapshots > 12 do
		table.remove(view.snapshots, 1)
	end
end

local function render(dt: number)
	local renderTime = workspace:GetServerTimeNow() - Config.Perception.InterpolationDelay
	local now = os.clock()
	for _, view in views do
		if #view.snapshots == 0 then
			continue
		end
		local pos, yaw, speed = sample(view.snapshots, renderTime)
		view.phase += dt * speed * 0.55
		ShellRig.pose(view.model, CFrame.new(pos) * CFrame.Angles(0, yaw, 0), view.phase, math.clamp(speed / Config.Shell.WalkSpeed, 0, 1), now)
		setLook(view, speed)
	end
end

function ShellViews.init(clientFolder: Folder)
	folder = Instance.new("Folder")
	folder.Name = "Shells"
	folder.Parent = clientFolder
	Net.get("ShellView").OnClientEvent:Connect(function(batch)
		if type(batch) ~= "table" then
			return
		end
		for _, message in batch do
			if type(message) == "table" then
				push(message)
			end
		end
	end)
	RunService.RenderStepped:Connect(render)
end

-- For tests: what this client currently draws.
function ShellViews.describe(): { [string]: any }
	local out = {}
	for id, view in views do
		local last = view.snapshots[#view.snapshots]
		out[id] = {
			visibility = view.visibility,
			pos = last and { math.floor(last.pos.X * 10) / 10, math.floor(last.pos.Y * 10) / 10, math.floor(last.pos.Z * 10) / 10 },
		}
	end
	return out
end

return ShellViews
