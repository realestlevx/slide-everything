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
local ROWS = {
	Sfx = "Sound",
	Music = "Music",
}

type Slider = {
	Name: string, -- See Volumes
	Group: SoundGroup?,
	-- The group's Volume as set in Studio. The slider sets it as a share of this, so all the way up
	-- it sounds as it was mixed
	MixedVolume: number,
	Volume: number, -- Where the slider is, 0 to 1
	-- Set once the player moves it, so their saved volume reaching the client late can't move it back
	Changed: boolean,
	-- Parts of its row, found again each time the gui's remade
	Track: GuiObject?, -- The row's Scroller, which the slider runs along
	Fill: GuiObject?,
	Knob: GuiObject?,
}

local SettingsController = {}

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

local sliders: { [string]: Slider } = {}
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
	local fill, knob = slider.Fill, slider.Knob
	if fill then
		fill.Size = UDim2.new(UDim.new(slider.Volume, 0), fill.Size.Y)
		-- Its outline would still show as a sliver at nothing
		fill.Visible = slider.Volume > 0
	end
	if knob then
		knob.Position = UDim2.new(UDim.new(slider.Volume, 0), knob.Position.Y)
	end
end

local function setVolume(slider: Slider, volume: number)
	slider.Volume = volume
	if slider.Group then
		slider.Group.Volume = slider.MixedVolume * volume
	end
	render(slider)
end

local function slideTo(slider: Slider, x: number)
	local track = slider.Track
	if not (track and track.AbsoluteSize.X > 0) then
		return
	end
	slider.Changed = true
	setVolume(slider, math.clamp((x - track.AbsolutePosition.X) / track.AbsoluteSize.X, 0, 1))
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
	SetVolume:FireServer(slider.Name, slider.Volume)
end

local function loadSavedVolume(slider: Slider)
	local saved = LocalPlayer:GetAttribute(`{slider.Name}Volume`)
	if typeof(saved) == "number" and not slider.Changed then
		setVolume(slider, saved)
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

	for name, slider in sliders do
		task.spawn(bindSlider, slider, holder:WaitForChild(ROWS[name]))
	end

	ButtonController.Animate(exitButton)
	exitButton.Activated:Connect(function()
		if icon then
			icon:deselect()
		end
	end)
end

-- A sound plays through the group its SoundGroup names rather than the one it's kept in, so every
-- sound in the group, and every copy of one played there, is pointed at it
local function bindGroup(slider: Slider)
	local groupName = Volumes[slider.Name]
	local group = SoundService:FindFirstChild(groupName)
	if not (group and group:IsA("SoundGroup")) then
		warn(`[SettingsController] SoundService.{groupName} should be a SoundGroup`)
		return
	end
	slider.Group = group
	slider.MixedVolume = group.Volume

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

function SettingsController.Start()
	for name in Volumes do
		local slider: Slider = {
			Name = name,
			Group = nil,
			MixedVolume = 1,
			Volume = 1,
			Changed = false,
			Track = nil,
			Fill = nil,
			Knob = nil,
		}
		sliders[name] = slider
		bindGroup(slider)
		LocalPlayer:GetAttributeChangedSignal(`{name}Volume`):Connect(function()
			loadSavedVolume(slider)
		end)
		loadSavedVolume(slider)
	end

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
