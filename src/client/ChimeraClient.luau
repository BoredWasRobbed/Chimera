-- The Chimera player's client: follows the server's ChimeraState, switches between FacilityView and
-- ShellControl, and owns the shared parts of the HUD: energy, the Interface prompt and hold progress.
-- E is the one contextual Interface button; hold Q leaves a shell.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Config = require(ReplicatedStorage.Shared.Config)
local FacilityMap = require(ReplicatedStorage.Shared.FacilityMap)
local Net = require(ReplicatedStorage.Shared.Net)
local FacilityView = require(script.Parent.FacilityView)
local Hud = require(script.Parent.Hud)
local ShellControl = require(script.Parent.ShellControl)

local ChimeraClient = {}

local ACTIONS = {
	Blackout = { label = "Blackout", hold = false },
	LockDoor = { label = "Lock door", hold = false },
	CorruptTerminal = { label = "Corrupt terminal", hold = true },
	TakeShell = { label = "Take shell", hold = true },
}

local LEFT_REASONS = {
	energy = "Out of energy: back to the cameras",
	fell = "Shell lost: back to the cameras",
}

type LocalHold = { kind: string, id: string?, startedAt: number, seconds: number }

local running = false
local mode = "facility"
local cameraId: string? = nil
local energy, rate, energyAt = Config.Chimera.EnergyStart, 0, os.clock()
local hold: LocalHold? = nil
local actionRemote: RemoteEvent
local names: { [string]: { [string]: string } } = { Blackout = {}, LockDoor = {}, CorruptTerminal = {}, TakeShell = {} }
local connections: { RBXScriptConnection } = {}
local ui: { [string]: any } = {}

local function energyNow(): number
	return math.clamp(energy + rate * (os.clock() - energyAt), 0, Config.Chimera.EnergyMax)
end

local function currentTarget()
	if mode == "shell" then
		return ShellControl.target()
	end
	return FacilityView.target()
end

local function promptAnchor(): Vector2
	return if mode == "shell" then ShellControl.promptAnchor() else FacilityView.promptAnchor()
end

local function showFacility(id: string)
	mode = "facility"
	cameraId = id
	ShellControl.stop()
	FacilityView.start(id)
end

local function onState(message: any)
	if type(message) ~= "table" or not running then
		return
	end
	local kind = message.type
	if kind == "snapshot" then
		energy, rate, energyAt = message.energy, message.rate, os.clock()
		hold = nil
		if message.shell then
			mode = "shell"
			FacilityView.stop()
			ShellControl.start(message.shell)
		else
			showFacility(message.cameraId)
		end
	elseif kind == "energy" then
		energy, rate, energyAt = message.value, message.rate, os.clock()
	elseif kind == "hopStart" then
		FacilityView.beginRelink(message.to)
	elseif kind == "hopDone" then
		cameraId = message.cameraId
		FacilityView.setCamera(message.cameraId)
		FacilityView.endRelink()
	elseif kind == "holdStart" then
		-- Releasing the key already sent a cancel, which the server handles after this hold began.
		if not hold or hold.kind ~= message.kind then
			hold = { kind = message.kind, id = message.id, startedAt = os.clock(), seconds = message.seconds }
		end
	elseif kind == "holdEnd" then
		if hold and hold.kind == message.kind then
			hold = nil
		end
	elseif kind == "shellTaken" then
		hold = nil
		mode = "shell"
		FacilityView.stop()
		ShellControl.start(message)
	elseif kind == "shellLeft" then
		hold = nil
		showFacility(message.cameraId)
		local reason = LEFT_REASONS[message.reason]
		if reason then
			Hud.toast(reason)
		end
	elseif kind == "toast" then
		Hud.toast(message.text)
	end
end

local function requestHop(id: string)
	if running and mode == "facility" then
		actionRemote:FireServer("hop", id)
	end
end

local function onInputBegan(input: InputObject, processed: boolean)
	if not running or processed then
		return
	end
	if input.KeyCode == Enum.KeyCode.E then
		local target = currentTarget()
		local action = target and ACTIONS[target.kind]
		if not target or not action then
			return
		end
		if action.hold then
			hold = { kind = target.kind, id = target.id, startedAt = os.clock(), seconds = Config.Interface[target.kind].HoldSeconds }
			actionRemote:FireServer("holdBegin", { kind = target.kind, id = target.id })
		else
			actionRemote:FireServer("interface", { kind = target.kind, id = target.id })
		end
	elseif input.KeyCode == Enum.KeyCode.Q and mode == "shell" then
		hold = { kind = "Leave", id = nil, startedAt = os.clock(), seconds = Config.Shell.LeaveHoldSeconds }
		actionRemote:FireServer("leaveBegin")
	end
end

local function onInputEnded(input: InputObject)
	if not running then
		return
	end
	if input.KeyCode == Enum.KeyCode.E and hold and hold.kind ~= "Leave" then
		hold = nil
		actionRemote:FireServer("holdCancel")
	elseif input.KeyCode == Enum.KeyCode.Q and hold and hold.kind == "Leave" then
		hold = nil
		actionRemote:FireServer("leaveCancel")
	end
end

local function targetName(kind: string, id: string): string
	return names[kind] and names[kind][id] or id
end

local function render()
	local value = energyNow()
	ui.setEnergy(value / Config.Chimera.EnergyMax)
	ui.energyLabel.Text = string.format("ENERGY %d", math.floor(value + 0.5))
	if mode == "shell" then
		local drain = -rate
		ui.rateLabel.Text = if drain > 0 then string.format("-%g/s  ·  %ds left", drain, math.floor(value / drain)) else "no drain"
	else
		ui.rateLabel.Text = if rate > 0 then string.format("+%g/s", rate) else "full"
	end

	local prompt = ui.prompt
	local target = currentTarget()
	local text, color, progress = nil, Hud.CYAN, nil
	if hold then
		local label = if hold.kind == "Leave" then "Leaving shell" else ACTIONS[hold.kind].label
		text = `{label}…`
		progress = math.clamp((os.clock() - hold.startedAt) / math.max(hold.seconds, 0.01), 0, 1)
	elseif target and ACTIONS[target.kind] then
		local action = ACTIONS[target.kind]
		local cost = Config.Interface[target.kind].Cost
		text = string.format("%s  %s · %s  (%d)", if action.hold then "Hold E" else "E", action.label, targetName(target.kind, target.id), cost)
		if value < cost then
			color = Hud.WARN
		end
	end
	if text then
		local anchor = promptAnchor()
		prompt.Position = UDim2.fromOffset(anchor.X, anchor.Y)
		prompt.Visible = true
		ui.promptLabel.Text = text
		ui.promptLabel.TextColor3 = color
		ui.promptBar.Visible = progress ~= nil
		ui.setPrompt(progress or 0)
	else
		prompt.Visible = false
	end
end

-- Doors stand open, slid into the wall, so the doorway itself is what the Chimera aims at to lock one.
-- These invisible client-only parts fill each doorway; the server never sees them.
local function buildDoorTargets(clientFolder: Folder): Folder
	local targets = Instance.new("Folder")
	targets.Name = "DoorTargets"
	for id, door in FacilityMap.doors() do
		local p = Instance.new("Part")
		p.Name = id
		p.Size = Vector3.new(door.panel.Size.X, door.panel.Size.Y, 2.2)
		p.CFrame = door.closed
		p.Color = Hud.CYAN
		p.Material = Enum.Material.ForceField
		p.Transparency = 1
		p.Anchored = true
		p.CanCollide = false
		p.CanTouch = false
		p.CastShadow = false
		p:SetAttribute("TargetKind", "LockDoor")
		p:SetAttribute("TargetId", id)
		p.Parent = targets
	end
	targets.Parent = clientFolder
	return targets
end

function ChimeraClient.init(clientFolder: Folder)
	actionRemote = Net.get("ChimeraAction")
	Net.get("ChimeraState").OnClientEvent:Connect(onState)
	local doorTargets = buildDoorTargets(clientFolder)
	FacilityView.init(clientFolder, doorTargets, requestHop)
	ShellControl.init(clientFolder, doorTargets)

	for id, room in FacilityMap.rooms() do
		names.Blackout[id] = room.displayName
	end
	for id, terminal in FacilityMap.terminals() do
		names.CorruptTerminal[id] = terminal.displayName
	end
	for id, dock in FacilityMap.docks() do
		names.TakeShell[id] = dock.displayName
	end
	for id, door in FacilityMap.doors() do
		names.LockDoor[id] = door.model:GetAttribute("DisplayName") or "door"
	end
end

function ChimeraClient.start()
	if running then
		return
	end
	running = true
	mode = "facility"
	hold = nil
	local gui = Hud.gui()
	local energyBar, setEnergy = Hud.bar(gui, {
		Name = "Energy",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -66),
		Size = UDim2.fromOffset(320, 10),
	}, Hud.CYAN)
	ui.energyBar = energyBar
	ui.setEnergy = setEnergy
	ui.energyLabel = Hud.text(energyBar, {
		Position = UDim2.fromOffset(0, -22),
		Size = UDim2.new(0.5, 0, 0, 20),
		TextSize = 16,
	})
	ui.rateLabel = Hud.text(energyBar, {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, 0, 0, -22),
		Size = UDim2.new(0.6, 0, 0, 20),
		TextSize = 14,
		TextColor3 = Hud.DIM,
		TextXAlignment = Enum.TextXAlignment.Right,
	})
	local prompt = Hud.frame(gui, {
		Name = "Prompt",
		Size = UDim2.fromOffset(330, 30),
		Visible = false,
		ZIndex = 30,
	})
	ui.prompt = prompt
	ui.promptLabel = Hud.text(prompt, {
		Position = UDim2.fromOffset(8, 0),
		Size = UDim2.new(1, -16, 1, -4),
		TextSize = 15,
		ZIndex = 31,
	})
	local promptBar, setPrompt = Hud.bar(prompt, {
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.fromScale(0, 1),
		Size = UDim2.new(1, 0, 0, 4),
		ZIndex = 31,
	}, Hud.CYAN)
	ui.promptBar = promptBar
	ui.setPrompt = setPrompt

	table.insert(connections, UserInputService.InputBegan:Connect(onInputBegan))
	table.insert(connections, UserInputService.InputEnded:Connect(onInputEnded))
	table.insert(connections, RunService.RenderStepped:Connect(render))
	-- Ask for a fresh snapshot in case the first one arrived before this client was ready.
	actionRemote:FireServer("sync")
end

function ChimeraClient.stop()
	if not running then
		return
	end
	running = false
	hold = nil
	for _, connection in connections do
		connection:Disconnect()
	end
	table.clear(connections)
	FacilityView.stop()
	ShellControl.stop()
	for _, key in { "energyBar", "prompt" } do
		if ui[key] then
			ui[key]:Destroy()
		end
	end
	table.clear(ui)
	workspace.CurrentCamera.CameraType = Enum.CameraType.Custom
end

-- For Studio tests: press or release E/Q through the same code path as the keyboard, or ask to hop.
function ChimeraClient.testKey(keyName: string, down: boolean)
	local fake = { KeyCode = (Enum.KeyCode :: any)[keyName] } :: any
	if down then
		onInputBegan(fake, false)
	else
		onInputEnded(fake)
	end
end

function ChimeraClient.testHop(id: string)
	requestHop(id)
end

function ChimeraClient.describe(): { [string]: any }
	return {
		running = running,
		mode = mode,
		cameraId = cameraId,
		energy = math.floor(energyNow() * 10) / 10,
		hold = hold and { kind = hold.kind, id = hold.id },
		facility = FacilityView.describe(),
		shell = ShellControl.describe(),
		prompt = if ui.prompt and ui.prompt.Visible then ui.promptLabel.Text else nil,
	}
end

return ChimeraClient
