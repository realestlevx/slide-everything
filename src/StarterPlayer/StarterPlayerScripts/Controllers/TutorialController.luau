local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Places = require(ReplicatedStorage.Shared.Places)
local Tutorial = require(ReplicatedStorage.Shared.Tutorial)

local ButtonController = require(script.Parent.ButtonController)
local HudController = require(script.Parent.HudController)
local InventoryController = require(script.Parent.InventoryController)
local RollController = require(script.Parent.RollController)
local SignController = require(script.Parent.SignController)
local SlotController = require(script.Parent.SlotController)
local TopTextController = require(script.Parent.TopTextController)

local LocalPlayer = Players.LocalPlayer

-- Shows the player what their tutorial step wants: it's said across the top of the screen, a beam runs
-- from them to it, it glows, and any button they need to press pulses. All on this client. What's
-- locked and what moves them on to the next step is up to the rest of the game (see Tutorial)
local CHECK_INTERVAL = 0.2 -- Seconds between looks at where things are, as they stream in and out
local PULSE_INTERVAL = 1.2 -- Seconds between a button's pulses
local DONE_TEXT_TIME = 5 -- Seconds the message for finishing lasts, counting its fades

local COLOR = Tutorial.COLOR

local GLOW_NAME = "TutorialGlow"
-- Just an outline, fading back and forth for as long as it's on. A fill would wash out the text on a sign
local GLOW_INFO = TweenInfo.new(0.7, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true)
local GLOW_OUTLINE_GOAL = 0.6 -- How see-through it fades to

local BEAM_NAME = "TutorialBeam"
local BEAM_TEXTURE = "rbxassetid://15000587389"
local BEAM_TEXTURE_LENGTH = 4 -- Studs one copy of the texture takes up
local BEAM_TEXTURE_SPEED = -1.5 -- Copies of the texture a second it scrolls, the way its arrows point
local BEAM_WIDTH = 2.5 -- Studs
local BEAM_FEET = CFrame.new(0, -2.5, 0) -- From the character's root part, so it starts at their feet

type Target = {
	Glow: Instance?, -- What lights up
	Point: BasePart?, -- Where the beam goes
	Button: GuiButton?, -- What pulses
	PulseInside: boolean?, -- It pulses from itself instead of a holder (see ButtonController.Pulse)
}

local dropView = false
local glow: Highlight? = nil
local glowTween: Tween? = nil
local beam: Beam? = nil
local lastPulseAt = -math.huge

local TutorialController = {}

local function getOwnPlace(): Folder?
	for _, place in Places.GetAll() do
		if place:GetAttribute("OwnerUserId") == LocalPlayer.UserId then
			return place
		end
	end
	return nil
end

local function findPart(parent: Instance?, name: string): BasePart?
	local part = parent and parent:FindFirstChild(name)
	return if part and part:IsA("BasePart") then part else nil
end

-- A model in the place, and the part in it the beam goes to. Either may not have streamed in yet
local function getModelTarget(place: Folder, modelName: string, partName: string): Target
	local model = place:FindFirstChild(modelName)
	return { Glow = model, Point = findPart(model, partName) }
end

local function getSignTarget(name: string): (place: Folder) -> Target
	return function()
		local button, board, part = SignController.FindPanel(name)
		return { Glow = board, Point = part, Button = button }
	end
end

-- The last of the slots the player can use that's filled or not. Slots are in the order they're
-- bought, so with one left empty that's the one they just bought
local function findSlot(place: Folder, filled: boolean): Model?
	local found = nil
	for _, slot in Places.GetSlots(place) do
		local usable = slot:GetAttribute("Unlocked") == true and slot:GetAttribute("GamePass") ~= true
		if usable and (slot:GetAttribute("ItemId") ~= nil) == filled then
			found = slot
		end
	end
	return found
end

-- What each step's action points the player at
local targets: { [string]: (place: Folder) -> Target } = {
	Roll = function(place)
		return getModelTarget(place, "RollTools_Model", "Proximity_Holder")
	end,
	BuyItem = function(place)
		return getModelTarget(place, Places.GetStandName(1), "Roll_Place")
	end,
	Slots = getSignTarget("Slots"),
	Equip = function()
		return { Button = InventoryController.GetHotbarButton(1), PulseInside = true }
	end,
	Place = function(place)
		local slot = findSlot(place, false)
		return { Glow = slot, Point = findPart(slot, Places.SLOT_PART) }
	end,
	UpgradeItem = function(place)
		local slot = findSlot(place, true)
		return {
			Glow = slot,
			Point = findPart(slot, Places.SLOT_PART),
			Button = if slot then SlotController.GetUpgradeButton(slot) else nil,
		}
	end,
	Drop = function(place)
		return getModelTarget(place, "Drop_Button", "Proximity_Holder")
	end,
	Collect = function(place)
		return getModelTarget(place, "Collect", "Proximity_Holder")
	end,
	Luck = getSignTarget("Luck"),
	SlideSpeed = getSignTarget("SlideSpeed"),
}

-- How far along they are, like "3/10", in the beam's color, then what to do
local function getMessage(step: Tutorial.Step, number: number): string
	return `<font color="#{COLOR:ToHex()}">{number}/{#Tutorial.Steps}</font>  {step.Text}`
end

local function setGlow(instance: Instance?)
	local current = glow
	if current and current.Parent == instance then
		return
	end
	if current then
		current:Destroy()
		glow = nil
	end
	if glowTween then
		glowTween:Cancel()
		glowTween = nil
	end
	if not instance then
		return
	end

	-- Occluded like the signs' own highlights, so it doesn't show through walls. The beam gets the
	-- player to where they can see it
	local highlight = Instance.new("Highlight")
	highlight.Name = GLOW_NAME
	highlight.DepthMode = Enum.HighlightDepthMode.Occluded
	highlight.FillTransparency = 1
	highlight.OutlineColor = COLOR
	highlight.OutlineTransparency = 0
	highlight.Parent = instance
	glow = highlight
	glowTween = TweenService:Create(highlight, GLOW_INFO, { OutlineTransparency = GLOW_OUTLINE_GOAL })
	glowTween:Play()
end

local function clearBeam()
	local current = beam
	if not current then
		return
	end
	beam = nil
	if current.Attachment0 then
		current.Attachment0:Destroy()
	end
	if current.Attachment1 then
		current.Attachment1:Destroy()
	end
	current:Destroy()
end

-- Between the player's character and the part. Made again if either changes: a new character after a
-- respawn, or a part that streamed back in. The texture's arrows point toward the beam's start, so
-- it starts at the part
local function setBeam(point: BasePart?)
	local character = LocalPlayer.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local current = beam
	if
		current
		and current.Attachment0
		and current.Attachment1
		and current.Attachment0.Parent == point
		and current.Attachment1.Parent == root
	then
		return
	end
	clearBeam()
	if not (point and root and root:IsA("BasePart")) then
		return
	end

	local from = Instance.new("Attachment")
	from.CFrame = BEAM_FEET
	from.Parent = root
	local to = Instance.new("Attachment")
	to.Parent = point

	local made = Instance.new("Beam")
	made.Name = BEAM_NAME
	made.Attachment0 = to
	made.Attachment1 = from
	made.Color = ColorSequence.new(COLOR)
	made.LightEmission = 0
	made.LightInfluence = 0
	made.FaceCamera = true
	made.Segments = 1
	made.Width0 = BEAM_WIDTH
	made.Width1 = BEAM_WIDTH
	made.Texture = BEAM_TEXTURE
	made.TextureMode = Enum.TextureMode.Static
	made.TextureLength = BEAM_TEXTURE_LENGTH
	made.TextureSpeed = BEAM_TEXTURE_SPEED
	made.Parent = root
	beam = made
end

local function pulse(target: Target)
	local button = target.Button
	local now = os.clock()
	if button and now - lastPulseAt >= PULSE_INTERVAL then
		lastPulseAt = now
		ButtonController.Pulse(button, target.PulseInside)
	end
end

-- Nothing shows through a drop or a roll's spin, which have the player's whole screen and camera, or
-- while the settings menu is open, whose header it would sit on
local function update()
	local step, number = Tutorial.GetStep(LocalPlayer)
	local shown = step ~= nil and not dropView and not RollController.IsSpinning() and not HudController.IsMenuOpen()
	TopTextController.Show(if shown and step and number then getMessage(step, number) else nil)

	local place = if shown then getOwnPlace() else nil
	local target: Target = if step and place then targets[step.Action](place) else {}
	setGlow(target.Glow)
	setBeam(target.Point)
	pulse(target)
end

function TutorialController.Start()
	HudController.DropViewChanged:Connect(function(on: boolean)
		dropView = on
	end)

	task.spawn(function()
		-- Someone who finished it on an earlier visit never has a step here, so isn't told again
		local hadStep = false
		while not Tutorial.IsDone(LocalPlayer) do
			hadStep = hadStep or Tutorial.GetStep(LocalPlayer) ~= nil
			update()
			task.wait(CHECK_INTERVAL)
		end
		update() -- With no step left, this clears everything away
		if hadStep then
			TopTextController.Flash(Tutorial.DONE_TEXT, DONE_TEXT_TIME)
		end
	end)
end

return TutorialController
