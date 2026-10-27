local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Icon = require(ReplicatedStorage.Packages.TopbarPlus)

local ButtonController = require(script.Parent.ButtonController)
local HudController = require(script.Parent.HudController)

local SetSfxVolume = ReplicatedStorage.Remotes.SetSfxVolume
local LocalPlayer = Players.LocalPlayer
local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")

-- The topbar button opens and closes the Settings gui, and its exit button closes it too. It stays
-- through drops, when the rest of the HUD has moved out
local ICON_IMAGE = "rbxassetid://18801194936"
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

local SettingsController = {}

local icon: any = nil
local isOpen = false
local openVersion = 0 -- Counts opens and closes, so a close that's been reopened since doesn't hide it

-- Parts of the Settings gui, which is remade on every respawn, so they're found again each time
local main: GuiObject? = nil
local openScale: UIScale? = nil
local track: GuiObject? = nil -- The Sound row's Scroller, which the slider runs along
local fill: GuiObject? = nil
local knob: GuiObject? = nil

local blur: BlurEffect? = nil
local fovBoost = Instance.new("NumberValue") -- How far the view's widened right now, tweened in and out
-- The camera the widening is on until the frame's drawn, and its FieldOfView without and with it
local widenedCamera: Camera? = nil
local unwidenedFov = 0
local widenedFov = 0

-- SoundService.SFX, the SoundGroup every sound effect plays through. The slider sets its Volume as a
-- share of what it's set to in Studio, so all the way up the effects sound as they were mixed
local sfx: SoundGroup? = nil
local mixedVolume = 1
local sfxVolume = 1 -- Where the slider is, 0 to 1
-- Set once the player moves the slider, so their saved volume reaching the client late can't move it back
local changed = false
local press: InputObject? = nil -- The click or touch dragging the slider

local function isPress(input: InputObject): boolean
	return input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch
end

-- A mouse's button is the same from press to let go, while each touch is its own
local function isSameInput(a: InputObject, b: InputObject): boolean
	return a == b or (a.UserInputType == b.UserInputType and a.UserInputType ~= Enum.UserInputType.Touch)
end

local function render()
	if fill then
		fill.Size = UDim2.new(UDim.new(sfxVolume, 0), fill.Size.Y)
		-- Its outline would still show as a sliver at nothing
		fill.Visible = sfxVolume > 0
	end
	if knob then
		knob.Position = UDim2.new(UDim.new(sfxVolume, 0), knob.Position.Y)
	end
end

local function setVolume(volume: number)
	sfxVolume = volume
	if sfx then
		sfx.Volume = mixedVolume * volume
	end
	render()
end

local function slideTo(x: number)
	local bar = track
	if not (bar and bar.AbsoluteSize.X > 0) then
		return
	end
	changed = true
	setVolume(math.clamp((x - bar.AbsolutePosition.X) / bar.AbsoluteSize.X, 0, 1))
end

-- Pressing anywhere on the bar or its knob jumps the slider there and starts dragging it
local function onPressed(input: InputObject)
	if press or not isPress(input) then
		return
	end
	press = input
	slideTo(input.Position.X)
end

local function onPointerMoved(input: InputObject)
	local current = press
	if not current then
		return
	end
	local isMouse = current.UserInputType == Enum.UserInputType.MouseButton1
	if isMouse and input.UserInputType ~= Enum.UserInputType.MouseMovement then
		return
	elseif not isMouse and input ~= current then
		return
	end
	slideTo(input.Position.X)
end

-- Kept once it's let go, rather than on every step of the drag
local function onPointerReleased(input: InputObject)
	local current = press
	if not (current and isSameInput(current, input)) then
		return
	end
	press = nil
	SetSfxVolume:FireServer(sfxVolume)
end

local function loadSavedVolume()
	local saved = LocalPlayer:GetAttribute("SfxVolume")
	if typeof(saved) == "number" and not changed then
		setVolume(saved)
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

local function bindGui(gui: Instance)
	local frame = gui:WaitForChild("Main") :: GuiObject
	local exitButton = frame:WaitForChild("Header"):WaitForChild("ExitButton") :: GuiButton
	local scroller = frame:WaitForChild("Holder"):WaitForChild("Sound"):WaitForChild("Scroller") :: GuiObject
	local bar = scroller:WaitForChild("Fill") :: GuiObject
	local handle = scroller:WaitForChild("Slider") :: GuiObject

	main = frame
	track = scroller
	fill = bar
	knob = handle

	local scale = Instance.new("UIScale")
	scale.Name = "OpenScale"
	scale.Scale = if isOpen then 1 else OPEN_SCALE
	scale.Parent = frame
	openScale = scale
	frame.Visible = isOpen

	-- The knob sits centered on the end of the fill
	handle.AnchorPoint = Vector2.new(0.5, handle.AnchorPoint.Y)
	-- So a touch dragging the slider doesn't turn the camera as well
	scroller.Active = true
	handle.Active = true
	scroller.InputBegan:Connect(onPressed)
	handle.InputBegan:Connect(onPressed)
	render()

	ButtonController.Animate(exitButton)
	exitButton.Activated:Connect(function()
		if icon then
			icon:deselect()
		end
	end)
end

-- A sound plays through the group its SoundGroup names rather than the one it's kept in, so every
-- sound in SFX, and every copy of one played there, is pointed at it
local function bindSoundGroup()
	local group = SoundService:FindFirstChild("SFX")
	if not (group and group:IsA("SoundGroup")) then
		warn("[SettingsController] SoundService.SFX should be a SoundGroup")
		return
	end
	sfx = group
	mixedVolume = group.Volume

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
		:setCaption(ICON_CAPTION)
		:setOrder(ICON_ORDER)
		:bindEvent("toggled", function(_, isSelected: boolean)
			setOpen(isSelected)
		end)
end

function SettingsController.Start()
	bindSoundGroup()
	LocalPlayer:GetAttributeChangedSignal("SfxVolume"):Connect(loadSavedVolume)
	loadSavedVolume()

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
	-- Listened for everywhere, since the slider can be let go off the bar
	UserInputService.InputEnded:Connect(onPointerReleased)
end

return SettingsController
