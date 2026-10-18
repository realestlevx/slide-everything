local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")

local FormatMoney = require(ReplicatedStorage.Shared.FormatMoney)
local Places = require(ReplicatedStorage.Shared.Places)
local SignUpgrades = require(ReplicatedStorage.Shared.SignUpgrades)

local ButtonController = require(script.Parent.ButtonController)

local BuySlot = ReplicatedStorage.Remotes.BuySlot
local BuySlotResult = ReplicatedStorage.Remotes.BuySlotResult
local BuyUpgrade = ReplicatedStorage.Remotes.BuyUpgrade
local BuyUpgradeResult = ReplicatedStorage.Remotes.BuyUpgradeResult
local LocalPlayer = Players.LocalPlayer
local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")

-- Each panel on a sign is a Frame with a button (its price on the button's TextLabel) and a
-- Value_Increase label ("1 > 2"). The Increase Slots panel is its own thing; the rest are the
-- level upgrades in SignUpgrades, found by their Frame
local SLOTS_PANEL = "Slots"
local SLOTS_FRAME_NAME = "Slots_Frame"
local VALUE_LABEL_NAME = "Value_Increase"
local ICON_NAMES = { "Icon", "ImageLabel" } -- The panel's picture, which grows and presses with its button
local MAX_TEXT = "MAX" -- On the button once there's nothing left to buy

local PRICE_ERROR_COLOR = Color3.fromRGB(255, 50, 50)
local PRICE_FLASH = TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.In) -- Fades the red back out

type Panel = {
	Price: TextLabel?,
	Value: TextLabel?,
}

type Sign = {
	Place: Folder,
	Gui: SurfaceGui, -- This player's copy, in PlayerGui
	Panels: { [string]: Panel }, -- SLOTS_PANEL or an upgrade's name -> its labels
}

local signs: { [SurfaceGui]: Sign } = {} -- The sign's own SurfaceGui -> its copy
local priceColors: { [TextLabel]: Color3 } = {} -- Each price label's own color, taken before it first flashes

local SignController = {}

-- Panel name -> the Frame it's shown in
local panelFrames: { [string]: string } = { [SLOTS_PANEL] = SLOTS_FRAME_NAME }
for name, upgrade in SignUpgrades.Upgrades do
	panelFrames[name] = upgrade.Frame
end

local function show(panel: Panel, value: string, price: number?)
	if panel.Value then
		panel.Value.Text = value
	end
	if panel.Price then
		panel.Price.Text = if price then FormatMoney(price) else MAX_TEXT
	end
end

-- From the place's attributes, which the server keeps up to date for its owner
local function refreshPanel(place: Folder, name: string, panel: Panel)
	if name == SLOTS_PANEL then
		local unlocked = place:GetAttribute("SlotsUnlocked")
		local price = place:GetAttribute("NextSlotPrice")
		if typeof(unlocked) == "number" then
			local nextPrice = if typeof(price) == "number" then price else nil
			show(panel, if nextPrice then `{unlocked} > {unlocked + 1}` else `{unlocked}`, nextPrice)
		end
		return
	end

	local level = place:GetAttribute(`{name}Level`)
	if typeof(level) ~= "number" then
		return
	end
	local suffix = SignUpgrades.Upgrades[name].Suffix
	local value = SignUpgrades.GetValue(name, level)
	local nextValue = SignUpgrades.GetNextValue(name, level)
	local text = if nextValue then `{value}{suffix} > {nextValue}{suffix}` else `{value}{suffix}`
	show(panel, text, SignUpgrades.GetNextPrice(name, level))
end

local function refreshPlace(place: Folder)
	for _, sign in signs do
		if sign.Place == place then
			for name, panel in sign.Panels do
				refreshPanel(place, name, panel)
			end
		end
	end
end

local function buy(place: Folder, name: string)
	if name == SLOTS_PANEL then
		BuySlot:FireServer(place)
	else
		BuyUpgrade:FireServer(place, name)
	end
end

local function hasPanel(gui: SurfaceGui): boolean
	for _, frameName in panelFrames do
		if gui:FindFirstChild(frameName, true) then
			return true
		end
	end
	return false
end

-- Buttons only take clicks from a SurfaceGui under PlayerGui, so each player shows a copy from there,
-- on the sign's part. The one on the sign is just the design to copy, and stays hidden
local function copySign(place: Folder, original: SurfaceGui)
	local old = signs[original]
	if old then
		old.Gui:Destroy()
	end

	local gui = original:Clone()
	gui.Adornee = original.Parent
	gui.ResetOnSpawn = false
	original.Enabled = false

	local sign: Sign = { Place = place, Gui = gui, Panels = {} }
	for name, frameName in panelFrames do
		local frame = gui:FindFirstChild(frameName, true)
		if not frame then
			continue
		end
		local button = frame:FindFirstChildWhichIsA("GuiButton")
		local value = frame:FindFirstChild(VALUE_LABEL_NAME)
		sign.Panels[name] = {
			Price = button and button:FindFirstChildOfClass("TextLabel"),
			Value = if value and value:IsA("TextLabel") then value else nil,
		}

		if button then
			button.Activated:Connect(function()
				-- Everyone sees each place's signs, but only its owner can buy from them
				if place:GetAttribute("OwnerUserId") == LocalPlayer.UserId then
					buy(place, name)
				end
			end)

			local icon
			for _, iconName in ICON_NAMES do
				local found = frame:FindFirstChild(iconName)
				if found and found:IsA("GuiObject") then
					icon = found
					break
				end
			end
			ButtonController.Animate(button, if icon then { icon } else nil)
		end
		refreshPanel(place, name, sign.Panels[name])
	end
	signs[original] = sign

	-- The original leaves with its part when that streams out, and the copy goes with it
	original.AncestryChanged:Connect(function()
		if not original:IsDescendantOf(workspace) and signs[original] == sign then
			signs[original] = nil
			gui:Destroy()
		end
	end)

	gui.Parent = PlayerGui
end

local function onDescendantAdded(place: Folder, descendant: Instance)
	if descendant:IsA("SurfaceGui") and hasPanel(descendant) then
		copySign(place, descendant)
	end
end

-- Played from the client, so only this player hears them
local function playSound(name: string) -- Sound under SoundService.SFX
	local sfx = SoundService:FindFirstChild("SFX")
	local sound = sfx and sfx:FindFirstChild(name)
	if sound and sound:IsA("Sound") then
		sound:Play()
	end
end

-- Bought: the buy sound. Too expensive: the error sound, and the panel's price on the player's own
-- signs flashes red and fades back to its own color
local function onResult(name: string, bought: boolean)
	if bought then
		playSound("Buy")
		return
	end

	playSound("Error")
	for _, sign in signs do
		local panel = sign.Panels[name]
		local price = panel and panel.Price
		if price and sign.Place:GetAttribute("OwnerUserId") == LocalPlayer.UserId then
			local color = priceColors[price] or price.TextColor3
			priceColors[price] = color
			-- Starting a new tween on TextColor3 cancels a flash that's still fading
			price.TextColor3 = PRICE_ERROR_COLOR
			TweenService:Create(price, PRICE_FLASH, { TextColor3 = color }):Play()
		end
	end
end

function SignController.Start()
	local attributes = { "SlotsUnlocked", "NextSlotPrice" }
	for name in SignUpgrades.Upgrades do
		table.insert(attributes, `{name}Level`)
	end

	for _, place in Places.GetAll() do
		for _, descendant in place:GetDescendants() do
			onDescendantAdded(place, descendant)
		end
		place.DescendantAdded:Connect(function(descendant)
			onDescendantAdded(place, descendant)
		end)

		for _, attribute in attributes do
			place:GetAttributeChangedSignal(attribute):Connect(function()
				refreshPlace(place)
			end)
		end
	end

	BuySlotResult.OnClientEvent:Connect(function(bought: boolean)
		onResult(SLOTS_PANEL, bought)
	end)
	BuyUpgradeResult.OnClientEvent:Connect(onResult)
end

return SignController
