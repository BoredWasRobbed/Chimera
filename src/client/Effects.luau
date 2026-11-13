-- Public combat effects: tracers, muzzle flashes, explosions, Flash bursts, sparks, steam, alarms,
-- sensor darts, decoy flicker, and (for Scouts) System Leap trails. All drawn on this client only.
local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage.Shared.Config)
local Net = require(ReplicatedStorage.Shared.Net)

local Effects = {}

local player = Players.LocalPlayer
local folder: Folder

local function part(props: { [string]: any }): Part
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Material = Enum.Material.Neon
	for key, value in props do
		(p :: any)[key] = value
	end
	p.Parent = folder
	return p
end

local function fade(p: BasePart, seconds: number, props: { [string]: any }?)
	local goal = props or {}
	goal.Transparency = 1
	TweenService:Create(p, TweenInfo.new(seconds), goal):Play()
	Debris:AddItem(p, seconds + 0.05)
end

local function flashLight(position: Vector3, color: Color3, range: number, brightness: number, seconds: number)
	local holder = part({ Size = Vector3.new(0.1, 0.1, 0.1), CFrame = CFrame.new(position), Transparency = 1 })
	local light = Instance.new("PointLight")
	light.Color = color
	light.Range = range
	light.Brightness = brightness
	light.Shadows = false
	light.Parent = holder
	TweenService:Create(light, TweenInfo.new(seconds), { Brightness = 0 }):Play()
	Debris:AddItem(holder, seconds + 0.05)
end

function Effects.tracer(from: Vector3, to: Vector3, color: Color3?, width: number?)
	local length = (to - from).Magnitude
	if length < 0.1 then
		return
	end
	local p = part({
		Size = Vector3.new(width or 0.08, width or 0.08, length),
		CFrame = CFrame.lookAt(from, to) * CFrame.new(0, 0, -length / 2),
		Color = color or Color3.fromRGB(255, 235, 180),
		Transparency = 0.2,
	})
	fade(p, 0.08)
end

function Effects.muzzle(position: Vector3)
	flashLight(position, Color3.fromRGB(255, 210, 140), 10, 4, 0.06)
end

function Effects.explosion(position: Vector3, radius: number)
	local ball = part({ Shape = Enum.PartType.Ball, Size = Vector3.new(1, 1, 1), CFrame = CFrame.new(position), Color = Color3.fromRGB(255, 190, 110), Transparency = 0.1 })
	TweenService:Create(ball, TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Size = Vector3.one * radius * 2 }):Play()
	fade(ball, 0.5)
	flashLight(position, Color3.fromRGB(255, 180, 90), radius * 3, 6, 0.5)
end

function Effects.steam(position: Vector3, radius: number, seconds: number)
	local cloud = part({
		Shape = Enum.PartType.Ball,
		Size = Vector3.one * 2,
		CFrame = CFrame.new(position + Vector3.new(0, 2, 0)),
		Color = Color3.fromRGB(235, 240, 245),
		Material = Enum.Material.SmoothPlastic,
		Transparency = 0.35,
	})
	TweenService:Create(cloud, TweenInfo.new(0.4), { Size = Vector3.one * radius * 2 }):Play()
	task.delay(math.max(0, seconds - 0.8), function()
		fade(cloud, 0.8)
	end)
end

local function decoyParts(model: Instance): { BasePart }
	local out = {}
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") and d.Name ~= "HumanoidRootPart" then
			table.insert(out, d)
		end
	end
	return out
end

function Effects.decoyFlicker(model: Instance)
	local parts = decoyParts(model)
	task.spawn(function()
		for i = 1, 6 do
			for _, p in parts do
				p.LocalTransparencyModifier = if i % 2 == 1 then 0.8 else 0
			end
			task.wait(0.06)
		end
		for _, p in parts do
			p.LocalTransparencyModifier = 0
		end
	end)
end

function Effects.decoyFade(model: Instance)
	for _, p in decoyParts(model) do
		TweenService:Create(p, TweenInfo.new(0.35), { LocalTransparencyModifier = 1 }):Play()
	end
end

-- Scout passive: the path of a traversal move, seen through walls for a few seconds.
function Effects.trail(from: Vector3, to: Vector3, seconds: number)
	local a, b = from + Vector3.new(0, 3, 0), to + Vector3.new(0, 3, 0)
	local length = (b - a).Magnitude
	local beam = part({
		Size = Vector3.new(0.4, 0.4, math.max(length, 0.5)),
		CFrame = CFrame.lookAt(a, b) * CFrame.new(0, 0, -length / 2),
		Color = Color3.fromRGB(150, 255, 220),
		Transparency = 0.3,
	})
	local highlight = Instance.new("Highlight")
	highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
	highlight.FillColor = Color3.fromRGB(150, 255, 220)
	highlight.FillTransparency = 0.4
	highlight.OutlineTransparency = 1
	highlight.Parent = beam
	for _, at in { a, b } do
		local node = part({ Shape = Enum.PartType.Ball, Size = Vector3.one * 1.6, CFrame = CFrame.new(at), Color = Color3.fromRGB(150, 255, 220), Transparency = 0.2 })
		local h = highlight:Clone()
		h.Parent = node
		task.delay(seconds, function()
			fade(node, 0.4)
		end)
	end
	task.delay(seconds, function()
		fade(beam, 0.4)
	end)
end

function Effects.init(clientFolder: Folder)
	folder = Instance.new("Folder")
	folder.Name = "Effects"
	folder.Parent = clientFolder
	Net.get("Combat").OnClientEvent:Connect(function(kind, a, b, c, d)
		if kind == "shot" then
			-- Our own shots are drawn the moment we fire (see MercCombat).
			if a == player.UserId then
				return
			end
			local weapon = Config.Weapons[d]
			if typeof(b) ~= "Vector3" or type(c) ~= "table" then
				return
			end
			if not (weapon and weapon.Silenced) then
				Effects.muzzle(b)
			end
			for _, point in c do
				if typeof(point) == "Vector3" then
					Effects.tracer(b, point)
				end
			end
		elseif kind == "explosion" and typeof(a) == "Vector3" then
			Effects.explosion(a, tonumber(b) or 10)
		elseif kind == "flash" and typeof(b) == "Vector3" then
			flashLight(b, Color3.fromRGB(240, 245, 255), 24, 10, 0.2)
		elseif kind == "sparks" and typeof(a) == "Vector3" then
			flashLight(a, Color3.fromRGB(255, 230, 150), 8, 5, 0.25)
		elseif kind == "spark" and typeof(a) == "Vector3" then
			flashLight(a, Color3.fromRGB(150, 220, 255), 18, 8, 0.4)
		elseif kind == "steam" and typeof(a) == "Vector3" then
			Effects.steam(a, tonumber(b) or 7, tonumber(c) or 4)
		elseif kind == "alarm" and typeof(a) == "Vector3" then
			for i = 0, 3 do
				task.delay(i * 0.5, function()
					flashLight(a + Vector3.new(0, 1, 0), Color3.fromRGB(255, 170, 40), 16, 6, 0.3)
				end)
			end
		elseif kind == "dart" and typeof(a) == "Vector3" and typeof(b) == "Vector3" then
			Effects.tracer(a, b, Color3.fromRGB(150, 255, 220), 0.12)
		elseif kind == "dartPing" and typeof(a) == "Vector3" then
			flashLight(a, Color3.fromRGB(150, 255, 220), 16, 6, 0.6)
		elseif kind == "decoyFlicker" and typeof(a) == "Instance" then
			Effects.decoyFlicker(a)
		elseif kind == "decoyFade" and typeof(a) == "Instance" then
			Effects.decoyFade(a)
		end
	end)
	Net.get("MercEvents").OnClientEvent:Connect(function(kind, a, b, c)
		if kind == "trail" and typeof(a) == "Vector3" and typeof(b) == "Vector3" then
			Effects.trail(a, b, tonumber(c) or 4)
		end
	end)
end

return Effects
