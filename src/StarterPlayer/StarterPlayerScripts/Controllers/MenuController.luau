local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local ButtonController = require(script.Parent.ButtonController)
local HudController = require(script.Parent.HudController)

-- A menu that takes over the screen, like Settings, opens by fading in as it grows from its center and
-- rises into place, overshooting a little, and closes by fading out as it shrinks and drops back away
local CLOSED_SCALE = 0.85 -- Of its size
local CLOSED_DROP = 0.08 -- Of its height, how far below its place it rises from and drops back to
local OPEN_POSITION = UDim2.fromScale(0.5, 0.5) -- In the holder that takes its place (see ButtonController)
local CLOSED_POSITION = UDim2.fromScale(0.5, 0.5 + CLOSED_DROP)
local OPEN_INFO = TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local OPEN_FADE_INFO = TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out) -- Solid before it settles
local CLOSE_INFO = TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
-- The properties that fade, by the classes that have them. Each fades from what it's set to in
-- Studio up to fully see-through
local FADED_PROPERTIES = {
	GuiObject = { "BackgroundTransparency" },
	TextLabel = { "TextTransparency", "TextStrokeTransparency" },
	TextButton = { "TextTransparency", "TextStrokeTransparency" },
	ImageLabel = { "ImageTransparency" },
	ImageButton = { "ImageTransparency" },
	UIStroke = { "Transparency" },
}
-- While one's open the world behind it blurs a little and the camera widens its view
local BLUR_SIZE = 12
local FOV_BOOST = 10 -- Degrees added to the camera's FieldOfView
local EFFECTS_IN_INFO = TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local EFFECTS_OUT_INFO = TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local FOV_STEP_NAME = "MenuFov"

export type Menu = {
	IsOpen: boolean,
	OpenVersion: number, -- Counts opens and closes, so a close that's been reopened since doesn't hide it
	-- Parts of its gui, which is remade on every respawn, so they're found again each time
	Main: GuiObject?,
	OpenScale: UIScale?,
	-- Each faded thing in the menu -> its faded properties -> what they're at fully shown
	FadeBases: { [Instance]: { [string]: number } },
	Shown: NumberValue, -- How far the menu's faded in, 0 to 1, tweened in and out
}

-- How many menus are open. Two can be at once, so everything they share stays until the last one closes
local openMenus = 0
local effectsVersion = 0 -- Counts the effects coming on and going off, so going off that's been undone since doesn't hide them

local blur: BlurEffect? = nil
local fovBoost = Instance.new("NumberValue") -- How far the view's widened right now, tweened in and out
-- The camera the widening is on until the frame's drawn, and its FieldOfView without and with it
local widenedCamera: Camera? = nil
local unwidenedFov = 0
local widenedFov = 0

local MenuController = {}

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

local function fade(menu: Menu, instance: Instance, properties: { [string]: number })
	for property, base in properties do
		(instance :: any)[property] = 1 - (1 - base) * menu.Shown.Value
	end
end

local function fadeAll(menu: Menu)
	for instance, properties in menu.FadeBases do
		fade(menu, instance, properties)
	end
end

-- Keeps what it's at now as fully shown, so it's tracked before it's ever faded. Buttons' holders
-- (see ButtonController) come in after it's bound, and a button moved into one is already tracked
local function trackFade(menu: Menu, bases: { [Instance]: { [string]: number } }, instance: Instance)
	if bases[instance] then
		return
	end
	local properties = {}
	for className, names in FADED_PROPERTIES do
		if instance:IsA(className) then
			for _, property in names do
				properties[property] = (instance :: any)[property]
			end
		end
	end
	if next(properties) ~= nil then
		bases[instance] = properties
		fade(menu, instance, properties)
	end
end

local function setEffects(on: boolean)
	effectsVersion += 1
	local version = effectsVersion

	HudController.SetMenuOpen(on)
	local effectsInfo = if on then EFFECTS_IN_INFO else EFFECTS_OUT_INFO
	TweenService:Create(fovBoost, effectsInfo, { Value = if on then FOV_BOOST else 0 }):Play()
	local effect = blur
	if effect then
		effect.Enabled = true
		TweenService:Create(effect, effectsInfo, { Size = if on then BLUR_SIZE else 0 }):Play()
		if not on then
			task.delay(effectsInfo.Time, function()
				if effectsVersion == version then
					effect.Enabled = false
				end
			end)
		end
	end
end

function MenuController.Create(): Menu
	local menu: Menu = {
		IsOpen = false,
		OpenVersion = 0,
		Main = nil,
		OpenScale = nil,
		FadeBases = {},
		Shown = Instance.new("NumberValue"),
	}
	menu.Shown.Changed:Connect(function()
		fadeAll(menu)
	end)
	return menu
end

-- Takes on the menu's frame, each time its gui's made, and shows it as the menu is
function MenuController.Bind(menu: Menu, frame: GuiObject)
	menu.Main = frame
	-- Scaled from its center rather than wherever it's placed by
	local scale = ButtonController.MakeScalable(frame)
	scale.Scale = if menu.IsOpen then 1 else CLOSED_SCALE
	menu.OpenScale = scale
	frame.Position = if menu.IsOpen then OPEN_POSITION else CLOSED_POSITION
	frame.Visible = menu.IsOpen

	local bases = {}
	menu.FadeBases = bases
	trackFade(menu, bases, frame)
	for _, descendant in frame:GetDescendants() do
		trackFade(menu, bases, descendant)
	end
	frame.DescendantAdded:Connect(function(descendant)
		trackFade(menu, bases, descendant)
	end)
end

function MenuController.SetOpen(menu: Menu, open: boolean)
	if open == menu.IsOpen then
		return
	end
	menu.IsOpen = open
	menu.OpenVersion += 1
	local version = menu.OpenVersion

	openMenus += if open then 1 else -1
	if openMenus == (if open then 1 else 0) then
		setEffects(open)
	end

	local frame, scale = menu.Main, menu.OpenScale
	if not (frame and scale) then
		return
	end
	if open then
		-- From fully closed, or from wherever a close it interrupts had got to
		if not frame.Visible then
			scale.Scale = CLOSED_SCALE
			frame.Position = CLOSED_POSITION
			menu.Shown.Value = 0
			fadeAll(menu)
		end
		frame.Visible = true
		TweenService:Create(scale, OPEN_INFO, { Scale = 1 }):Play()
		TweenService:Create(frame, OPEN_INFO, { Position = OPEN_POSITION }):Play()
		TweenService:Create(menu.Shown, OPEN_FADE_INFO, { Value = 1 }):Play()
	else
		TweenService:Create(scale, CLOSE_INFO, { Scale = CLOSED_SCALE }):Play()
		TweenService:Create(frame, CLOSE_INFO, { Position = CLOSED_POSITION }):Play()
		TweenService:Create(menu.Shown, CLOSE_INFO, { Value = 0 }):Play()
		task.delay(CLOSE_INFO.Time, function()
			if menu.OpenVersion == version then
				frame.Visible = false
			end
		end)
	end
end

-- On the camera, so it's only on this player's screen and out of the way of the stage lighting looks
local function createBlur()
	local effect = Instance.new("BlurEffect")
	effect.Name = "MenuBlur"
	effect.Size = 0
	effect.Enabled = false
	effect.Parent = workspace.CurrentCamera
	blur = effect
	workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
		effect.Parent = workspace.CurrentCamera
	end)
end

function MenuController.Start()
	createBlur()
	-- After every other camera step, the drop camera's too, and taken off once the frame's drawn
	RunService:BindToRenderStep(FOV_STEP_NAME, Enum.RenderPriority.Last.Value, widen)
	RunService.PreAnimation:Connect(unwiden)
end

return MenuController
