local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
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
local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")

-- Shows the player what their tutorial step wants: it's said across the top of the screen, a beam runs
-- from them to it, it glows, and any button they need to press pulses, has an arrow bobbing under it or
-- has the screen darkened around it. All on this client. What's locked and what moves them on to the
-- next step is up to the rest of the game (see Tutorial)
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

local ARROW_NAME = "TutorialArrow"
local ARROW_IMAGE = "rbxassetid://74885007861450" -- Points up. The image of decal 140344844546225
-- As shares of the button's height. A billboard doesn't draw what's fully outside it, and a slot's has
-- hardly any room under its buttons. So the arrow's frame stays where it starts, just inside the billboard,
-- and the arrow's fit into the middle of it: the frame growing taller is what moves the arrow down
local ARROW_SIZE = 1
local ARROW_GAP = 0.05 -- Between the button and the arrow at its highest
local ARROW_BOB = 0.25
local ARROW_BOB_INFO = TweenInfo.new(0.4, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true)

local SPOTLIGHT_NAME = "TutorialSpotlight"
-- Over the game's guis, under the top bar's buttons and the step's message, which stay lit
local SPOTLIGHT_DISPLAY_ORDER = 5
local SPOTLIGHT_TRANSPARENCY = 0.35 -- How see-through the dark is
local SPOTLIGHT_THICKNESS = 10000 -- Pixels, to reach past the far corner of any screen
-- Left lit around the button on each side, as a share of its size. Its outline and the ring take up
-- about 0.13 of that, so what's left is the gap that shows between them
local SPOTLIGHT_GAP = 0.19
local SPOTLIGHT_RING_THICKNESS = 0.07 -- The pulsing ring inside the gap, scaled by the frame's size
local SPOTLIGHT_SHRINK_INFO = TweenInfo.new(1.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local SPOTLIGHT_FADE_INFO = TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

type Target = {
	Glow: Instance?, -- What lights up
	Point: BasePart?, -- Where the beam goes
	Button: GuiButton?, -- What pulses
	PulseInside: boolean?, -- It pulses from itself instead of a holder (see ButtonController.Pulse)
	Arrow: GuiObject?, -- What has an arrow bobbing under it
	Spotlight: GuiObject?, -- What stays lit while the rest of the screen darkens
}

type Spotlight = {
	Gui: ScreenGui,
	Dark: UIStroke,
	Ring: UIStroke,
	Follow: RBXScriptConnection,
	Pulse: Tween?, -- The ring's, once the dark has closed in
}

local dropView = false
local glow: Highlight? = nil
local glowTween: Tween? = nil
local beam: Beam? = nil
local lastPulseAt = -math.huge
local arrow: ImageLabel? = nil
local arrowTween: Tween? = nil
local spotlight: Spotlight? = nil
local spotlightButton: GuiObject? = nil

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
		local button = InventoryController.GetHotbarButton(1)
		return { Button = button, PulseInside = true, Spotlight = button }
	end,
	Place = function(place)
		local slot = findSlot(place, false)
		return { Glow = slot, Point = findPart(slot, Places.SLOT_PART) }
	end,
	UpgradeItem = function(place)
		local slot = findSlot(place, true)
		local button = if slot then SlotController.GetUpgradeButton(slot) else nil
		return {
			Glow = slot,
			Point = findPart(slot, Places.SLOT_PART),
			Button = button,
			Arrow = button,
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

-- How far along they are, like "3/10", then what to do
local function getMessage(step: Tutorial.Step, number: number): string
	return `<font color="#{Tutorial.COUNT_COLOR:ToHex()}">{number}/{#Tutorial.Steps}</font>  {step.Text}`
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

-- Inside the button, so it goes along with it and goes away if it does. It hangs from the button's bottom
-- edge, where it doesn't cover anything else on the billboard. Left its own colors, as a tint would turn
-- its blue side green. Made again if the button's a new one, as a billboard's copy is when its slot
-- streams back in
local function setArrow(button: GuiObject?)
	local current = arrow
	if current and current.Parent == button then
		return
	end
	if current then
		current:Destroy()
		arrow = nil
	end
	if arrowTween then
		arrowTween:Cancel()
		arrowTween = nil
	end
	if not button then
		return
	end

	local made = Instance.new("ImageLabel")
	made.Name = ARROW_NAME
	made.AnchorPoint = Vector2.new(0.5, 0)
	made.Position = UDim2.fromScale(0.5, 1)
	made.Size = UDim2.fromScale(ARROW_SIZE, ARROW_SIZE + ARROW_GAP * 2)
	made.SizeConstraint = Enum.SizeConstraint.RelativeYY
	made.BackgroundTransparency = 1
	made.Image = ARROW_IMAGE
	made.ScaleType = Enum.ScaleType.Fit
	made.ZIndex = button.ZIndex + 1
	made.Parent = button
	arrow = made
	arrowTween = TweenService:Create(made, ARROW_BOB_INFO, {
		Size = UDim2.fromScale(ARROW_SIZE, ARROW_SIZE + (ARROW_GAP + ARROW_BOB) * 2),
	})
	arrowTween:Play()
end

local function clearSpotlight()
	local current = spotlight
	if not current then
		return
	end
	spotlight = nil
	current.Follow:Disconnect()
	if current.Pulse then
		current.Pulse:Cancel()
	end
	TweenService:Create(current.Dark, SPOTLIGHT_FADE_INFO, { Transparency = 1 }):Play()
	TweenService:Create(current.Ring, SPOTLIGHT_FADE_INFO, { Transparency = 1 }):Play()
	task.delay(SPOTLIGHT_FADE_INFO.Time, current.Gui.Destroy, current.Gui)
end

-- Darkens everything but this button, which can still be pressed: a frame over it, with its corners,
-- and a stroke thick enough to fill the rest of the screen. The frame starts out past the screen's
-- edges, so the dark closes in from off screen as it shrinks down to the button, then a ring inside it
-- starts to pulse. It's in a gui of its own to go over the other guis, so it's lined up every frame, as
-- the hotbar's buttons move and get made again. Hands over to a new button without starting again, so
-- that doesn't flicker
local function setSpotlight(button: GuiObject?)
	spotlightButton = button
	if not button then
		clearSpotlight()
		return
	end
	if spotlight then
		return
	end

	local gui = Instance.new("ScreenGui")
	gui.Name = SPOTLIGHT_NAME
	gui.DisplayOrder = SPOTLIGHT_DISPLAY_ORDER
	gui.ResetOnSpawn = false
	gui.ClipToDeviceSafeArea = false
	local source = button:FindFirstAncestorOfClass("ScreenGui")
	if source then
		gui.IgnoreGuiInset = source.IgnoreGuiInset
		gui.ScreenInsets = source.ScreenInsets
	end

	local frame = Instance.new("Frame")
	frame.AnchorPoint = Vector2.new(0.5, 0.5)
	frame.BackgroundTransparency = 1
	frame.BorderSizePixel = 0
	local corner = button:FindFirstChildOfClass("UICorner")
	if corner then
		corner:Clone().Parent = frame
	end
	local dark = Instance.new("UIStroke")
	dark.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	dark.Color = Color3.new()
	dark.Thickness = SPOTLIGHT_THICKNESS
	dark.Transparency = SPOTLIGHT_TRANSPARENCY
	dark.Parent = frame
	-- See-through until the dark has closed in, as scaling with the frame makes it a wide band till then
	local ring = Instance.new("UIStroke")
	ring.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	ring.BorderStrokePosition = Enum.BorderStrokePosition.Inner
	ring.StrokeSizingMode = Enum.StrokeSizingMode.ScaledSize
	ring.Color = COLOR
	ring.Thickness = SPOTLIGHT_RING_THICKNESS
	ring.Transparency = 1
	ring.Parent = frame
	frame.Parent = gui
	gui.Parent = PlayerGui

	-- How much further out the frame's edges are than where they end up. The screen's diagonal puts
	-- them off screen from anywhere on it
	local extra = Instance.new("NumberValue")
	extra.Value = workspace.CurrentCamera.ViewportSize.Magnitude

	local function follow()
		local current = spotlightButton
		if current then
			local center = current.AbsolutePosition + current.AbsoluteSize / 2 - gui.AbsolutePosition
			local size = current.AbsoluteSize * (1 + SPOTLIGHT_GAP * 2) + Vector2.one * extra.Value * 2
			frame.Position = UDim2.fromOffset(center.X, center.Y)
			frame.Size = UDim2.fromOffset(size.X, size.Y)
		end
	end
	follow() -- Now, as it could show before the next frame's step, with the frame not yet in place

	local made: Spotlight = { Gui = gui, Dark = dark, Ring = ring, Follow = RunService.RenderStepped:Connect(follow) }
	spotlight = made
	local shrink = TweenService:Create(extra, SPOTLIGHT_SHRINK_INFO, { Value = 0 })
	shrink.Completed:Once(function()
		if spotlight == made then
			local ringPulse = TweenService:Create(ring, GLOW_INFO, { Transparency = 0 })
			made.Pulse = ringPulse
			ringPulse:Play()
		end
	end)
	shrink:Play()
end

-- Nothing shows through a drop or a roll's spin, which have the player's whole screen and camera, or
-- while the settings menu is open, whose header it would sit on. The backpack stays usable through the
-- tutorial, so it isn't left in the dark
local function update()
	local step, number = Tutorial.GetStep(LocalPlayer)
	local shown = step ~= nil and not dropView and not RollController.IsSpinning() and not HudController.IsMenuOpen()
	TopTextController.Show(if shown and step and number then getMessage(step, number) else nil)

	local place = if shown then getOwnPlace() else nil
	local target: Target = if step and place then targets[step.Action](place) else {}
	setGlow(target.Glow)
	setBeam(target.Point)
	setArrow(target.Arrow)
	setSpotlight(if InventoryController.IsOpen() then nil else target.Spotlight)
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
