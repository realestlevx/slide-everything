local UserInputService = game:GetService("UserInputService")
local ProximityPromptService = game:GetService("ProximityPromptService")
local TweenService = game:GetService("TweenService")
local TextService = game:GetService("TextService")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local LocalPlayer = Players.LocalPlayer
local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")

-- This script doesn't wait for game.Loaded, so wait for the module to replicate
local ApplyGradient = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("ApplyGradient"))

local GamepadButtonImage = {
	[Enum.KeyCode.ButtonX] = "rbxasset://textures/ui/Controls/xboxX.png",
	[Enum.KeyCode.ButtonY] = "rbxasset://textures/ui/Controls/xboxY.png",
	[Enum.KeyCode.ButtonA] = "rbxasset://textures/ui/Controls/xboxA.png",
	[Enum.KeyCode.ButtonB] = "rbxasset://textures/ui/Controls/xboxB.png",
	[Enum.KeyCode.DPadLeft] = "rbxasset://textures/ui/Controls/dpadLeft.png",
	[Enum.KeyCode.DPadRight] = "rbxasset://textures/ui/Controls/dpadRight.png",
	[Enum.KeyCode.DPadUp] = "rbxasset://textures/ui/Controls/dpadUp.png",
	[Enum.KeyCode.DPadDown] = "rbxasset://textures/ui/Controls/dpadDown.png",
	[Enum.KeyCode.ButtonSelect] = "rbxasset://textures/ui/Controls/xboxmenu.png",
	[Enum.KeyCode.ButtonL1] = "rbxasset://textures/ui/Controls/xboxLS.png",
	[Enum.KeyCode.ButtonR1] = "rbxasset://textures/ui/Controls/xboxRS.png",
}

local KeyboardButtonImage = {
	[Enum.KeyCode.Backspace] = "rbxasset://textures/ui/Controls/backspace.png",
	[Enum.KeyCode.Return] = "rbxasset://textures/ui/Controls/return.png",
	[Enum.KeyCode.LeftShift] = "rbxasset://textures/ui/Controls/shift.png",
	[Enum.KeyCode.RightShift] = "rbxasset://textures/ui/Controls/shift.png",
	[Enum.KeyCode.Tab] = "rbxasset://textures/ui/Controls/tab.png",
}

local KeyboardButtonIconMapping = {
	["'"] = "rbxasset://textures/ui/Controls/apostrophe.png",
	[","] = "rbxasset://textures/ui/Controls/comma.png",
	["`"] = "rbxasset://textures/ui/Controls/graveaccent.png",
	["."] = "rbxasset://textures/ui/Controls/period.png",
	[" "] = "rbxasset://textures/ui/Controls/spacebar.png",
}

local KeyCodeToTextMapping = {
	[Enum.KeyCode.LeftControl] = "Ctrl",
	[Enum.KeyCode.RightControl] = "Ctrl",
	[Enum.KeyCode.LeftAlt] = "Alt",
	[Enum.KeyCode.RightAlt] = "Alt",
	[Enum.KeyCode.F1] = "F1",
	[Enum.KeyCode.F2] = "F2",
	[Enum.KeyCode.F3] = "F3",
	[Enum.KeyCode.F4] = "F4",
	[Enum.KeyCode.F5] = "F5",
	[Enum.KeyCode.F6] = "F6",
	[Enum.KeyCode.F7] = "F7",
	[Enum.KeyCode.F8] = "F8",
	[Enum.KeyCode.F9] = "F9",
	[Enum.KeyCode.F10] = "F10",
	[Enum.KeyCode.F11] = "F11",
	[Enum.KeyCode.F12] = "F12",
}

local BOUNCE_IN_INFO = TweenInfo.new(0.4, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local FADE_OUT_TIME = 0.2
local FADE_OUT_SCALE_INFO = TweenInfo.new(FADE_OUT_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
local FADE_OUT_SCALE = 0.8
-- Quick squash when the prompt is triggered, like a button being pushed in, before it fades out
local PRESS_INFO = TweenInfo.new(0.1, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local PRESS_SCALE = 0.85
local SHINE_DELAY = 0.3
local SHINE_INFO = TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut)
-- Gradient offsets where the shine band is fully off the left / right edge
local SHINE_START_OFFSET = Vector2.new(-1, 0)
local SHINE_END_OFFSET = Vector2.new(1, 0)
-- Highlight strength up close. It stays at full strength out to HIGHLIGHT_FADE_START studs, then
-- fades to fully clear at the edge of the prompt's range
local HIGHLIGHT_FILL_TRANSPARENCY = 0.9
local HIGHLIGHT_OUTLINE_TRANSPARENCY = 0
local HIGHLIGHT_FADE_START = 6

local function getScreenGui()
	local screenGui = PlayerGui:FindFirstChild("ProximityPrompts")
	if screenGui == nil then
		screenGui = Instance.new("ScreenGui")
		screenGui.Name = "ProximityPrompts"
		screenGui.ResetOnSpawn = false
		screenGui.Parent = PlayerGui
	end
	return screenGui
end

local function getWorldPosition(instance)
	if instance:IsA("Attachment") then
		return instance.WorldPosition
	elseif instance:IsA("BasePart") then
		return instance.Position
	elseif instance:IsA("Model") then
		return instance:GetPivot().Position
	end
	return nil
end

-- Outlines whatever the prompt belongs to while it's in range, fading out the farther away the player
-- gets. Made on the client, so only this player sees it, and destroyed when the prompt hides instead
-- of being kept around disabled. Occluded, so it doesn't show through walls. Returns the function
-- that removes it
local function createHighlight(prompt)
	local holder = prompt.Parent
	local target = holder and holder.Parent
	if target == nil then
		return function() end
	end

	local highlight = Instance.new("Highlight")
	highlight.Name = "PromptHighlight"
	highlight.DepthMode = Enum.HighlightDepthMode.Occluded
	highlight.FillColor = Color3.new(1, 1, 1)
	highlight.FillTransparency = HIGHLIGHT_FILL_TRANSPARENCY
	highlight.OutlineColor = Color3.new(1, 1, 1)
	highlight.OutlineTransparency = HIGHLIGHT_OUTLINE_TRANSPARENCY

	local function updateFade()
		local character = LocalPlayer.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		local position = getWorldPosition(holder)
		if root == nil or position == nil then
			return
		end

		local distance = (root.Position - position).Magnitude
		local fadeRange = math.max(prompt.MaxActivationDistance - HIGHLIGHT_FADE_START, 0.01)
		local fade = math.clamp((distance - HIGHLIGHT_FADE_START) / fadeRange, 0, 1)
		highlight.FillTransparency = HIGHLIGHT_FILL_TRANSPARENCY + (1 - HIGHLIGHT_FILL_TRANSPARENCY) * fade
		highlight.OutlineTransparency = HIGHLIGHT_OUTLINE_TRANSPARENCY + (1 - HIGHLIGHT_OUTLINE_TRANSPARENCY) * fade
	end

	-- Faded before it's parented so it never flashes in at full strength
	updateFade()
	highlight.Parent = target
	local fadeConnection = RunService.Heartbeat:Connect(updateFade)

	return function()
		fadeConnection:Disconnect()
		highlight:Destroy()
	end
end

local function setUpCircularProgressBar(bar)
	local leftGradient = bar.LeftGradient.ProgressBarImage.UIGradient
	local rightGradient = bar.RightGradient.ProgressBarImage.UIGradient

	local progress = bar.Progress
	progress.Changed:Connect(function(value)
		local angle = math.clamp(value * 360, 0, 360)
		leftGradient.Rotation = math.clamp(angle, 180, 360)
		rightGradient.Rotation = math.clamp(angle, 0, 180)
	end)
end

local function createPrompt(prompt, inputType, gui)
	local tweensForButtonHoldBegin = {}
	local tweensForButtonHoldEnd = {}
	local tweensForFadeOut = {}
	local tweensForFadeIn = {}
	local tweenInfoInFullDuration = TweenInfo.new(prompt.HoldDuration, Enum.EasingStyle.Linear, Enum.EasingDirection.Out)
	local tweenInfoFast = TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	local tweenInfoQuick = TweenInfo.new(0.06, Enum.EasingStyle.Linear, Enum.EasingDirection.Out)
	local tweenInfoInstant = TweenInfo.new(0, Enum.EasingStyle.Linear, Enum.EasingDirection.Out)

	local promptUI = nil
	local promptTheme = prompt:GetAttribute("Theme")
	if promptTheme then
		local themedPromptUI = script:FindFirstChild(promptTheme)
		if themedPromptUI then
			promptUI = themedPromptUI:Clone()
		end
	end

	if promptUI == nil then
		promptUI = script.Default:Clone()
	end

	promptUI.Enabled = true
	local templateSize = promptUI.Size

	local frame = promptUI.PromptFrame
	local inputFrame = frame.InputFrame
	local actionText = frame.ActionText
	local objectText = frame.ObjectText
	local defaultActionTextColor = actionText.TextColor3

	-- An exact copy of the action text on top of it, for when a gradient covers only part of the text.
	-- Made before the tweens are set up so it fades along with everything else
	local gradientText = actionText:Clone()
	gradientText.Name = "ActionTextGradient"
	gradientText.Text = ""
	-- A stroke still draws hidden characters as solid shapes, which would black out the action text's
	-- part underneath. The action text strokes the whole text instead
	for _, child in gradientText:GetChildren() do
		if child:IsA("UIStroke") then
			child:Destroy()
		end
	end
	gradientText.Parent = frame
	local actionTextStroke = actionText:FindFirstChildOfClass("UIStroke")

	-- Center the frame so the bounce scales from the middle instead of the top-left corner
	frame.AnchorPoint = Vector2.new(0.5, 0.5)
	frame.Position = UDim2.fromScale(0.5, 0.5)
	local bounceScale = Instance.new("UIScale")
	bounceScale.Name = "BounceScale"
	bounceScale.Scale = 0
	bounceScale.Parent = frame
	local bounceInTween = TweenService:Create(bounceScale, BOUNCE_IN_INFO, { Scale = 1 })
	local fadeOutScaleTween = TweenService:Create(bounceScale, FADE_OUT_SCALE_INFO, { Scale = FADE_OUT_SCALE })
	local pressTween = TweenService:Create(bounceScale, PRESS_INFO, { Scale = PRESS_SCALE })
	local pressThread = nil
	local releasedDuringPress = false

	-- Shine line that sweeps across the prompt shortly after it opens
	local shine = frame:FindFirstChild("Shine")
	local shineGradient = shine and shine:FindFirstChildOfClass("UIGradient")
	local shineTween = shineGradient and TweenService:Create(shineGradient, SHINE_INFO, { Offset = SHINE_END_OFFSET })
	local shineThread = nil

	-- Tweens for Frame and children
	local backgroundTransparency = frame.BackgroundTransparency
	local imageTransparency = frame.ImageTransparency
	frame.BackgroundTransparency = 1
	frame.ImageTransparency = 1
	-- TODO consolidate this with the other tweens for image labels, theres some duplication
	-- TODO make these functions somehow consolidate the properties objects?
	table.insert(tweensForButtonHoldBegin, TweenService:Create(frame, tweenInfoFast, { Size = UDim2.fromScale(0.5, 1), BackgroundTransparency = 1, ImageTransparency = 1 }))
	table.insert(tweensForButtonHoldEnd, TweenService:Create(frame, tweenInfoFast, { Size = UDim2.fromScale(1, 1), BackgroundTransparency = backgroundTransparency, ImageTransparency = imageTransparency }))
	table.insert(tweensForFadeOut, TweenService:Create(frame, tweenInfoFast, { BackgroundTransparency = 1, ImageTransparency = 1 }))
	table.insert(tweensForFadeIn, TweenService:Create(frame, tweenInfoFast, { BackgroundTransparency = backgroundTransparency, ImageTransparency = imageTransparency }))

	local function setupUIStrokeTweens(uiStroke)
		local transparency = uiStroke.Transparency
		uiStroke.Transparency = 1
		table.insert(tweensForButtonHoldBegin, TweenService:Create(uiStroke, tweenInfoFast, { Transparency = 1 }))
		table.insert(tweensForButtonHoldEnd, TweenService:Create(uiStroke, tweenInfoFast, { Transparency = transparency }))
		table.insert(tweensForFadeOut, TweenService:Create(uiStroke, tweenInfoFast, { Transparency = 1 }))
		table.insert(tweensForFadeIn, TweenService:Create(uiStroke, tweenInfoFast, { Transparency = transparency }))
	end

	local function setupGUIObjectTweens(guiObject)
		local guiObjectBackgroundTransparency = guiObject.BackgroundTransparency
		guiObject.BackgroundTransparency = 1
		table.insert(tweensForButtonHoldBegin, TweenService:Create(guiObject, tweenInfoFast, { BackgroundTransparency = 1 }))
		table.insert(tweensForButtonHoldEnd, TweenService:Create(guiObject, tweenInfoFast, { BackgroundTransparency = guiObjectBackgroundTransparency }))
		table.insert(tweensForFadeOut, TweenService:Create(guiObject, tweenInfoFast, { BackgroundTransparency = 1 }))
		table.insert(tweensForFadeIn, TweenService:Create(guiObject, tweenInfoFast, { BackgroundTransparency = guiObjectBackgroundTransparency }))
	end

	local function setupTextLabelTweens(textLabel)
		local textTransparency = textLabel.TextTransparency
		local textStrokeTransparency = textLabel.TextStrokeTransparency
		textLabel.TextTransparency = 1
		textLabel.TextStrokeTransparency = 1
		table.insert(tweensForButtonHoldBegin, TweenService:Create(textLabel, tweenInfoFast, { TextTransparency = 1, TextStrokeTransparency = 1 }))
		table.insert(tweensForButtonHoldEnd, TweenService:Create(textLabel, tweenInfoFast, { TextTransparency = textTransparency, TextStrokeTransparency = textStrokeTransparency }))
		table.insert(tweensForFadeOut, TweenService:Create(textLabel, tweenInfoFast, { TextTransparency = 1, TextStrokeTransparency = 1 }))
		table.insert(tweensForFadeIn, TweenService:Create(textLabel, tweenInfoFast, { TextTransparency = textTransparency, TextStrokeTransparency = textStrokeTransparency }))
	end

	local function setupImageLabelTweens(imageLabel)
		local imageTransparency = imageLabel.ImageTransparency
		imageLabel.ImageTransparency = 1
		table.insert(tweensForButtonHoldBegin, TweenService:Create(imageLabel, tweenInfoFast, { ImageTransparency = 1 }))
		table.insert(tweensForButtonHoldEnd, TweenService:Create(imageLabel, tweenInfoFast, { ImageTransparency = imageTransparency }))
		table.insert(tweensForFadeOut, TweenService:Create(imageLabel, tweenInfoFast, { ImageTransparency = 1 }))
		table.insert(tweensForFadeIn, TweenService:Create(imageLabel, tweenInfoFast, { ImageTransparency = imageTransparency }))
	end

	local function setupUnexpectedChildTweens(child)
		if child:IsA("UIStroke") then
			setupUIStrokeTweens(child)
		elseif child:IsA("UIGradient") then
			-- The Transparency property of UIGradients is not tweenable
		elseif child:IsA("GuiObject") then
			setupGUIObjectTweens(child)

			if child:IsA("TextLabel") then
				setupTextLabelTweens(child)
			elseif child:IsA("ImageLabel") then
				setupImageLabelTweens(child)
			end
		end

		for _, grandChild in pairs(child:GetChildren()) do
			setupUnexpectedChildTweens(grandChild)
		end
	end

	-- Key is UI object, value is whether or not we should tween out the children of it in the same manner
	local expectedFrameChildren = {[inputFrame] = false, [actionText] = true, [objectText] = true}
	for _, child in pairs(frame:GetChildren()) do
		if expectedFrameChildren[child] == nil then
			-- Unexpected child of the frame and direct children elements
			setupUnexpectedChildTweens(child)
		elseif expectedFrameChildren[child] == true then
			for _, grandChild in pairs(child:GetChildren()) do
				-- All children of ActionText or ObjectText
				setupUnexpectedChildTweens(grandChild)
			end
		end
	end

	-- Tweens for InputFrame
	local resizeableInputFrame = inputFrame.Frame
	local inputFrameScaler = resizeableInputFrame.UIScale
	local inputFrameScaleFactor = inputType == Enum.ProximityPromptInputType.Touch and 1.6 or 1.33
	table.insert(tweensForButtonHoldBegin, TweenService:Create(inputFrameScaler, tweenInfoFast, { Scale = inputFrameScaleFactor }))
	table.insert(tweensForButtonHoldEnd, TweenService:Create(inputFrameScaler, tweenInfoFast, { Scale = 1 }))

	-- Tweens for ActionText and ObjectText
	setupTextLabelTweens(actionText)
	setupTextLabelTweens(objectText)

	local buttonFrame = resizeableInputFrame.ButtonFrame

	local function setupButtonFrameTweens()
		local buttonFrameBackgroundTransparency = buttonFrame.BackgroundTransparency
		local buttonFrameImageTransparency = buttonFrame.ImageTransparency

		table.insert(tweensForFadeOut, TweenService:Create(buttonFrame, tweenInfoQuick, { BackgroundTransparency = 1, ImageTransparency = 1 }))
		table.insert(tweensForFadeIn, TweenService:Create(buttonFrame, tweenInfoQuick, { BackgroundTransparency = buttonFrameBackgroundTransparency, ImageTransparency = buttonFrameImageTransparency }))

		for _, child in pairs(buttonFrame:getChildren()) do
			if child:IsA("UIStroke") then
				local transparency = child.Transparency
				table.insert(tweensForFadeOut, TweenService:Create(child, tweenInfoQuick, { Transparency = 1 }))
				table.insert(tweensForFadeIn, TweenService:Create(child, tweenInfoQuick, { Transparency = transparency }))
			end
			-- Currently not supporting any other children other than UIStroke
		end
	end
	setupButtonFrameTweens()

	local buttonImage = resizeableInputFrame.ButtonImage
	local buttonText = resizeableInputFrame.ButtonText
	local icon = resizeableInputFrame.ButtonTextImage

	local function setupButtonTextTweens()
		local textTransparency = buttonText.TextTransparency
		local textStrokeTransparency = buttonText.TextStrokeTransparency
		local textBackgroundTransparency = buttonText.BackgroundTransparency
		buttonText.BackgroundTransparency = 1
		buttonText.TextStrokeTransparency = 1
		buttonText.TextTransparency = 1
		table.insert(tweensForFadeOut, TweenService:Create(buttonText, tweenInfoQuick, { TextTransparency = 1, TextStrokeTransparency = 1, BackgroundTransparency = 1 }))
		table.insert(tweensForFadeIn, TweenService:Create(buttonText, tweenInfoQuick, { TextTransparency = textTransparency, TextStrokeTransparency = textStrokeTransparency, BackgroundTransparency = textBackgroundTransparency }))

		for _, child in pairs(buttonText:getChildren()) do
			if child:IsA("UIStroke") then
				local transparency = child.Transparency
				table.insert(tweensForFadeOut, TweenService:Create(child, tweenInfoQuick, { Transparency = 1 }))
				table.insert(tweensForFadeIn, TweenService:Create(child, tweenInfoQuick, { Transparency = transparency }))
			end
			-- Currently not supporting any other children other than UIStroke
		end
	end

	local function setupButtonImageTweens()
		local buttonImageTransparency = buttonImage.ImageTransparency
		local buttonImageBackgroundTransparency = buttonImage.BackgroundTransparency
		buttonImage.BackgroundTransparency = 1
		buttonImage.ImageTransparency = 1
		table.insert(tweensForFadeOut, TweenService:Create(buttonImage, tweenInfoQuick, { ImageTransparency = 1, BackgroundTransparency = 1 }))
		table.insert(tweensForFadeIn, TweenService:Create(buttonImage, tweenInfoQuick, { ImageTransparency = buttonImageTransparency, BackgroundTransparency = buttonImageBackgroundTransparency }))
	end

	local function setupIconTweens()
		local iconBackgroundTransparency = icon.BackgroundTransparency
		local iconImageTransparency = icon.ImageTransparency
		icon.BackgroundTransparency = 1
		icon.ImageTransparency = 1
		table.insert(tweensForFadeOut, TweenService:Create(icon, tweenInfoQuick, { ImageTransparency = 1, BackgroundTransparency = 1 }))
		table.insert(tweensForFadeIn, TweenService:Create(icon, tweenInfoQuick, { ImageTransparency = iconImageTransparency, BackgroundTransparency = iconBackgroundTransparency }))
	end

	if inputType == Enum.ProximityPromptInputType.Gamepad then
		if GamepadButtonImage[prompt.GamepadKeyCode] then
			setupIconTweens()
			icon.Image = GamepadButtonImage[prompt.GamepadKeyCode]

			-- Hide ButtonText and ButtonImage, show ButtonTextImage
			buttonText.Visible = false
			buttonImage.Visible = false
			icon.Visible = true
		end
	elseif inputType == Enum.ProximityPromptInputType.Touch then
		setupButtonImageTweens()
		buttonImage.Image = "rbxasset://textures/ui/Controls/TouchTapIcon.png"

		-- Hide ButtonText and ButtonTextImage, show ButtonImage
		buttonText.Visible = false
		icon.Visible = false
		buttonImage.Visible = true
	else
		setupButtonImageTweens()

		-- Show ButtonImage
		buttonImage.Visible = true

		local buttonTextString = UserInputService:GetStringForKeyCode(prompt.KeyboardKeyCode)

		local buttonTextImage = KeyboardButtonImage[prompt.KeyboardKeyCode]
		if buttonTextImage == nil then
			buttonTextImage = KeyboardButtonIconMapping[buttonTextString]
		end

		if buttonTextImage == nil then
			local keyCodeMappedText = KeyCodeToTextMapping[prompt.KeyboardKeyCode]
			if keyCodeMappedText then
				buttonTextString = keyCodeMappedText
			end
		end

		if buttonTextImage then
			setupIconTweens()
			icon.Image = buttonTextImage

			--  Hide ButtonText, show ButtonTextImage
			buttonText.Visible = false
			icon.Visible = true
		elseif buttonTextString ~= nil and buttonTextString ~= '' then
			if string.len(buttonTextString) > 2 then
				buttonText.TextSize = math.round(buttonText.TextSize * 6/7)
			end
			setupButtonTextTweens()
			buttonText.Text = buttonTextString

			-- Hide ButtonTextImage, show ButtonText
			icon.Visible = false
			buttonText.Visible = true
		else
			error("ProximityPrompt '" .. prompt.Name .. "' has an unsupported keycode for rendering UI: " .. tostring(prompt.KeyboardKeyCode))
		end
	end

	if inputType == Enum.ProximityPromptInputType.Touch or prompt.ClickablePrompt then
		local button = promptUI.TextButton

		local buttonDown = false

		button.InputBegan:Connect(function(input)
			if (input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1) and
				input.UserInputState ~= Enum.UserInputState.Change then
				prompt:InputHoldBegin()
				buttonDown = true
			end
		end)
		button.InputEnded:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1 then
				if buttonDown then
					buttonDown = false
					prompt:InputHoldEnd()
				end
			end
		end)

		promptUI.Active = true
	end

	if prompt.HoldDuration > 0 then
		local circleBar = resizeableInputFrame.ProgressBar
		setUpCircularProgressBar(circleBar)
		table.insert(tweensForButtonHoldBegin, TweenService:Create(circleBar.Progress, tweenInfoInFullDuration, { Value = 1 }))
		table.insert(tweensForButtonHoldEnd, TweenService:Create(circleBar.Progress, tweenInfoInstant, { Value = 0 }))
	end

	local function cancelShine()
		if shineThread then
			task.cancel(shineThread)
			shineThread = nil
		end
		if shineTween then
			shineTween:Cancel()
			shineGradient.Offset = SHINE_START_OFFSET
		end
	end

	local function cancelPress()
		if pressThread then
			task.cancel(pressThread)
			pressThread = nil
		end
	end

	local function playFadeIn()
		cancelPress()
		bounceScale.Scale = 0
		bounceInTween:Play()
		for _, tween in ipairs(tweensForFadeIn) do
			tween:Play()
		end

		if shineTween then
			cancelShine()
			shineThread = task.delay(SHINE_DELAY, function()
				shineThread = nil
				shineTween:Play()
			end)
		end
	end

	local function playFadeOut()
		cancelShine()
		fadeOutScaleTween:Play()
		for _, tween in ipairs(tweensForFadeOut) do
			tween:Play()
		end
	end

	-- Squash the prompt first and only fade it out once the press has landed
	local function playPress()
		cancelShine()
		cancelPress()
		releasedDuringPress = false
		pressTween:Play()
		pressThread = task.delay(PRESS_INFO.Time, function()
			pressThread = nil
			if releasedDuringPress then
				-- Springs back up from the pressed size, like a button letting go
				bounceInTween:Play()
			else
				playFadeOut()
			end
		end)
	end

	-- A click or quick tap lets go before the press has landed, so finish the press first
	local function playRelease()
		if pressThread then
			releasedDuringPress = true
		else
			playFadeIn()
		end
	end

	-- SFX.ChargeTick plays once when a hold prompt starts being held, and stops when it's let go
	local chargeSound: Sound? = nil

	local function stopChargeTick()
		if chargeSound then
			chargeSound:Stop()
			chargeSound = nil
		end
	end

	local function playChargeTick()
		local sfx = SoundService:FindFirstChild("SFX")
		chargeSound = sfx and sfx:FindFirstChild("ChargeTick") :: Sound?
		if chargeSound then
			chargeSound:Play()
		end
	end

	local holdBeganConnection
	local holdEndedConnection
	local triggeredConnection
	local triggerEndedConnection

	if prompt.HoldDuration > 0 then
		holdBeganConnection = prompt.PromptButtonHoldBegan:Connect(function()
			for _, tween in ipairs(tweensForButtonHoldBegin) do
				tween:Play()
			end
			playChargeTick()
		end)

		holdEndedConnection = prompt.PromptButtonHoldEnded:Connect(function()
			for _, tween in ipairs(tweensForButtonHoldEnd) do
				tween:Play()
			end
			stopChargeTick()
		end)
	end

	triggeredConnection = prompt.Triggered:Connect(playPress)

	triggerEndedConnection = prompt.TriggerEnded:Connect(playRelease)

	local function updateUIFromPrompt()
		-- todo: Use AutomaticSize instead of GetTextSize when that feature becomes available
		local actionTextParams = Instance.new("GetTextBoundsParams")
		actionTextParams.Text = prompt.ActionText
		actionTextParams.RichText = actionText.RichText -- Otherwise tags like <font> count towards the width
		actionTextParams.Font = actionText.FontFace
		actionTextParams.Size = actionText.TextSize
		actionTextParams.Width = 1000
		local actionTextSize = TextService:GetTextBoundsAsync(actionTextParams)

		local objectTextParams = Instance.new("GetTextBoundsParams")
		objectTextParams.Text = prompt.ObjectText
		objectTextParams.Font = objectText.FontFace
		objectTextParams.Size = objectText.TextSize
		objectTextParams.Width = 1000
		local objectTextSize = TextService:GetTextBoundsAsync(objectTextParams)

		local maxTextWidth = math.max(actionTextSize.X, objectTextSize.X)
		-- The template's size is the minimum; only grow wider when the text doesn't fit
		local promptHeight = templateSize.Y.Offset
		local promptWidth = promptHeight
		local textPaddingLeft = 72

		if (prompt.ActionText ~= nil and prompt.ActionText ~= '') or
			(prompt.ObjectText ~= nil and prompt.ObjectText ~= '') then
			promptWidth = math.max(templateSize.X.Offset, maxTextWidth + textPaddingLeft + 24)
		end

		local actionTextYOffset = 0
		if prompt.ObjectText ~= nil and prompt.ObjectText ~= '' then
			actionTextYOffset = 9
		end
		actionText.Position = UDim2.new(0.5, textPaddingLeft - promptWidth/2, 0, actionTextYOffset)
		gradientText.Position = actionText.Position
		objectText.Position = UDim2.new(0.5, textPaddingLeft - promptWidth/2, 0, -10)

		-- The action text itself is set by updateActionText
		objectText.Text = prompt.ObjectText
		for _, label in { actionText, gradientText } do
			label.AutoLocalize = prompt.AutoLocalize
			label.RootLocalizationTable = prompt.RootLocalizationTable
		end

		objectText.AutoLocalize = prompt.AutoLocalize
		objectText.RootLocalizationTable = prompt.RootLocalizationTable

		promptUI.Size = UDim2.fromOffset(promptWidth, promptHeight)
		promptUI.SizeOffset = Vector2.new(prompt.UIOffset.X / promptUI.Size.Width.Offset, prompt.UIOffset.Y / promptUI.Size.Height.Offset)
	end

	local function getStringAttribute(name: string): string?
		local value = prompt:GetAttribute(name)
		return if typeof(value) == "string" and value ~= "" then value else nil
	end

	-- Prompts can recolor their action text with a ProximityTextGradient attribute (the name of a
	-- UIGradient in ReplicatedStorage.Gradients) or a ProximityTextColor attribute. The gradient wins,
	-- unless a ProximityGradientText attribute names the part of the text it covers; the rest then keeps
	-- the color. With neither the template's color is kept
	local function updateActionText()
		local text = prompt.ActionText
		local color = prompt:GetAttribute("ProximityTextColor")
		if typeof(color) ~= "Color3" then
			color = defaultActionTextColor
		end
		local gradientName = getStringAttribute("ProximityTextGradient")
		local gradientPart = getStringAttribute("ProximityGradientText")
		local first, last = nil, nil
		if gradientPart then
			first, last = string.find(text, gradientPart, 1, true)
		end

		if first and last then
			-- Both labels hold the whole text so the characters line up. The gradient label hides the
			-- rest, and the action text draws the gradient's part in its stroke color under it, so the
			-- stroke goes around the whole text and the gradient's edges blend into it
			local function hide(part: string): string
				return if part == "" then "" else `<font transparency="1">{part}</font>`
			end
			local strokeColor = if actionTextStroke then actionTextStroke.Color else Color3.new()
			local before, after = string.sub(text, 1, first - 1), string.sub(text, last + 1)
			ApplyGradient(actionText, nil)
			actionText.Text = before .. `<font color="#{strokeColor:ToHex()}">{gradientPart}</font>` .. after
			actionText.TextColor3 = color
			gradientText.Text = hide(before) .. (gradientPart :: string) .. hide(after)
			-- The gradient multiplies the text color, so white shows it as designed
			gradientText.TextColor3 = if ApplyGradient(gradientText, gradientName) then Color3.new(1, 1, 1) else color
		else
			ApplyGradient(gradientText, nil)
			gradientText.Text = ""
			actionText.Text = text
			actionText.TextColor3 = if ApplyGradient(actionText, gradientName) then Color3.new(1, 1, 1) else color
		end
	end

	local changedConnection = prompt.Changed:Connect(function()
		updateUIFromPrompt()
		updateActionText()
	end)
	local textColorConnection = prompt:GetAttributeChangedSignal("ProximityTextColor"):Connect(updateActionText)
	local textGradientConnection = prompt:GetAttributeChangedSignal("ProximityTextGradient"):Connect(updateActionText)
	local gradientPartConnection = prompt:GetAttributeChangedSignal("ProximityGradientText"):Connect(updateActionText)
	updateUIFromPrompt()
	updateActionText()

	promptUI.Adornee = prompt.Parent
	promptUI.Parent = gui

	playFadeIn()

	local function cleanup()
		if holdBeganConnection then
			holdBeganConnection:Disconnect()
		end

		if holdEndedConnection then
			holdEndedConnection:Disconnect()
		end

		stopChargeTick()
		triggeredConnection:Disconnect()
		triggerEndedConnection:Disconnect()
		changedConnection:Disconnect()
		textColorConnection:Disconnect()
		textGradientConnection:Disconnect()
		gradientPartConnection:Disconnect()

		-- The roll prompt hides the moment it's triggered, so let its press land before fading
		if pressThread then
			cancelPress()
			task.wait(PRESS_INFO.Time)
		end

		playFadeOut()

		task.wait(FADE_OUT_TIME)

		promptUI.Parent = nil
	end

	return cleanup
end

local function onLoad()
	ProximityPromptService.PromptShown:Connect(function(prompt, inputType)
		if prompt.Style == Enum.ProximityPromptStyle.Default then
			return
		end

		local gui = getScreenGui()

		local cleanupFunction = createPrompt(prompt, inputType, gui)
		local removeHighlight = createHighlight(prompt)

		prompt.PromptHidden:Wait()

		removeHighlight()
		cleanupFunction()
	end)
end

onLoad()
