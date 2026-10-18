local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local HOVER_SCALE = 1.1 -- Buttons grow to this while the mouse is over them
local HOVER_INFO = TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local PRESS_SCALE = 0.9 -- And shrink to this while held down
local PRESS_INFO = TweenInfo.new(0.08, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local RELEASE_INFO = TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out) -- Springs back up

-- Constraints that shape a gui's box; the holder needs them too to keep the same box
local SHAPING_CONSTRAINTS = { "UIAspectRatioConstraint", "UISizeConstraint" }

local ButtonController = {}

local function isPress(input: InputObject): boolean
	return input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch
end

-- A UIScale scales from a gui's corner, and a UIListLayout would let it grow over its neighbours, so
-- the gui moves into an invisible holder that takes its place and is scaled from the holder's center
local function makeScalable(gui: GuiObject): UIScale
	local holder = Instance.new("Frame")
	holder.Name = `{gui.Name}Holder`
	holder.BackgroundTransparency = 1
	holder.BorderSizePixel = 0
	holder.AnchorPoint = gui.AnchorPoint
	holder.Position = gui.Position
	holder.Size = gui.Size
	holder.SizeConstraint = gui.SizeConstraint
	holder.LayoutOrder = gui.LayoutOrder
	holder.ZIndex = gui.ZIndex
	for _, className in SHAPING_CONSTRAINTS do
		local constraint = gui:FindFirstChildOfClass(className)
		if constraint then
			constraint:Clone().Parent = holder
		end
	end
	holder.Parent = gui.Parent

	gui.AnchorPoint = Vector2.new(0.5, 0.5)
	gui.Position = UDim2.fromScale(0.5, 0.5)
	gui.Size = UDim2.fromScale(1, 1)
	gui.SizeConstraint = Enum.SizeConstraint.RelativeXY
	gui.Parent = holder

	local scale = Instance.new("UIScale")
	scale.Name = "AnimationScale"
	scale.Parent = gui
	return scale
end

-- The button grows while hovered and presses down while held. Anything in scaledWith, like the
-- icon next to it on a sign, grows and presses along with it
function ButtonController.Animate(button: GuiButton, scaledWith: { GuiObject }?)
	local scales = { makeScalable(button) }
	for _, gui in scaledWith or {} do
		table.insert(scales, makeScalable(gui))
	end

	local hovered, pressed = false, false
	-- A new tween on Scale replaces the running one, so hover and press can't fight
	local function animate(info: TweenInfo)
		local goal = if pressed then PRESS_SCALE elseif hovered then HOVER_SCALE else 1
		for _, scale in scales do
			TweenService:Create(scale, info, { Scale = goal }):Play()
		end
	end

	button.MouseEnter:Connect(function()
		hovered = true
		animate(HOVER_INFO)
	end)
	button.MouseLeave:Connect(function()
		hovered = false
		animate(HOVER_INFO)
	end)
	button.InputBegan:Connect(function(input)
		if isPress(input) then
			pressed = true
			animate(PRESS_INFO)
		end
	end)
	-- Listened for everywhere, since the press can be let go off the button
	local released = UserInputService.InputEnded:Connect(function(input)
		if pressed and isPress(input) then
			pressed = false
			animate(RELEASE_INFO)
		end
	end)
	button.Destroying:Connect(function()
		released:Disconnect()
	end)
end

return ButtonController
