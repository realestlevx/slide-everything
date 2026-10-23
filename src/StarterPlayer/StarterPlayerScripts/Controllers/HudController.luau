local ContextActionService = game:GetService("ContextActionService")
local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local FormatMoney = require(ReplicatedStorage.Shared.FormatMoney)

local ButtonController = require(script.Parent.ButtonController)

local LocalPlayer = Players.LocalPlayer
local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")

local SLIDE_OUT_INFO = TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
local SLIDE_IN_INFO = TweenInfo.new(0.4, Enum.EasingStyle.Back, Enum.EasingDirection.Out) -- Overshoots a little before it settles
local FADE_INFO = TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local EDGE_MARGIN = 0.1 -- Pieces slide this share of their own size past the edge, so their strokes go too

-- The pieces of the screen that swap while the player's items drop. These are on screen in the drop
-- view, the multiplier only once it's past 1x; the rest are on screen the rest of the time
local DROP_VIEW_PIECES =
	{ Spectate = true, ControlFrame = true, Left = true, Right = true, Time = true, Multiplier = true }
-- The sequences play side by side, each step once the one before has finished: in this order into
-- the drop view, and backwards out of it. A step's pieces move together
local SEQUENCES = {
	{ { "Inventory" }, { "ControlFrame" }, { "Left", "Right", "Time", "Multiplier" } },
	{ { "Cash", "Gem" } },
}
-- The top bar holds one of these at a time: the base buttons, the button back to the base once the
-- player's left it, or the drop view's Spectate. Whichever is leaving slides out before the next comes in
local TOP_PIECES = { "BaseButtons", "OutsideBaseButtons", "Spectate" }

-- The clock on the timer rocks from side to side
local ICON_TILT = 5 -- Degrees either way
local ICON_SWING_INFO = TweenInfo.new(0.5, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true) -- Each way
-- Every time the timer ticks down, a "-1" pops out of it and floats up as it fades
local TICK_POP_TEXT = "-1"
local TICK_POP_COLOR = Color3.fromRGB(255, 85, 85)
local TICK_POP_SIZE = 0.6 -- Times the timer's size
local TICK_POP_RISE = 1 -- Timer heights it floats up
local TICK_POP_DRIFT = 0.25 -- Timer widths it may drift to either side as it goes
local TICK_POP_GROW_INFO = TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local TICK_POP_RISE_INFO = TweenInfo.new(0.8, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local TICK_POP_FADE_INFO = TweenInfo.new(0.8, Enum.EasingStyle.Quad, Enum.EasingDirection.In) -- Fades mostly at the end

-- The multiplier's colors scroll through the rainbow. The gradient's colors are made again every
-- frame, each a little further round, instead of sliding its Offset, which leaves a flat color
-- where it's slid off the end
local RAINBOW_COLORS = 12 -- Keypoints across it; a ColorSequence takes up to 20
local RAINBOW_PERIOD = 2 -- Seconds for a color to scroll all the way across
-- It shakes harder and grows bigger for every wall the items have passed that multiplies, up to
-- MAX_SHAKE_WALLS of them. The shake starts as a slight tremble at the first wall and builds up
-- faster with each one after: walls ^ SHAKE_BUILD times as hard
local SHAKE_RATE = 20 -- Times a second it jumps to a new spot
local SHAKE_STEP = 0.004 -- Share of its size it jumps about by, at the first wall
local SHAKE_TILT_STEP = 0.4 -- Degrees it tips either way, at the first wall
local SHAKE_BUILD = 1.5
local GROW_STEP = 0.1 -- Share bigger it gets, for each wall
local MAX_SHAKE_WALLS = 6
local GROW_INFO = TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out) -- Pops a little past its new size
-- Every wall that multiplies also sends copies of MultiplierUp's Template up the screen from near the
-- bottom, each a color of the rainbow, turning a little and fading as they rise
local MULTIPLIER_UP_COUNT = 10
local MULTIPLIER_UP_SPREAD = 0.3 -- Seconds they set off across, so they don't all go at once
local MULTIPLIER_UP_MIN_START = 0.75 -- Share of the way down the screen they start, at the highest
local MULTIPLIER_UP_MIN_RISE = 0.3 -- Share of the screen they rise
local MULTIPLIER_UP_MAX_RISE = 0.55
local MULTIPLIER_UP_MIN_TIME = 1 -- Seconds they take
local MULTIPLIER_UP_MAX_TIME = 1.6
local MULTIPLIER_UP_TILT = 20 -- Degrees they may start turned, and turn further, either way
-- It plays SoundService.SFX.MultiplierUp too, a step higher for each wall the drop has passed
local MULTIPLIER_UP_SOUND_NAME = "MultiplierUp"
local MULTIPLIER_UP_MIN_PITCH = 0.8 -- PlaybackSpeed at the first wall
local MULTIPLIER_UP_PITCH_STEP = 0.1
local MULTIPLIER_UP_MAX_PITCH = 1.5
-- And MultiplierUp's Vignette fades in, a random color of the rainbow, and back out
local VIGNETTE_IN_INFO = TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local VIGNETTE_OUT_INFO = TweenInfo.new(0.8, Enum.EasingStyle.Quad, Enum.EasingDirection.In)

local STEER_ACTION = "SteerItems"
local STEER_KEYS: { [Enum.KeyCode]: number } = { -- Key -> the side it steers to, -1 left and 1 right
	[Enum.KeyCode.A] = -1,
	[Enum.KeyCode.Left] = -1,
	[Enum.KeyCode.D] = 1,
	[Enum.KeyCode.Right] = 1,
}
local STICK_DEADZONE = 0.4 -- How far the left stick has to be pushed to one side to steer

type Side = "Top" | "Bottom" | "Left" | "Right"

-- Side -> its button in ControlGui, which slides in from that side
local STEER_BUTTONS: { [number]: Side } = { [-1] = "Left", [1] = "Right" }

type Piece = {
	Gui: GuiObject,
	Side: Side?, -- The edge it slides out past. Without one it fades in and out where it is
	Rest: UDim2, -- Where it sits, as laid out in Studio
	RestTransparency: number,
	Shown: boolean,
	Version: number, -- Bumped on every move, so a slide out only hides it if nothing moved it since
}

local pieces: { [string]: Piece } = {}
-- ControlGui's labels for what the drop has made and how far it's got
local cashLabel: TextLabel? = nil
local distanceLabel: TextLabel? = nil
local timeLabel: TextLabel? = nil
-- The drop's best multiplier so far, and how many walls that multiply it took to get there
local multiplier = 1
local multiplierWalls = 0
local valueLabel: TextLabel? = nil -- Shows the multiplier
local valueRest = UDim2.new() -- Where it sits when it isn't shaking
local valueScale: UIScale? = nil
local valueGradient: UIGradient? = nil
local multiplierUpTemplate: ImageLabel? = nil
local vignette: ImageLabel? = nil
local vignetteTransparency = 0 -- As laid out in Studio, which it fades in to
local nextShakeAt = 0
local random = Random.new()
local dropView = false
local outsideBase = false
local switches = 0 -- Bumped on every switch, so steps left over from the one before stop
local topSwitches = 0 -- The same, for the top bar, which also changes as the player leaves the base

local keysHeld: { [Enum.KeyCode]: boolean } = {}
local stickX = 0
local pointers: { [InputObject]: number } = {} -- Touches and clicks holding a steering button -> its side
local pressButton: { [number]: (held: boolean) -> () } = {} -- Side -> holds its button down or lets go

local exitRequested = Instance.new("BindableEvent")
local homeRequested = Instance.new("BindableEvent")

local HudController = {
	-- Fires when the player asks to leave the drop view with its Exit button
	ExitRequested = exitRequested.Event,
	-- Fires when the player asks to go back to their base with the top bar's Base button
	HomeRequested = homeRequested.Event,
}

local function isShown(name: string): boolean
	if name == "Multiplier" and multiplier <= 1 then
		return false
	end
	if not dropView and (name == "BaseButtons" or name == "OutsideBaseButtons") then
		return outsideBase == (name == "OutsideBaseButtons")
	end
	return (DROP_VIEW_PIECES[name] == true) == dropView
end

-- Where the gui can be seen: inside its nearest ancestor that clips, or else the whole screen.
-- Absolute positions start below the top bar, so the screen starts above 0
local function getViewArea(gui: GuiObject): (Vector2, Vector2)
	local ancestor = gui.Parent
	while ancestor and ancestor:IsA("GuiObject") do
		if (ancestor :: GuiObject).ClipsDescendants then
			local area = ancestor :: GuiObject
			return area.AbsolutePosition, area.AbsolutePosition + area.AbsoluteSize
		end
		ancestor = ancestor.Parent
	end
	local inset = GuiService:GetGuiInset()
	return -inset, workspace.CurrentCamera.ViewportSize - inset
end

-- Just out of sight past the piece's side, measured from where it rests
local function getAwayPosition(piece: Piece): UDim2
	local gui = piece.Gui
	local moved = Vector2.new(gui.Position.X.Offset - piece.Rest.X.Offset, gui.Position.Y.Offset - piece.Rest.Y.Offset)
	local topLeft = gui.AbsolutePosition - moved
	local bottomRight = topLeft + gui.AbsoluteSize
	local areaTopLeft, areaBottomRight = getViewArea(gui)
	local margin = gui.AbsoluteSize * EDGE_MARGIN

	local offset = if piece.Side == "Top"
		then Vector2.new(0, areaTopLeft.Y - bottomRight.Y - margin.Y)
		elseif piece.Side == "Bottom" then Vector2.new(0, areaBottomRight.Y - topLeft.Y + margin.Y)
		elseif piece.Side == "Left" then Vector2.new(areaTopLeft.X - bottomRight.X - margin.X, 0)
		else Vector2.new(areaBottomRight.X - topLeft.X + margin.X, 0)
	return piece.Rest + UDim2.fromOffset(offset.X, offset.Y)
end

-- Slides or fades the piece in or out. Returns how long that takes, 0 if it's already there
local function move(name: string, shown: boolean): number
	local piece = pieces[name]
	if not piece or piece.Shown == shown then
		return 0
	end
	piece.Shown = shown
	piece.Version += 1
	local version = piece.Version
	local gui = piece.Gui

	local info, goal
	if piece.Side then
		-- Comes in from out of sight, or turns back from wherever it got to on its way out
		if not gui.Visible then
			gui.Position = getAwayPosition(piece)
		end
		info = if shown then SLIDE_IN_INFO else SLIDE_OUT_INFO
		goal = { Position = if shown then piece.Rest else getAwayPosition(piece) }
	elseif piece.RestTransparency < 1 then
		if not gui.Visible then
			gui.BackgroundTransparency = 1
		end
		info = FADE_INFO
		goal = { BackgroundTransparency = if shown then piece.RestTransparency else 1 }
	else
		-- No background to fade, so it just shows or hides what's in it
		gui.Visible = shown
		return 0
	end

	gui.Visible = true
	TweenService:Create(gui, info, goal):Play()
	if not shown then
		task.delay(info.Time, function()
			if piece.Version == version then
				gui.Visible = false
			end
		end)
	end
	return info.Time
end

local function playSequence(sequence: { { string } }, switch: number)
	for i = 1, #sequence do
		if switches ~= switch then
			return
		end
		local step = sequence[if dropView then i else #sequence + 1 - i]
		local duration = 0
		for _, name in step do
			duration = math.max(duration, move(name, isShown(name)))
		end
		if duration > 0 then
			task.wait(duration)
		end
	end
end

local function playTop(switch: number)
	local duration = 0
	for _, name in TOP_PIECES do
		if not isShown(name) then
			duration = math.max(duration, move(name, false))
		end
	end
	if duration > 0 then
		task.wait(duration)
	end
	if topSwitches ~= switch then
		return
	end
	for _, name in TOP_PIECES do
		if isShown(name) then
			move(name, true)
		end
	end
end

local function refreshTop()
	topSwitches += 1
	task.spawn(playTop, topSwitches)
end

local function isHeld(side: number): boolean
	if stickX * side > STICK_DEADZONE then
		return true
	end
	for key, keySide in STEER_KEYS do
		if keySide == side and keysHeld[key] then
			return true
		end
	end
	for _, pointerSide in pointers do
		if pointerSide == side then
			return true
		end
	end
	return false
end

-- The steering buttons are already at full size, so they shrink while their side is held, by
-- touch, click, key or stick alike
local function updateButtons()
	for side, press in pressButton do
		press(isHeld(side))
	end
end

local function isPress(input: InputObject): boolean
	return input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch
end

-- Each touch keeps its own InputObject from start to end; a mouse button may not
local function isSameInput(a: InputObject, b: InputObject): boolean
	return a == b or (a.UserInputType == b.UserInputType and a.UserInputType ~= Enum.UserInputType.Touch)
end

local function onSteerInput(_: string, state: Enum.UserInputState, input: InputObject): Enum.ContextActionResult
	local ended = state == Enum.UserInputState.End or state == Enum.UserInputState.Cancel
	if input.KeyCode == Enum.KeyCode.Thumbstick1 then
		stickX = if ended then 0 else input.Position.X
	else
		keysHeld[input.KeyCode] = not ended
	end
	updateButtons()
	-- Sunk, so they don't walk the character or turn the camera as well
	return Enum.ContextActionResult.Sink
end

-- In the drop view the steering inputs steer instead, and the touch thumbstick and jump button go,
-- so the steering buttons have the bottom of touch screens to themselves
local function setSteering(on: boolean)
	table.clear(keysHeld)
	table.clear(pointers)
	stickX = 0
	updateButtons()

	if on then
		local inputs: { Enum.KeyCode } = { Enum.KeyCode.Thumbstick1 }
		for key in STEER_KEYS do
			table.insert(inputs, key)
		end
		ContextActionService:BindActionAtPriority(
			STEER_ACTION,
			onSteerInput,
			false,
			Enum.ContextActionPriority.High.Value,
			table.unpack(inputs)
		)
	else
		ContextActionService:UnbindAction(STEER_ACTION)
	end
	GuiService.TouchControlsEnabled = not on
end

-- Into the view while the player's items drop, or back out of it
function HudController.SetDropView(on: boolean)
	if on == dropView then
		return
	end
	dropView = on
	switches += 1
	for _, sequence in SEQUENCES do
		task.spawn(playSequence, sequence, switches)
	end
	refreshTop()
	setSteering(on)
end

-- Whether the player has left their base, which swaps the top bar's buttons for the one back to it
function HudController.SetOutsideBase(outside: boolean)
	if outside == outsideBase then
		return
	end
	outsideBase = outside
	refreshTop()
end

-- Where the player is steering their dropping items: -1 left, 1 right, 0 straight on
function HudController.GetSteer(): number
	return (if isHeld(1) then 1 else 0) - (if isHeld(-1) then 1 else 0)
end

-- What the drop has made so far, and how many studs down the slide it's got, shown as metres
function HudController.SetDropStats(cash: number, distance: number)
	if cashLabel then
		cashLabel.Text = FormatMoney(cash, 2)
	end
	if distanceLabel then
		distanceLabel.Text = `{math.max(math.floor(distance), 0)}m`
	end
end

-- Anchored at its middle instead, without moving, so it grows and tips about its middle
local function anchorAtMiddle(gui: GuiObject)
	local anchor, size = gui.AnchorPoint, gui.Size
	gui.AnchorPoint = Vector2.new(0.5, 0.5)
	gui.Position += UDim2.fromScale(size.X.Scale * (0.5 - anchor.X), size.Y.Scale * (0.5 - anchor.Y))
end

-- Placed by where the timer's text is on screen, since its aspect ratio keeps it narrower than its frame
local function popTime(label: TextLabel)
	local holder = label.Parent :: GuiObject
	local size = label.AbsoluteSize
	local center = label.AbsolutePosition + size / 2 - holder.AbsolutePosition

	local pop = Instance.new("TextLabel")
	pop.Name = "TimePop"
	pop.BackgroundTransparency = 1
	pop.Text = TICK_POP_TEXT
	pop.FontFace = label.FontFace
	pop.TextScaled = true
	pop.TextColor3 = TICK_POP_COLOR
	pop.ZIndex = label.ZIndex + 1
	pop.AnchorPoint = Vector2.new(0.5, 0.5)
	pop.Size = UDim2.fromOffset(size.X * TICK_POP_SIZE, size.Y * TICK_POP_SIZE)
	pop.Position = UDim2.fromOffset(center.X, center.Y)
	local stroke = label:FindFirstChildOfClass("UIStroke")
	local popStroke = if stroke then stroke:Clone() else nil
	if popStroke then
		popStroke.Parent = pop
	end
	local scale = Instance.new("UIScale")
	scale.Scale = 0
	scale.Parent = pop
	pop.Parent = holder

	local drift = random:NextNumber(-TICK_POP_DRIFT, TICK_POP_DRIFT) * size.X
	TweenService:Create(scale, TICK_POP_GROW_INFO, { Scale = 1 }):Play()
	TweenService:Create(pop, TICK_POP_RISE_INFO, {
		Position = UDim2.fromOffset(center.X + drift, center.Y - size.Y * TICK_POP_RISE),
	}):Play()
	TweenService:Create(pop, TICK_POP_FADE_INFO, { TextTransparency = 1 }):Play()
	if popStroke then
		TweenService:Create(popStroke, TICK_POP_FADE_INFO, { Transparency = 1 }):Play()
	end
	task.delay(TICK_POP_FADE_INFO.Time, pop.Destroy, pop)
end

-- Seconds left in the drop, counting down as m:ss
function HudController.SetDropTime(seconds: number)
	local label = timeLabel
	if not label then
		return
	end
	local whole = math.ceil(seconds)
	local text = string.format("%d:%02d", whole // 60, whole % 60)
	if text ~= label.Text then
		label.Text = text
		if dropView then
			popTime(label)
		end
	end
end

local function getGrowth(walls: number): number
	return 1 + math.min(walls, MAX_SHAKE_WALLS) * GROW_STEP
end

local function emitMultiplierUp()
	local template = multiplierUpTemplate
	if not template then
		return
	end
	local firstHue = random:NextNumber()
	for index = 1, MULTIPLIER_UP_COUNT do
		task.delay(random:NextNumber(0, MULTIPLIER_UP_SPREAD), function()
			-- Gone if the character respawned since, which makes the gui again
			local holder = template.Parent
			if not (holder and template:IsDescendantOf(PlayerGui)) then
				return
			end
			local image = template:Clone()
			local x = random:NextNumber(0.05, 0.95)
			local y = random:NextNumber(MULTIPLIER_UP_MIN_START, 1)
			local tilt = random:NextNumber(-MULTIPLIER_UP_TILT, MULTIPLIER_UP_TILT)
			image.AnchorPoint = Vector2.new(0.5, 0.5)
			image.Position = UDim2.fromScale(x, y)
			image.Rotation = tilt
			-- Spread evenly round the rainbow
			image.ImageColor3 = Color3.fromHSV((firstHue + index / MULTIPLIER_UP_COUNT) % 1, 1, 1)
			image.Visible = true
			image.Parent = holder

			local duration = random:NextNumber(MULTIPLIER_UP_MIN_TIME, MULTIPLIER_UP_MAX_TIME)
			-- Slows as it rises, and fades mostly towards the end
			TweenService:Create(image, TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
				Position = UDim2.fromScale(x, y - random:NextNumber(MULTIPLIER_UP_MIN_RISE, MULTIPLIER_UP_MAX_RISE)),
				Rotation = tilt + random:NextNumber(-MULTIPLIER_UP_TILT, MULTIPLIER_UP_TILT),
			}):Play()
			TweenService:Create(image, TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
				ImageTransparency = 1,
			}):Play()
			task.delay(duration, image.Destroy, image)
		end)
	end
end

-- Its own copy, so one still playing isn't cut off
local function playMultiplierUp(walls: number)
	local sfx = SoundService:FindFirstChild("SFX")
	local sound = sfx and sfx:FindFirstChild(MULTIPLIER_UP_SOUND_NAME)
	if not (sound and sound:IsA("Sound")) then
		return
	end
	local copy = sound:Clone()
	copy.PlaybackSpeed =
		math.min(MULTIPLIER_UP_MIN_PITCH + (walls - 1) * MULTIPLIER_UP_PITCH_STEP, MULTIPLIER_UP_MAX_PITCH)
	copy.Parent = sfx
	copy.Ended:Connect(function()
		copy:Destroy()
	end)
	copy:Play()
end

local function flashVignette()
	local image = vignette
	if not (image and image:IsDescendantOf(PlayerGui)) then
		return
	end
	image.ImageColor3 = Color3.fromHSV(random:NextNumber(), 1, 1)
	local fadeIn = TweenService:Create(image, VIGNETTE_IN_INFO, { ImageTransparency = vignetteTransparency })
	fadeIn.Completed:Connect(function(state: Enum.PlaybackState)
		if state == Enum.PlaybackState.Completed then
			TweenService:Create(image, VIGNETTE_OUT_INFO, { ImageTransparency = 1 }):Play()
		end
	end)
	fadeIn:Play()
end

-- The best multiplier the drop's items have reached, and how many walls that multiply they've
-- passed. It slides in once it's past 1x, and pops bigger with every wall
function HudController.SetDropMultiplier(value: number, walls: number)
	multiplier = value
	if valueLabel then
		valueLabel.Text = `{value}x`
	end
	if walls ~= multiplierWalls then
		if walls > multiplierWalls then
			emitMultiplierUp()
			playMultiplierUp(walls)
			flashVignette()
		end
		multiplierWalls = walls
		if valueScale then
			TweenService:Create(valueScale, GROW_INFO, { Scale = getGrowth(walls) }):Play()
		end
	end
	move("Multiplier", isShown("Multiplier"))
end

local function getRainbow(time: number): ColorSequence
	local keypoints = {}
	for index = 0, RAINBOW_COLORS - 1 do
		local at = index / (RAINBOW_COLORS - 1)
		-- Both ends are the same color, so it scrolls round without a seam
		local hue = (at - time / RAINBOW_PERIOD) % 1
		table.insert(keypoints, ColorSequenceKeypoint.new(at, Color3.fromHSV(hue, 1, 1)))
	end
	return ColorSequence.new(keypoints)
end

-- Every frame the multiplier's on screen: its rainbow scrolls, and it jumps about and tips
local function animateMultiplier()
	local piece = pieces.Multiplier
	local label = valueLabel
	if not (piece and label and piece.Gui.Visible) then
		return
	end
	local now = os.clock()
	if valueGradient then
		valueGradient.Color = getRainbow(now)
	end
	if now >= nextShakeAt then
		nextShakeAt = now + 1 / SHAKE_RATE
		local strength = math.min(multiplierWalls, MAX_SHAKE_WALLS) ^ SHAKE_BUILD
		local jump = strength * SHAKE_STEP
		label.Position = valueRest + UDim2.fromScale(random:NextNumber(-jump, jump), random:NextNumber(-jump, jump))
		label.Rotation = random:NextNumber(-1, 1) * strength * SHAKE_TILT_STEP
	end
end

-- Puts the piece where it belongs in the view the player is in now, without moving it there. Guis
-- are made again on every respawn, so each new copy gets this too
local function addPiece(name: string, gui: GuiObject, side: Side?)
	local shown = isShown(name)
	gui.Visible = shown
	pieces[name] = {
		Gui = gui,
		Side = side,
		Rest = gui.Position,
		RestTransparency = gui.BackgroundTransparency,
		Shown = shown,
		Version = 0,
	}
end

local function bindTop(gui: Instance)
	local main = gui:WaitForChild("Frame"):WaitForChild("Main")
	local baseButtons = main:WaitForChild("BaseButtons") :: GuiObject
	local outsideButtons = main:WaitForChild("OutsideBaseButtons") :: GuiObject
	local homeButton = outsideButtons:WaitForChild("BaseButton") :: GuiButton
	local spectate = main:WaitForChild("Spectate") :: GuiObject
	local exitButton = spectate:WaitForChild("ExitControlButton") :: GuiButton

	for _, holder in { baseButtons, outsideButtons } do
		for _, button in holder:GetChildren() do
			if button:IsA("GuiButton") then
				ButtonController.Animate(button)
			end
		end
	end
	ButtonController.Animate(exitButton)
	exitButton.Activated:Connect(function()
		exitRequested:Fire()
	end)
	homeButton.Activated:Connect(function()
		homeRequested:Fire()
	end)

	addPiece("BaseButtons", baseButtons, "Top")
	addPiece("OutsideBaseButtons", outsideButtons, "Top")
	addPiece("Spectate", spectate, "Top")
end

local function bindControls(gui: Instance)
	local frame = gui:WaitForChild("Main") :: GuiObject
	cashLabel = frame:WaitForChild("Cash") :: TextLabel
	distanceLabel = frame:WaitForChild("Distance") :: TextLabel
	for side, name in STEER_BUTTONS do
		local button = frame:WaitForChild(name) :: GuiButton
		-- Before its piece: this moves the button into a holder in its place, and the button slides
		-- within that
		pressButton[side] = ButtonController.AnimatePress(button)
		button.InputBegan:Connect(function(input)
			if dropView and isPress(input) then
				pointers[input] = side
				updateButtons()
			end
		end)
		addPiece(name, button, name)
	end
	addPiece("ControlFrame", frame, nil)

	local timer = gui:WaitForChild("Time") :: GuiObject
	timeLabel = timer:WaitForChild("Time") :: TextLabel
	local icon = timer:WaitForChild("Icon") :: GuiObject
	icon.Rotation = -ICON_TILT
	TweenService:Create(icon, ICON_SWING_INFO, { Rotation = ICON_TILT }):Play()
	addPiece("Time", timer, "Left")

	local multiplierFrame = gui:WaitForChild("Multiplier") :: GuiObject
	local value = multiplierFrame:WaitForChild("Value") :: TextLabel
	anchorAtMiddle(value)
	valueRest = value.Position
	local scale = Instance.new("UIScale")
	scale.Scale = getGrowth(multiplierWalls)
	scale.Parent = value
	valueLabel = value
	valueScale = scale
	valueGradient = value:FindFirstChildOfClass("UIGradient")
	addPiece("Multiplier", multiplierFrame, "Right")
end

local function bindInventory(gui: Instance)
	addPiece("Inventory", gui:WaitForChild("Main") :: GuiObject, "Bottom")
end

-- The vignette's hidden until a wall flashes it
local function bindMultiplierUp(gui: Instance)
	local main = gui:WaitForChild("Main")
	multiplierUpTemplate = main:WaitForChild("Template") :: ImageLabel
	local image = main:WaitForChild("Vignette") :: ImageLabel
	vignetteTransparency = image.ImageTransparency
	image.ImageTransparency = 1
	vignette = image
end

-- Found wherever they are in the gui, so the frames around them can change
local function bindCurrency(gui: Instance)
	for _, name in { "Cash", "Gem" } do
		local frame = gui:FindFirstChild(name, true)
		if frame and frame:IsA("GuiObject") then
			addPiece(name, frame, "Left")
		end
	end
end

function HudController.Start()
	local binders: { [string]: (Instance) -> () } = {
		TopScreenGui = bindTop,
		ControlGui = bindControls,
		Inventory = bindInventory,
		["Cash/Gem"] = bindCurrency,
		MultiplierUp = bindMultiplierUp,
	}
	PlayerGui.ChildAdded:Connect(function(child)
		local bind = binders[child.Name]
		if bind then
			bind(child)
		end
	end)
	for name, bind in binders do
		local gui = PlayerGui:FindFirstChild(name)
		if gui then
			task.spawn(bind, gui)
		end
	end

	-- Listened for everywhere, since a touch can be let go off its button
	UserInputService.InputEnded:Connect(function(input)
		local released = false
		for pointer in pointers do
			if isSameInput(pointer, input) then
				pointers[pointer] = nil
				released = true
			end
		end
		if released then
			updateButtons()
		end
	end)
	RunService.RenderStepped:Connect(animateMultiplier)
end

return HudController
