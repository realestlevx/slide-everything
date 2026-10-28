local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Icon = require(ReplicatedStorage.Packages.TopbarPlus)
local Volumes = require(ReplicatedStorage.Shared.Volumes)

local ButtonController = require(script.Parent.ButtonController)
local HudController = require(script.Parent.HudController)

local SetFastMode = ReplicatedStorage.Remotes.SetFastMode
local SetLuck = ReplicatedStorage.Remotes.SetLuck
local SetVolume = ReplicatedStorage.Remotes.SetVolume
local LocalPlayer = Players.LocalPlayer
local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")

-- The topbar button opens and closes the Settings gui, and its exit button closes it too. It stays
-- through drops, when the rest of the HUD has moved out
local ICON_IMAGE = "rbxassetid://18801194936"
local ICON_IMAGE_SCALE = 0.75 -- Of the button, up from TopbarPlus's 0.5
local ICON_CAPTION = "Settings"
local ICON_ORDER = 2 -- After the Inventory button, which keeps TopbarPlus's own order of a little over 1
-- The menu grows from this share of its size as it opens, overshooting a little, and shrinks back
-- to it as it closes, the same as the backpack
local OPEN_SCALE = 0.85
local OPEN_INFO = TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local CLOSE_INFO = TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
-- While it's open the world behind it blurs a little and the camera widens its view
local BLUR_SIZE = 12
local FOV_BOOST = 10 -- Degrees added to the camera's FieldOfView
local EFFECTS_IN_INFO = TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local EFFECTS_OUT_INFO = TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local FOV_STEP_NAME = "SettingsFov"

-- Volume name (see Volumes) -> its row in the Settings gui's Holder, which has its slider
local VOLUME_ROWS = {
	Sfx = "Sound",
	Music = "Music",
}
-- The row whose slider sets the luck the player's rolls are at, from 1 up to the most their Luck
-- upgrade gives. The label on its bar shows both, like "30/50 Luck"
local LUCK_ROW = "Luck"
local VALUE_LABEL_NAME = "Value"
-- The row with the Fast Mode switch: a button that's red with "Off" on its Text label while it's
-- off, and green with "On" while it's on. It's saved, and put back as it was when they join
local FAST_MODE_ROW = "FastMode"
local FAST_MODE_BUTTON_NAME = "Off/On"
local FAST_MODE_TEXT_NAME = "Text"
local FAST_MODE_ON_COLOR = Color3.fromRGB(96, 253, 29)
local FAST_MODE_OFF_COLOR = Color3.fromRGB(253, 3, 3)

-- A knob dragged along the bar of one of the gui's rows
type Slider = {
	Row: string, -- Its row in the gui's Holder
	Fraction: number, -- How far along the bar the knob is, 0 to 1
	Text: string?, -- Shown on the bar's Value label. Nil for a row without one
	-- Dragged this far along the bar, which moves the knob there or as near as it goes
	OnSlide: (fraction: number) -> (),
	OnRelease: () -> (), -- Let go, so where it's at can be kept
	-- Parts of its row, found again each time the gui's remade
	Track: GuiObject?, -- The row's Scroller, which the slider runs along
	Fill: GuiObject?,
	Knob: GuiObject?,
	Label: TextLabel?,
}

type Volume = {
	Name: string, -- See Volumes
	Group: SoundGroup?,
	-- The group's Volume as set in Studio. The slider sets it as a share of this, so all the way up
	-- it sounds as it was mixed
	MixedVolume: number,
	-- Set once the player moves it, so their saved volume reaching the client late can't move it back
	Changed: boolean,
	Slider: Slider, -- Its Fraction is the volume
}

local fastModeChanged = Instance.new("BindableEvent")

local SettingsController = {
	-- Fires with true as the player turns Fast Mode on, and false as they turn it off
	FastModeChanged = fastModeChanged.Event,
}

local icon: any = nil
local isOpen = false
local openVersion = 0 -- Counts opens and closes, so a close that's been reopened since doesn't hide it

-- Parts of the Settings gui, which is remade on every respawn, so they're found again each time
local main: GuiObject? = nil
local openScale: UIScale? = nil

local blur: BlurEffect? = nil
local fovBoost = Instance.new("NumberValue") -- How far the view's widened right now, tweened in and out
-- The camera the widening is on until the frame's drawn, and its FieldOfView without and with it
local widenedCamera: Camera? = nil
local unwidenedFov = 0
local widenedFov = 0

local fastMode = false
-- Set once the player clicks it, so their saved choice reaching the client late can't switch it back
local fastModeClicked = false
local fastModeButton: GuiButton? = nil
local fastModeText: TextLabel? = nil

local sliders: { Slider } = {}
local press: InputObject? = nil -- The click or touch dragging a slider
local pressed: Slider? = nil -- The slider it's dragging

local function isPress(input: InputObject): boolean
	return input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch
end

-- A mouse's button is the same from press to let go, while each touch is its own
local function isSameInput(a: InputObject, b: InputObject): boolean
	return a == b or (a.UserInputType == b.UserInputType and a.UserInputType ~= Enum.UserInputType.Touch)
end

local function render(slider: Slider)
	local fill, knob, label = slider.Fill, slider.Knob, slider.Label
	if fill then
		fill.Size = UDim2.new(UDim.new(slider.Fraction, 0), fill.Size.Y)
		-- Its outline would still show as a sliver at nothing
		fill.Visible = slider.Fraction > 0
	end
	if knob then
		knob.Position = UDim2.new(UDim.new(slider.Fraction, 0), knob.Position.Y)
	end
	if label and slider.Text then
		label.Text = slider.Text
	end
end

local function createSlider(
	row: string,
	text: string?,
	onSlide: (fraction: number) -> (),
	onRelease: () -> ()
): Slider
	local slider: Slider = {
		Row = row,
		Fraction = 1,
		Text = text,
		OnSlide = onSlide,
		OnRelease = onRelease,
		Track = nil,
		Fill = nil,
		Knob = nil,
		Label = nil,
	}
	table.insert(sliders, slider)
	return slider
end

local function slideTo(slider: Slider, x: number)
	local track = slider.Track
	if not (track and track.AbsoluteSize.X > 0) then
		return
	end
	slider.OnSlide(math.clamp((x - track.AbsolutePosition.X) / track.AbsoluteSize.X, 0, 1))
end

-- Pressing anywhere on a bar or its knob jumps the slider there and starts dragging it
local function onPressed(slider: Slider, input: InputObject)
	if press or not isPress(input) then
		return
	end
	press = input
	pressed = slider
	slideTo(slider, input.Position.X)
end

local function onPointerMoved(input: InputObject)
	local current, slider = press, pressed
	if not (current and slider) then
		return
	end
	local isMouse = current.UserInputType == Enum.UserInputType.MouseButton1
	if isMouse and input.UserInputType ~= Enum.UserInputType.MouseMovement then
		return
	elseif not isMouse and input ~= current then
		return
	end
	slideTo(slider, input.Position.X)
end

-- Kept once it's let go, rather than on every step of the drag
local function onPointerReleased(input: InputObject)
	local current, slider = press, pressed
	if not (current and slider and isSameInput(current, input)) then
		return
	end
	press = nil
	pressed = nil
	slider.OnRelease()
end

local function setVolume(volume: Volume, value: number)
	volume.Slider.Fraction = value
	if volume.Group then
		volume.Group.Volume = volume.MixedVolume * value
	end
	render(volume.Slider)
end

local function loadSavedVolume(volume: Volume)
	local saved = LocalPlayer:GetAttribute(`{volume.Name}Volume`)
	if typeof(saved) == "number" and not volume.Changed then
		setVolume(volume, saved)
	end
end

-- The widening goes on just before each frame is drawn and comes off again straight after, so
-- everything else that sets the camera's FieldOfView or keeps it to put back, like the drop camera
-- and the roll and floor zooms, only ever sees it without, and can't keep the widening by mistake
local function unwiden()
	local camera = widenedCamera
	if not camera then
		return
	end
	widenedCamera = nil
	-- Left as it is if something else has set it since
	if camera.FieldOfView == widenedFov then
		camera.FieldOfView = unwidenedFov
	end
end

local function widen()
	unwiden()
	local boost = fovBoost.Value
	if boost <= 0 then
		return
	end
	local camera = workspace.CurrentCamera
	unwidenedFov = camera.FieldOfView
	camera.FieldOfView = unwidenedFov + boost
	-- Read back, since it's clamped and stored less precisely than it's set
	widenedFov = camera.FieldOfView
	widenedCamera = camera
end

local function setOpen(open: boolean)
	isOpen = open
	openVersion += 1
	local version = openVersion

	HudController.SetMenuOpen(open)
	local effectsInfo = if open then EFFECTS_IN_INFO else EFFECTS_OUT_INFO
	TweenService:Create(fovBoost, effectsInfo, { Value = if open then FOV_BOOST else 0 }):Play()
	local effect = blur
	if effect then
		effect.Enabled = true
		TweenService:Create(effect, effectsInfo, { Size = if open then BLUR_SIZE else 0 }):Play()
		if not open then
			task.delay(effectsInfo.Time, function()
				if openVersion == version then
					effect.Enabled = false
				end
			end)
		end
	end

	local frame, scale = main, openScale
	if not (frame and scale) then
		return
	end
	if open then
		if not frame.Visible then
			scale.Scale = OPEN_SCALE
		end
		frame.Visible = true
		TweenService:Create(scale, OPEN_INFO, { Scale = 1 }):Play()
	else
		TweenService:Create(scale, CLOSE_INFO, { Scale = OPEN_SCALE }):Play()
		task.delay(CLOSE_INFO.Time, function()
			if openVersion == version then
				frame.Visible = false
			end
		end)
	end
end

local function bindSlider(slider: Slider, row: Instance)
	local track = row:WaitForChild("Scroller") :: GuiObject
	local knob = track:WaitForChild("Slider") :: GuiObject
	slider.Track = track
	slider.Fill = track:WaitForChild("Fill") :: GuiObject
	slider.Knob = knob
	if slider.Text then
		slider.Label = track:WaitForChild(VALUE_LABEL_NAME) :: TextLabel
	end

	-- The knob sits centered on the end of the fill
	knob.AnchorPoint = Vector2.new(0.5, knob.AnchorPoint.Y)
	-- So a touch dragging the slider doesn't turn the camera as well
	track.Active = true
	knob.Active = true
	for _, gui in { track, knob } do
		gui.InputBegan:Connect(function(input)
			onPressed(slider, input)
		end)
	end
	render(slider)
end

local function showFastMode()
	local button, text = fastModeButton, fastModeText
	if button then
		button.BackgroundColor3 = if fastMode then FAST_MODE_ON_COLOR else FAST_MODE_OFF_COLOR
	end
	if text then
		text.Text = if fastMode then "On" else "Off"
	end
end

local function setFastMode(on: boolean)
	if on == fastMode then
		return
	end
	fastMode = on
	showFastMode()
	fastModeChanged:Fire(on)
end

local function loadSavedFastMode()
	local saved = LocalPlayer:GetAttribute("FastMode")
	if typeof(saved) == "boolean" and not fastModeClicked then
		setFastMode(saved)
	end
end

local function bindFastMode(row: Instance)
	local button = row:WaitForChild(FAST_MODE_BUTTON_NAME) :: GuiButton
	fastModeButton = button
	fastModeText = button:WaitForChild(FAST_MODE_TEXT_NAME) :: TextLabel
	showFastMode()
	ButtonController.Animate(button)
	button.Activated:Connect(function()
		fastModeClicked = true
		setFastMode(not fastMode)
		SetFastMode:FireServer(fastMode)
	end)
end

local function bindGui(gui: Instance)
	local frame = gui:WaitForChild("Main") :: GuiObject
	local exitButton = frame:WaitForChild("Header"):WaitForChild("ExitButton") :: GuiButton
	local holder = frame:WaitForChild("Holder")

	main = frame
	local scale = Instance.new("UIScale")
	scale.Name = "OpenScale"
	scale.Scale = if isOpen then 1 else OPEN_SCALE
	scale.Parent = frame
	openScale = scale
	frame.Visible = isOpen

	for _, slider in sliders do
		task.spawn(bindSlider, slider, holder:WaitForChild(slider.Row))
	end
	task.spawn(bindFastMode, holder:WaitForChild(FAST_MODE_ROW))

	ButtonController.Animate(exitButton)
	exitButton.Activated:Connect(function()
		if icon then
			icon:deselect()
		end
	end)
end

-- A sound plays through the group its SoundGroup names rather than the one it's kept in, so every
-- sound in the group, and every copy of one played there, is pointed at it
local function bindGroup(volume: Volume)
	local groupName = Volumes[volume.Name]
	local group = SoundService:FindFirstChild(groupName)
	if not (group and group:IsA("SoundGroup")) then
		warn(`[SettingsController] SoundService.{groupName} should be a SoundGroup`)
		return
	end
	volume.Group = group
	volume.MixedVolume = group.Volume

	local function link(descendant: Instance)
		if descendant:IsA("Sound") then
			descendant.SoundGroup = group
		end
	end
	for _, descendant in group:GetDescendants() do
		link(descendant)
	end
	group.DescendantAdded:Connect(link)
end

local function createVolume(name: string)
	local volume: Volume
	volume = {
		Name = name,
		Group = nil,
		MixedVolume = 1,
		Changed = false,
		Slider = createSlider(VOLUME_ROWS[name], nil, function(fraction)
			volume.Changed = true
			setVolume(volume, fraction)
		end, function()
			SetVolume:FireServer(name, volume.Slider.Fraction)
		end),
	}
	bindGroup(volume)
	LocalPlayer:GetAttributeChangedSignal(`{name}Volume`):Connect(function()
		loadSavedVolume(volume)
	end)
	loadSavedVolume(volume)
end

-- The luck slider runs from 1 at its left end to the most the player's Luck upgrade gives at its
-- right, in whole steps, and the rolls are at wherever it's let go
local function createLuck()
	local luck, maxLuck = 1, 1
	local slider: Slider

	local function show()
		slider.Fraction = if maxLuck > 1 then (luck - 1) / (maxLuck - 1) else 1
		slider.Text = `{luck}/{maxLuck} Luck`
		render(slider)
	end

	-- From the server, which sends back what each let go set it to. Not while it's being dragged,
	-- so the answer to an earlier let go can't pull it back
	local function load()
		local current, most = LocalPlayer:GetAttribute("Luck"), LocalPlayer:GetAttribute("MaxLuck")
		if pressed ~= slider and typeof(current) == "number" and typeof(most) == "number" then
			luck, maxLuck = current, most
			show()
		end
	end

	slider = createSlider(LUCK_ROW, "", function(fraction)
		luck = math.round(1 + fraction * (maxLuck - 1))
		show()
	end, function()
		SetLuck:FireServer(luck)
	end)
	show()
	for _, attribute in { "Luck", "MaxLuck" } do
		LocalPlayer:GetAttributeChangedSignal(attribute):Connect(load)
	end
	load()
end

-- On the camera, so it's only on this player's screen and out of the way of the stage lighting looks
local function createBlur()
	local effect = Instance.new("BlurEffect")
	effect.Name = "SettingsBlur"
	effect.Size = 0
	effect.Enabled = false
	effect.Parent = workspace.CurrentCamera
	blur = effect
	workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
		effect.Parent = workspace.CurrentCamera
	end)
end

local function createIcon()
	icon = Icon.new()
		:setName("Settings")
		:setRight()
		:setImage(ICON_IMAGE)
		:setImageScale(ICON_IMAGE_SCALE)
		:setCaption(ICON_CAPTION)
		:setOrder(ICON_ORDER)
		:bindEvent("toggled", function(_, isSelected: boolean)
			setOpen(isSelected)
		end)
end

-- As the player left it last time, once their saved data's in, and off until then
function SettingsController.IsFastMode(): boolean
	return fastMode
end

function SettingsController.Start()
	for name in Volumes do
		createVolume(name)
	end
	createLuck()
	LocalPlayer:GetAttributeChangedSignal("FastMode"):Connect(loadSavedFastMode)
	loadSavedFastMode()

	createBlur()
	-- After every other camera step, the drop camera's too, and taken off once the frame's drawn
	RunService:BindToRenderStep(FOV_STEP_NAME, Enum.RenderPriority.Last.Value, widen)
	RunService.PreAnimation:Connect(unwiden)

	PlayerGui.ChildAdded:Connect(function(child)
		if child.Name == "Settings" then
			bindGui(child)
		end
	end)
	local gui = PlayerGui:FindFirstChild("Settings")
	if gui then
		task.spawn(bindGui, gui)
	end
	createIcon()

	UserInputService.InputChanged:Connect(onPointerMoved)
	-- Listened for everywhere, since a slider can be let go off its bar
	UserInputService.InputEnded:Connect(onPointerReleased)
end

return SettingsController
