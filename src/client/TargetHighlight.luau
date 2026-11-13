-- Marks the Interface target under the Chimera's aim. Doorway targets are invisible parts, which a
-- Highlight can't outline, so those light up as a faint sheet instead.
local TargetHighlight = {}

local CYAN = Color3.fromRGB(120, 220, 255)

local highlight: Highlight
local litDoorway: BasePart? = nil

function TargetHighlight.init(parent: Instance)
	highlight = Instance.new("Highlight")
	highlight.Name = "InterfaceTarget"
	highlight.FillColor = CYAN
	highlight.FillTransparency = 0.85
	highlight.OutlineColor = CYAN
	highlight.DepthMode = Enum.HighlightDepthMode.Occluded
	highlight.Enabled = false
	highlight.Parent = parent
end

function TargetHighlight.set(instance: Instance?)
	if litDoorway and litDoorway ~= instance then
		litDoorway.Transparency = 1
		litDoorway = nil
	end
	if instance and instance:IsA("BasePart") and instance.Parent and instance.Parent.Name == "DoorTargets" then
		instance.Transparency = 0.6
		litDoorway = instance
		highlight.Enabled = false
		return
	end
	if instance then
		highlight.Adornee = instance
		highlight.Enabled = true
	else
		highlight.Enabled = false
	end
end

return TargetHighlight
