local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Tutorial = require(ReplicatedStorage.Shared.Tutorial)

local LocalPlayer = Players.LocalPlayer
local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")

-- A message across the top of the screen. The TopTexts gui holds a frame named Template, designed in
-- StarterGui, with the words in a TextLabel named Text inside it. A message is a copy of that frame
-- which fades in, and fades away when it's replaced or taken down, before the next one fades in
local GUI_NAME = "TopTexts"
local TEMPLATE_NAME = "Template"
local TEXT_LABEL_NAME = "Text"
local MESSAGE_NAME = "Message" -- A copy, so it's never mistaken for the template

local FADE_IN_INFO = TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local FADE_OUT_INFO = TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
local FLASH_TIME = 1.25 -- Seconds a flashed message lasts, counting its fades, before what's wanted comes back

-- The properties that fade, by the classes that have them. Each fades between what it's set to in
-- Studio and fully see-through
local FADED_PROPERTIES = {
	GuiObject = { "BackgroundTransparency" },
	TextLabel = { "TextTransparency", "TextStrokeTransparency" },
	ImageLabel = { "ImageTransparency" },
	UIStroke = { "Transparency" },
}

local wanted: string? = nil -- What should be up
local flash: string? = nil -- What's up instead for a moment
local flashes = 0 -- Counts them, so only the latest one takes itself down
local shown: GuiObject? = nil -- The copy that's up, or fading in
local shownText: string? = nil
local leaving = false -- The last copy is still fading away, which the next one waits for

local TopTextController = {}

local function forEachFaded(root: Instance, callback: (instance: any, property: string) -> ())
	local function visit(instance: Instance)
		for className, properties in FADED_PROPERTIES do
			if instance:IsA(className) then
				for _, property in properties do
					callback(instance, property)
				end
			end
		end
	end
	visit(root)
	for _, descendant in root:GetDescendants() do
		visit(descendant)
	end
end

local function getTemplate(): GuiObject?
	local gui = PlayerGui:FindFirstChild(GUI_NAME)
	local template = gui and gui:FindFirstChild(TEMPLATE_NAME)
	return if template and template:IsA("GuiObject") then template else nil
end

local function fadeIn(text: string)
	local template = getTemplate()
	if not template then
		return
	end
	local message = template:Clone()
	message.Name = MESSAGE_NAME
	local label = message:FindFirstChild(TEXT_LABEL_NAME, true)
	if label and label:IsA("TextLabel") then
		label.Text = text
	end
	forEachFaded(message, function(instance, property)
		local rest = instance[property]
		instance[property] = 1
		TweenService:Create(instance, FADE_IN_INFO, { [property] = rest }):Play()
	end)
	message.Visible = true
	message.Parent = template.Parent
	shown, shownText = message, text
end

local function fadeOut(message: GuiObject)
	forEachFaded(message, function(instance, property)
		TweenService:Create(instance, FADE_OUT_INFO, { [property] = 1 }):Play()
	end)
	task.delay(FADE_OUT_INFO.Time, message.Destroy, message)
end

-- Takes down what's up if it isn't what's wanted, and once that's gone puts up what is
local function refresh()
	local goal = flash or wanted
	local message = shown
	if message and shownText ~= goal then
		shown, shownText = nil, nil
		leaving = true
		fadeOut(message)
		task.delay(FADE_OUT_INFO.Time, function()
			leaving = false
			refresh()
		end)
	elseif goal and not message and not leaving then
		fadeIn(goal)
	end
end

-- Puts this message up in place of whatever's there, or takes it down with nil. Showing what's already
-- up does nothing, so it can be called as often as needed
function TopTextController.Show(text: string?)
	if text ~= wanted then
		wanted = text
		refresh()
	end
end

-- Puts this message up for a moment, then what was wanted comes back. It lasts this many seconds,
-- counting its fades, or FLASH_TIME without. Flashing it again while it's up just keeps it there longer
function TopTextController.Flash(text: string, seconds: number?)
	flash = text
	flashes += 1
	local count = flashes
	refresh()
	task.delay(seconds or FLASH_TIME, function()
		if flashes == count then
			flash = nil
			refresh()
		end
	end)
end

-- Whether the tutorial lets the player do this now. If it doesn't, they're told to do the tutorial first
function TopTextController.CheckTutorial(action: string): boolean
	if Tutorial.Allows(LocalPlayer, action) then
		return true
	end
	TopTextController.Flash(Tutorial.LOCKED_TEXT)
	return false
end

-- The gui comes back as designed on every respawn, without the copy that was up, so the template goes
-- out of sight and whatever's wanted fades back in
local function bindGui(gui: Instance)
	local template = gui:FindFirstChild(TEMPLATE_NAME)
	if template and template:IsA("GuiObject") then
		template.Visible = false
	end
	shown, shownText = nil, nil
	refresh()
end

function TopTextController.Start()
	PlayerGui.ChildAdded:Connect(function(child)
		if child.Name == GUI_NAME then
			bindGui(child)
		end
	end)
	local gui = PlayerGui:FindFirstChild(GUI_NAME)
	if gui then
		bindGui(gui)
	end
end

return TopTextController
