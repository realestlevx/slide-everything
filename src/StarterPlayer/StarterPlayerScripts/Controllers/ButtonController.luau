local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local HOVER_SCALE = 1.1 -- Buttons grow to this while the mouse is over them
local HOVER_INFO = TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local PRESS_SCALE = 0.9 -- And shrink to this while held down
local PRESS_INFO = TweenInfo.new(0.08, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local RELEASE_INFO = TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out) -- Springs back up

local PULSE_SCALE = 1.5 -- A click's pulse grows to this size of the button
local PULSE_GROW_INFO = TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local PULSE_FILL_INFO = TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out) -- The white fill fades first
local PULSE_STROKE_INFO = TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.In) -- Then its outline
local PULSE_FILL_TRANSPARENCY = 0.4 -- How see-through the fill starts

-- Constraints that shape a gui's box; the holder needs them too to keep the same box
local SHAPING_CONSTRAINTS = { "UIAspectRatioConstraint", "UISizeConstraint" }

local ButtonController = {}

local function isPress(input: InputObject): boolean
	return input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch
end

-- A UIScale scales from a gui's corner, and a UIListLayout would let it grow over its neighbours, so
-- the gui moves into an invisible holder that takes its place and is scaled from the holder's center
function ButtonController.MakeScalable(gui: GuiObject): UIScale
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
	local scales = { ButtonController.MakeScalable(button) }
	for _, gui in scaledWith or {} do
		table.insert(scales, ButtonController.MakeScalable(gui))
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

-- A white copy of the button's shape grows out over it and fades, its fill first and then
-- its outline, so it looks like two rings. For a button that's had Animate, which puts it in a holder
-- with its own box to grow from
function ButtonController.Pulse(button: GuiButton)
	local holder = button.Parent
	if not (holder and holder:IsA("GuiObject")) then
		return
	end

	local pulse = Instance.new("Frame")
	pulse.Name = "Pulse"
	pulse.AnchorPoint = Vector2.new(0.5, 0.5)
	pulse.Position = UDim2.fromScale(0.5, 0.5)
	pulse.Size = UDim2.fromScale(1, 1)
	pulse.BackgroundColor3 = Color3.new(1, 1, 1)
	pulse.BackgroundTransparency = PULSE_FILL_TRANSPARENCY
	pulse.BorderSizePixel = 0
	pulse.ZIndex = button.ZIndex + 1

	-- Same corners and outline thickness as the button, without its gradient
	local corner = button:FindFirstChildOfClass("UICorner")
	if corner then
		corner:Clone().Parent = pulse
	end
	local buttonStroke = button:FindFirstChildOfClass("UIStroke")
	local stroke = if buttonStroke then buttonStroke:Clone() else Instance.new("UIStroke")
	stroke:ClearAllChildren()
	stroke.Color = Color3.new(1, 1, 1)
	stroke.Transparency = 0
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Parent = pulse
	pulse.Parent = holder

	TweenService:Create(pulse, PULSE_GROW_INFO, { Size = UDim2.fromScale(PULSE_SCALE, PULSE_SCALE) }):Play()
	TweenService:Create(pulse, PULSE_FILL_INFO, { BackgroundTransparency = 1 }):Play()
	local fade = TweenService:Create(stroke, PULSE_STROKE_INFO, { Transparency = 1 })
	fade.Completed:Connect(function()
		pulse:Destroy()
	end)
	fade:Play()
end

-- For buttons already at their full size, which can't grow on hover: they only press down while
-- held. The caller says when that is, since keys can hold them down as well as touches
function ButtonController.AnimatePress(button: GuiButton): (held: boolean) -> ()
	local scale = ButtonController.MakeScalable(button)
	local isHeld = false
	return function(held: boolean)
		if held == isHeld then
			return
		end
		isHeld = held
		local info = if held then PRESS_INFO else RELEASE_INFO
		TweenService:Create(scale, info, { Scale = if held then PRESS_SCALE else 1 }):Play()
	end
end

return ButtonController
