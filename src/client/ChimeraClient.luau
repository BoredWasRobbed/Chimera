-- The Chimera player's client: follows the server's ChimeraState, switches between FacilityView and
-- ShellControl, and owns the shared parts of the HUD: energy, shell HP and visibility, module
-- cooldowns, the Interface prompt and hold progress.
--   E: the one contextual Interface button (hold on a dock to take a shell; in a shell, hold on a
--      downed merc to Assimilate). F: Static Decoy where you aim. In a shell: LMB Energy Claws,
--      R System Leap, hold Q to leave.
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
	Overload = { label = "Overload", hold = false },
}

local LEFT_REASONS = {
	energy = "Out of energy: back to the cameras",
	fell = "Shell lost: back to the cameras",
	destroyed = "Shell destroyed: back to the cameras",
}

type LocalHold = { kind: string, id: string?, startedAt: number, seconds: number }

local running = false
local mode = "facility"
local cameraId: string? = nil
local energy, rate, energyAt = Config.Chimera.EnergyStart, 0, os.clock()
local hold: LocalHold? = nil
local status: { [string]: any } = { hp = 0, maxHp = 1, visibility = "Cloaked", staggered = false, speedScale = 1, attackReadyAt = 0, leapReadyAt = 0 }
local modules: { [string]: any } = { decoyReadyAt = 0, trapsArmed = 0, trapsMax = 2, takeBlockedUntil = 0 }
local channel: { label: string, endsAt: number, seconds: number }? = nil
local clawHitUntil = 0
local actionRemote: RemoteEvent
local names: { [string]: { [string]: string } } = { Blackout = {}, LockDoor = {}, CorruptTerminal = {}, TakeShell = {}, Overload = {} }
local connections: { RBXScriptConnection } = {}
local ui: { [string]: any } = {}

local function serverNow(): number
	return workspace:GetServerTimeNow()
end

local function energyNow(): number
	return math.clamp(energy + rate * (os.clock() - energyAt), 0, Config.Chimera.EnergyMax)
end

local function costOf(kind: string): number
	local settings = Config.Interface[kind]
	return if settings and settings.Cost then settings.Cost else 0
end

local function holdSecondsOf(kind: string): number
	local settings = Config.Interface[kind]
	return if settings and settings.HoldSeconds then settings.HoldSeconds else 0
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
	channel = nil
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
	elseif kind == "shellStatus" then
		status = message
	elseif kind == "modules" then
		modules = message
	elseif kind == "clawHit" then
		clawHitUntil = os.clock() + 0.2
		if message.result == "downed" then
			Hud.toast("Merc down", Hud.CYAN)
		end
	elseif kind == "assimilate" then
		if message.state == "started" then
			local seconds = Config.Health.AssimilateSeconds
			channel = { label = `Assimilating {message.name or ""}`, endsAt = message.endsAt, seconds = seconds }
			ShellControl.playAction("assimilate", seconds)
		else
			channel = nil
			ShellControl.stopAction()
			if message.state == "done" then
				Hud.toast(`{message.name or "Merc"} assimilated`, Hud.CYAN)
			elseif message.reason and message.reason ~= "released" then
				Hud.toast(`Assimilate broken: {message.reason}`)
			end
		end
	elseif kind == "leap" then
		if message.state == "started" then
			local seconds = Config.Modules.SystemLeap.Channel
			channel = { label = `Leaping to {message.target}`, endsAt = message.endsAt, seconds = seconds }
			ShellControl.playAction("leap", seconds)
		else
			channel = nil
			ShellControl.stopAction()
			if message.state == "cancelled" then
				Hud.toast(`Leap broken: {message.reason}`)
			end
		end
	elseif kind == "alert" then
		Hud.toast(message.text, Color3.fromRGB(255, 220, 120))
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
	if mode == "shell" and input.UserInputType == Enum.UserInputType.MouseButton1 then
		if serverNow() >= (status.attackReadyAt or 0) then
			ShellControl.playAction("attack", 0.35)
		end
		actionRemote:FireServer("attack")
		return
	end
	if input.KeyCode == Enum.KeyCode.E then
		if mode == "shell" and ShellControl.assimilateCandidate() then
			hold = { kind = "Assimilate", id = nil, startedAt = os.clock(), seconds = Config.Health.AssimilateSeconds }
			actionRemote:FireServer("assimilateBegin")
			return
		end
		local target = currentTarget()
		local action = target and ACTIONS[target.kind]
		if not target or not action then
			return
		end
		if action.hold then
			hold = { kind = target.kind, id = target.id, startedAt = os.clock(), seconds = holdSecondsOf(target.kind) }
			actionRemote:FireServer("holdBegin", { kind = target.kind, id = target.id })
		else
			actionRemote:FireServer("interface", { kind = target.kind, id = target.id })
		end
	elseif input.KeyCode == Enum.KeyCode.Q and mode == "shell" then
		hold = { kind = "Leave", id = nil, startedAt = os.clock(), seconds = Config.Shell.LeaveHoldSeconds }
		actionRemote:FireServer("leaveBegin")
	elseif input.KeyCode == Enum.KeyCode.R and mode == "shell" then
		local node = ShellControl.leapCandidate()
		local cooldown = (status.leapReadyAt or 0) - serverNow()
		if cooldown > 0 then
			Hud.toast(string.format("System Leap ready in %d s", math.ceil(cooldown)))
		elseif node then
			actionRemote:FireServer("leap", node.id)
		else
			Hud.toast("Aim at a camera or terminal within 80 studs")
		end
	elseif input.KeyCode == Enum.KeyCode.F then
		local point = if mode == "shell" then ShellControl.aimPoint() else FacilityView.aimPoint()
		if point then
			actionRemote:FireServer("decoy", point)
		else
			Hud.toast("Aim at the floor")
		end
	end
end

local function onInputEnded(input: InputObject)
	if not running then
		return
	end
	if input.KeyCode == Enum.KeyCode.E and hold and hold.kind == "Assimilate" then
		hold = nil
		actionRemote:FireServer("assimilateCancel")
	elseif input.KeyCode == Enum.KeyCode.E and hold and hold.kind ~= "Leave" then
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

local function seconds(at: number): number
	return math.max(0, math.ceil(at - serverNow()))
end

local function render()
	local value = energyNow()
	ui.setEnergy(value / Config.Chimera.EnergyMax)
	ui.energyLabel.Text = string.format("ENERGY %d", math.floor(value + 0.5))
	local inShell = mode == "shell"
	if inShell then
		local drain = -rate
		ui.rateLabel.Text = if drain > 0 then string.format("-%g/s  ·  %ds left", drain, math.floor(value / drain)) else "no drain"
	else
		ui.rateLabel.Text = if rate > 0 then string.format("+%g/s", rate) else "full"
	end

	-- Shell HP and state.
	ui.hpBar.Visible = inShell
	if inShell then
		ui.setHp(status.hp / math.max(status.maxHp, 1))
		local flags = { string.upper(status.visibility or "Cloaked") }
		if status.staggered then
			table.insert(flags, "STAGGERED")
		elseif (status.speedScale or 1) <= 0 then
			table.insert(flags, "ROOTED")
		elseif (status.speedScale or 1) < 1 then
			table.insert(flags, "SLOWED")
		end
		ui.hpLabel.Text = `HP {status.hp} / {status.maxHp}   {table.concat(flags, " · ")}`
	end

	-- Modules.
	local decoyIn = seconds(modules.decoyReadyAt or 0)
	local parts = {}
	if inShell then
		local leapIn = seconds(status.leapReadyAt or 0)
		local node = ShellControl.leapCandidate()
		table.insert(parts, "[LMB] Claws")
		table.insert(parts, if leapIn > 0 then `[R] Leap {leapIn}s` elseif node then `[R] Leap → {node.name}` else "[R] Leap (aim at a camera)")
	end
	table.insert(parts, if decoyIn > 0 then `[F] Decoy {decoyIn}s` else "[F] Decoy ready")
	table.insert(parts, `Traps {modules.trapsArmed or 0}/{modules.trapsMax or 2}`)
	local blocked = seconds(modules.takeBlockedUntil or 0)
	if not inShell and blocked > 0 then
		table.insert(parts, `Shell printing locked {blocked}s`)
	end
	ui.modulesLabel.Text = table.concat(parts, "   ")

	local prompt = ui.prompt
	local target = currentTarget()
	local text, color, progress = nil, Hud.CYAN, nil
	if channel then
		text = `{channel.label}…`
		progress = 1 - math.clamp((channel.endsAt - serverNow()) / channel.seconds, 0, 1)
	elseif hold then
		local label = if hold.kind == "Leave" then "Leaving shell" elseif hold.kind == "Assimilate" then "Assimilating" else ACTIONS[hold.kind].label
		text = `{label}…`
		progress = math.clamp((os.clock() - hold.startedAt) / math.max(hold.seconds, 0.01), 0, 1)
	elseif inShell and ShellControl.assimilateCandidate() then
		text = `Hold E  Assimilate · {ShellControl.assimilateCandidate():GetAttribute("MercTag") or "merc"}`
	elseif target and ACTIONS[target.kind] then
		local action = ACTIONS[target.kind]
		local cost = costOf(target.kind)
		local costText = if cost > 0 then `  ({cost})` else ""
		text = string.format("%s  %s · %s%s", if action.hold then "Hold E" else "E", action.label, targetName(target.kind, target.id), costText)
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
	ui.clawHit.Visible = inShell and os.clock() < clawHitUntil
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
	local rooms = FacilityMap.rooms()
	for id, trap in FacilityMap.traps() do
		local room = rooms[trap.room]
		names.Overload[id] = `{if trap.kind == "Conduit" then "power conduit" else "steam pipe"}{if room then ", " .. room.displayName else ""}`
	end
end

function ChimeraClient.start()
	if running then
		return
	end
	running = true
	mode = "facility"
	hold = nil
	channel = nil
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
	ui.modulesLabel = Hud.text(energyBar, {
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 0, -24),
		Size = UDim2.fromOffset(760, 18),
		TextSize = 14,
		TextColor3 = Hud.CYAN,
		TextXAlignment = Enum.TextXAlignment.Center,
	})
	local hpBar, setHp = Hud.bar(gui, {
		Name = "ShellHP",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -136),
		Size = UDim2.fromOffset(320, 8),
		Visible = false,
	}, Color3.fromRGB(235, 240, 245))
	ui.hpBar, ui.setHp = hpBar, setHp
	ui.hpLabel = Hud.text(hpBar, {
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 0, -2),
		Size = UDim2.fromOffset(520, 18),
		TextSize = 14,
		TextXAlignment = Enum.TextXAlignment.Center,
	})
	ui.clawHit = Hud.text(gui, { Name = "ClawHit", Text = "✕", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(30, 30), TextSize = 24, TextXAlignment = Enum.TextXAlignment.Center, Visible = false })
	local prompt = Hud.frame(gui, {
		Name = "Prompt",
		Size = UDim2.fromOffset(360, 30),
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
	channel = nil
	for _, connection in connections do
		connection:Disconnect()
	end
	table.clear(connections)
	FacilityView.stop()
	ShellControl.stop()
	for _, key in { "energyBar", "hpBar", "clawHit", "prompt" } do
		if ui[key] then
			ui[key]:Destroy()
		end
	end
	table.clear(ui)
	workspace.CurrentCamera.CameraType = Enum.CameraType.Custom
end

-- For Studio tests: press or release E/Q/R/F or the mouse through the same code path as the keyboard.
function ChimeraClient.testKey(keyName: string, down: boolean)
	local fake: any
	if keyName == "MouseButton1" then
		fake = { KeyCode = Enum.KeyCode.Unknown, UserInputType = Enum.UserInputType.MouseButton1 }
	else
		fake = { KeyCode = (Enum.KeyCode :: any)[keyName], UserInputType = Enum.UserInputType.Keyboard }
	end
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
		status = status,
		modules = modules,
		channel = channel and channel.label,
		facility = FacilityView.describe(),
		shell = ShellControl.describe(),
		prompt = if ui.prompt and ui.prompt.Visible then ui.promptLabel.Text else nil,
	}
end

return ChimeraClient
