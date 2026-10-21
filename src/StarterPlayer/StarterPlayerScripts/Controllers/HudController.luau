local ContextActionService = game:GetService("ContextActionService")
local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
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
-- view; the rest are on screen the rest of the time
local DROP_VIEW_PIECES = { Spectate = true, ControlFrame = true, Left = true, Right = true }
-- The sequences play side by side, each step once the one before has finished: in this order into
-- the drop view, and backwards out of it. A step's pieces move together
local SEQUENCES = {
	{ { "BaseButtons" }, { "Spectate" } },
	{ { "Inventory" }, { "ControlFrame" }, { "Left", "Right" } },
	{ { "Cash", "Gem" } },
}

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
local dropView = false
local switches = 0 -- Bumped on every switch, so steps left over from the one before stop

local keysHeld: { [Enum.KeyCode]: boolean } = {}
local stickX = 0
local pointers: { [InputObject]: number } = {} -- Touches and clicks holding a steering button -> its side
local pressButton: { [number]: (held: boolean) -> () } = {} -- Side -> holds its button down or lets go

local exitRequested = Instance.new("BindableEvent")

local HudController = {
	-- Fires when the player asks to leave the drop view with its Exit button
	ExitRequested = exitRequested.Event,
}

local function isShown(name: string): boolean
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
	setSteering(on)
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
	local spectate = main:WaitForChild("Spectate") :: GuiObject
	local exitButton = spectate:WaitForChild("ExitControlButton") :: GuiButton

	for _, button in baseButtons:GetChildren() do
		if button:IsA("GuiButton") then
			ButtonController.Animate(button)
		end
	end
	ButtonController.Animate(exitButton)
	exitButton.Activated:Connect(function()
		exitRequested:Fire()
	end)

	addPiece("BaseButtons", baseButtons, "Top")
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
end

local function bindInventory(gui: Instance)
	addPiece("Inventory", gui:WaitForChild("Main") :: GuiObject, "Bottom")
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
end

return HudController
