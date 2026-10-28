local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")

local FormatMoney = require(ReplicatedStorage.Shared.FormatMoney)
local LocalHide = require(ReplicatedStorage.Shared.LocalHide)
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

-- While the player has the cash for something on one of their own signs, the whole sign is highlighted.
-- It fades in and out instead of popping
local HIGHLIGHT_COLOR = Color3.new(1, 1, 1)
local HIGHLIGHT_FILL_TRANSPARENCY = 0.9
local HIGHLIGHT_OUTLINE_TRANSPARENCY = 0
local HIGHLIGHT_FADE = TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

-- Only a place's owner sees its signs. On everyone else's screen the copies of its panels are off,
-- and everything in the place's Signs folder is hidden: the boards, their lights and any other guis
local SIGNS_FOLDER_NAME = "Signs"

type Panel = {
	Button: GuiButton?,
	Price: TextLabel?,
	Value: TextLabel?,
	NextPrice: number?, -- What its button buys the next one for. Nil at MAX, or before the place's attributes are in
}

type Sign = {
	Place: Folder,
	Gui: SurfaceGui, -- This player's copy, in PlayerGui
	Highlight: Highlight, -- Made on this client, in the sign's model
	Lit: boolean, -- Whether the highlight is on, or fading in
	Panels: { [string]: Panel }, -- SLOTS_PANEL or an upgrade's name -> its labels
}

local signs: { [SurfaceGui]: Sign } = {} -- The sign's own SurfaceGui -> its copy
local priceColors: { [TextLabel]: Color3 } = {} -- Each price label's own color, taken before it first flashes
local lastClicks: { [string]: number } = {} -- Panel name -> when its button last took a click, on any sign

local SignController = {}

-- Panel name -> the Frame it's shown in
local panelFrames: { [string]: string } = { [SLOTS_PANEL] = SLOTS_FRAME_NAME }
for name, upgrade in SignUpgrades.Upgrades do
	panelFrames[name] = upgrade.Frame
end

local function isOwner(place: Folder): boolean
	return place:GetAttribute("OwnerUserId") == LocalPlayer.UserId
end

local function hasPanel(gui: SurfaceGui): boolean
	for _, frameName in panelFrames do
		if gui:FindFirstChild(frameName, true) then
			return true
		end
	end
	return false
end

-- Panel guis are left out: their copies are turned off instead, and the originals stay off for
-- good (see copySign)
local function setHidden(instance: Instance, hide: boolean)
	if not (instance:IsA("SurfaceGui") and hasPanel(instance)) then
		LocalHide.Set(instance, hide)
	end
end

local function isOnSign(place: Folder, instance: Instance): boolean
	local folder = place:FindFirstChild(SIGNS_FOLDER_NAME)
	return folder ~= nil and instance:IsDescendantOf(folder)
end

-- The whole sign a panel gui is on: its model in the place's Signs folder, or just the gui's part
-- if it isn't in one
local function getBoard(place: Folder, original: SurfaceGui): Instance?
	local folder = place:FindFirstChild(SIGNS_FOLDER_NAME)
	local current = original.Parent
	while folder and current and current.Parent ~= folder do
		current = current.Parent
	end
	return current or original.Parent
end

-- Fades the sign's highlight in or out. It's turned off once it's faded out, so it doesn't count
-- towards the highlights Roblox will draw at once. A new fade cancels one that's still going
local function setLit(sign: Sign, lit: boolean)
	if sign.Lit == lit then
		return
	end
	sign.Lit = lit
	local highlight = sign.Highlight
	highlight.Enabled = true
	local tween = TweenService:Create(highlight, HIGHLIGHT_FADE, {
		FillTransparency = if lit then HIGHLIGHT_FILL_TRANSPARENCY else 1,
		OutlineTransparency = if lit then HIGHLIGHT_OUTLINE_TRANSPARENCY else 1,
	})
	tween.Completed:Connect(function(state)
		if state == Enum.PlaybackState.Completed and not sign.Lit then
			highlight.Enabled = false
		end
	end)
	tween:Play()
end

-- On while the place is this player's and their cash covers the next price of any panel on the sign
local function refreshHighlight(sign: Sign)
	local money = LocalPlayer:GetAttribute("Money")
	local affordable = false
	if typeof(money) == "number" and isOwner(sign.Place) then
		for _, panel in sign.Panels do
			if panel.NextPrice and money >= panel.NextPrice then
				affordable = true
				break
			end
		end
	end
	setLit(sign, affordable)
end

-- When the place changes hands, its signs show or hide for this player to match
local function refreshOwner(place: Folder)
	local owned = isOwner(place)
	local folder = place:FindFirstChild(SIGNS_FOLDER_NAME)
	if folder then
		for _, descendant in folder:GetDescendants() do
			setHidden(descendant, not owned)
		end
	end
	for _, sign in signs do
		if sign.Place == place then
			sign.Gui.Enabled = owned
			refreshHighlight(sign)
		end
	end
end

local function show(panel: Panel, value: string, price: number?)
	panel.NextPrice = price
	if panel.Value then
		panel.Value.Text = value
	end
	if panel.Price then
		-- Two decimals, so prices like $1.35K show in full
		panel.Price.Text = if price then FormatMoney(price, 2) else MAX_TEXT
	end
end

-- From the place's attributes, which the server keeps up to date for its owner
local function refreshPanel(place: Folder, name: string, panel: Panel)
	if name == SLOTS_PANEL then
		local unlocked = place:GetAttribute("SlotsUnlocked")
		local price = place:GetAttribute("NextSlotPrice")
		-- Set instead once every slot is bought, while there's another floor to buy
		local nextFloor = place:GetAttribute("NextFloor")
		if typeof(unlocked) == "number" then
			local nextPrice = if typeof(price) == "number" then price else nil
			local value = if typeof(nextFloor) == "number"
				then `Floor {nextFloor}`
				elseif nextPrice then `{unlocked} > {unlocked + 1}`
				else `{unlocked}`
			show(panel, value, nextPrice)
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
			refreshHighlight(sign)
		end
	end
end

local function buy(place: Folder, name: string)
	-- Upgrades with a cooldown ignore clicks until it's over
	local upgrade = SignUpgrades.Upgrades[name]
	local cooldown = upgrade and upgrade.Cooldown
	local now = os.clock()
	if cooldown and now - (lastClicks[name] or -math.huge) < cooldown then
		return
	end
	lastClicks[name] = now

	if name == SLOTS_PANEL then
		BuySlot:FireServer(place)
	else
		BuyUpgrade:FireServer(place, name)
	end
end

-- Buttons only take clicks from a SurfaceGui under PlayerGui, so each player shows a copy from there,
-- on the sign's part. The one on the sign is just the design to copy, and stays hidden. The copy is
-- only on for the place's owner
local function copySign(place: Folder, original: SurfaceGui)
	local old = signs[original]
	if old then
		old.Gui:Destroy()
		old.Highlight:Destroy()
	end

	local gui = original:Clone()
	gui.Adornee = original.Parent
	gui.ResetOnSpawn = false
	gui.Enabled = isOwner(place)
	original.Enabled = false

	-- Occluded, so it doesn't show through the floors and walls between the player and the sign. It
	-- starts faded out and off
	local highlight = Instance.new("Highlight")
	highlight.Name = "AffordHighlight"
	highlight.DepthMode = Enum.HighlightDepthMode.Occluded
	highlight.FillColor = HIGHLIGHT_COLOR
	highlight.FillTransparency = 1
	highlight.OutlineColor = HIGHLIGHT_COLOR
	highlight.OutlineTransparency = 1
	highlight.Enabled = false

	local sign: Sign = { Place = place, Gui = gui, Highlight = highlight, Lit = false, Panels = {} }
	for name, frameName in panelFrames do
		local frame = gui:FindFirstChild(frameName, true)
		if not frame then
			continue
		end
		local button = frame:FindFirstChildWhichIsA("GuiButton")
		local value = frame:FindFirstChild(VALUE_LABEL_NAME)
		sign.Panels[name] = {
			Button = button,
			Price = button and button:FindFirstChildOfClass("TextLabel"),
			Value = if value and value:IsA("TextLabel") then value else nil,
		}

		if button then
			button.Activated:Connect(function()
				if isOwner(place) then
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

	-- The original leaves with its part when that streams out, and the copy and highlight go with it
	original.AncestryChanged:Connect(function()
		if not original:IsDescendantOf(workspace) and signs[original] == sign then
			signs[original] = nil
			gui:Destroy()
			highlight:Destroy()
		end
	end)

	gui.Parent = PlayerGui
	highlight.Parent = getBoard(place, original)
	refreshHighlight(sign)
end

-- Signs stream in a part at a time, and each part is hidden as it arrives if the sign isn't this player's
local function onDescendantAdded(place: Folder, descendant: Instance)
	if descendant:IsA("SurfaceGui") and hasPanel(descendant) then
		copySign(place, descendant)
	end
	if not isOwner(place) and isOnSign(place, descendant) then
		setHidden(descendant, true)
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

-- Bought: the buy sound, and the panel's button on the player's own signs pulses. Too expensive: the
-- error sound, and the panel's price on the player's own signs flashes red and fades back to its own color
local function onResult(name: string, bought: boolean)
	if bought then
		playSound("Buy")
		for _, sign in signs do
			local panel = sign.Panels[name]
			if panel and panel.Button and isOwner(sign.Place) then
				ButtonController.Pulse(panel.Button)
			end
		end
		return
	end

	playSound("Error")
	for _, sign in signs do
		local panel = sign.Panels[name]
		local price = panel and panel.Price
		if price and isOwner(sign.Place) then
			local color = priceColors[price] or price.TextColor3
			priceColors[price] = color
			-- Starting a new tween on TextColor3 cancels a flash that's still fading
			price.TextColor3 = PRICE_ERROR_COLOR
			TweenService:Create(price, PRICE_FLASH, { TextColor3 = color }):Play()
		end
	end
end

function SignController.Start()
	local attributes = { "SlotsUnlocked", "NextSlotPrice", "NextFloor" }
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
		place:GetAttributeChangedSignal("OwnerUserId"):Connect(function()
			refreshOwner(place)
		end)
	end

	LocalPlayer:GetAttributeChangedSignal("Money"):Connect(function()
		for _, sign in signs do
			refreshHighlight(sign)
		end
	end)

	BuySlotResult.OnClientEvent:Connect(function(bought: boolean)
		onResult(SLOTS_PANEL, bought)
	end)
	BuyUpgradeResult.OnClientEvent:Connect(onResult)
end

return SignController
