local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local ApplyGradient = require(ReplicatedStorage.Shared.ApplyGradient)
local FormatMoney = require(ReplicatedStorage.Shared.FormatMoney)
local Items = require(ReplicatedStorage.Shared.Items)
local Places = require(ReplicatedStorage.Shared.Places)

local FloatController = require(script.Parent.FloatController)
local InventoryController = require(script.Parent.InventoryController)
local PromptController = require(script.Parent.PromptController)

local RemoveFromSlot = ReplicatedStorage.Remotes.RemoveFromSlot
local IncomeTick = ReplicatedStorage.Remotes.IncomeTick
local LocalPlayer = Players.LocalPlayer
local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")

local BILLBOARD_NAME = "Stuff_UpgradeDisplay"
local SLOT_ITEM_NAME = "SlotItem"
local PARTICLES_NAME = "Particles" -- Folder in the slot part with the emitters that burst on placing

-- "+ $X" popups over each earning slot, copied from the Cash BillboardGui in its slot part (with an
-- Amount TextLabel). They start at its StudsOffset and float up while fading out
local POPUP_NAME = "Cash"
local POPUP_RISE = 4 -- Studs a popup floats up over its life
local POPUP_RISE_INFO = TweenInfo.new(1, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
-- Fully faded as the rise ends, when the popup is removed
local POPUP_FADE_INFO = TweenInfo.new(1, Enum.EasingStyle.Linear)

local slotPlaces: { [Model]: Folder } = {} -- Every slot seen so far -> its place
local billboards: { [Model]: BillboardGui } = {} -- Slot -> the copy of its billboard in PlayerGui

local SlotController = {}

-- The slot whose slot part holds this instance, if any. Parts stream in and out, so slots are
-- picked up from what arrives in their slot part
local function getSlot(instance: Instance): Model?
	local slotPart = instance.Parent
	local slot = slotPart and slotPart.Parent
	if slotPart and slotPart.Name == Places.SLOT_PART and slot and Places.IsSlot(slot) then
		return slot :: Model
	end
	return nil
end

-- What the server put in the slot, for everyone to see
local function getItem(slot: Model): Items.Item?
	local id = slot:GetAttribute("ItemId")
	return if typeof(id) == "string" then Items[id] else nil
end

local function showStats(billboard: BillboardGui, item: Items.Item)
	local main = (billboard :: any).Main
	local stats = main.Stats
	-- FindFirstChild because stats.Name is the Name property, not the label
	local nameLabel = stats:FindFirstChild("Name") :: TextLabel
	local rarityLabel = stats.Rarity :: TextLabel

	main.Icon.Image = `rbxassetid://{item.Icon}`
	nameLabel.Text = item.Name
	rarityLabel.Text = item.Rarity
	-- Tinted by the rarity's gradient (named after it), which needs white text underneath
	rarityLabel.TextColor3 = Color3.new(1, 1, 1)
	ApplyGradient(rarityLabel, item.Rarity)
	stats.Cash.Text = `{FormatMoney(item.MoneyPerSecond)}/s`
end

local function refresh(slot: Model)
	local place = slotPlaces[slot]
	local item = getItem(slot)

	local billboard = billboards[slot]
	if billboard then
		local buttons = (billboard :: any).Main.Buttons :: Frame
		billboard.Enabled = item ~= nil
		if item then
			showStats(billboard, item)
		end
		-- Everyone sees what's in a slot; only the owner gets its buttons
		buttons.Visible = place:GetAttribute("OwnerUserId") == LocalPlayer.UserId
	end

	local slotPart = slot:FindFirstChild(Places.SLOT_PART)
	local prompt = slotPart and slotPart:FindFirstChildOfClass("ProximityPrompt")
	if prompt then
		local held = InventoryController.GetEquippedItem()
		-- The text is set while the prompt is still hidden, since the prompt UI only reads it when shown
		if held then
			prompt.ActionText = `Place {held.Name}`
			prompt:SetAttribute("ProximityTextGradient", held.Rarity)
			prompt:SetAttribute("ProximityGradientText", held.Name)
		end
		-- Only up while the player holds an item and the slot is free
		PromptController.SetHidden(place, prompt, item ~= nil or held == nil)
	end
end

local function refreshAll()
	for slot in slotPlaces do
		refresh(slot)
	end
end

local function watchSlot(place: Folder, slot: Model)
	if slotPlaces[slot] then
		return
	end
	slotPlaces[slot] = place
	slot:GetAttributeChangedSignal("ItemId"):Connect(function()
		refresh(slot)
	end)
end

-- Buttons only take clicks from a billboard under PlayerGui, so each player shows a copy from there,
-- pinned to the slot. The one in the slot is just the design to copy, and stays hidden
local function copyBillboard(slot: Model, original: BillboardGui)
	local old = billboards[slot]
	if old then
		old:Destroy()
	end

	local billboard = original:Clone()
	billboard.Adornee = original.Parent
	billboard.ResetOnSpawn = false
	billboards[slot] = billboard
	original.Enabled = false

	local removeButton = (billboard :: any).Main.Buttons.RemoveButton :: ImageButton
	removeButton.Activated:Connect(function()
		RemoveFromSlot:FireServer(slot)
	end)

	-- The original leaves with its part when that streams out, and the copy goes with it
	original.AncestryChanged:Connect(function()
		if not original:IsDescendantOf(workspace) and billboards[slot] == billboard then
			billboards[slot] = nil
			billboard:Destroy()
		end
	end)

	refresh(slot)
	billboard.Parent = PlayerGui
end

local function getOwnPlace(): Folder?
	for _, place in Places.GetAll() do
		if place:GetAttribute("OwnerUserId") == LocalPlayer.UserId then
			return place
		end
	end
	return nil
end

-- What a popup part fades to, whatever the popup was designed with
local function getFadeGoal(instance: Instance): { [string]: number }?
	if instance:IsA("UIStroke") then
		return { Transparency = 1 }
	elseif not instance:IsA("GuiObject") then
		return nil
	end

	local goal: { [string]: number } = { BackgroundTransparency = 1 }
	if instance:IsA("TextLabel") or instance:IsA("TextButton") or instance:IsA("TextBox") then
		goal.TextTransparency = 1
		goal.TextStrokeTransparency = 1
	elseif instance:IsA("ImageLabel") or instance:IsA("ImageButton") then
		goal.ImageTransparency = 1
	end
	return goal
end

-- Made on this client, so only this player sees what their slots earn
local function showEarned(slot: Model, amount: number)
	local slotPart = slot:FindFirstChild(Places.SLOT_PART)
	local template = slotPart and slotPart:FindFirstChild(POPUP_NAME)
	if not (template and template:IsA("BillboardGui")) then
		return
	end

	local popup = template:Clone()
	local amountLabel = popup:FindFirstChild("Amount", true) :: TextLabel?
	if amountLabel then
		amountLabel.Text = `+ {FormatMoney(amount)}`
	end
	popup.Adornee = slotPart
	popup.ResetOnSpawn = false
	popup.Enabled = true
	popup.Parent = PlayerGui

	local risen = popup.StudsOffset + Vector3.new(0, POPUP_RISE, 0)
	TweenService:Create(popup, POPUP_RISE_INFO, { StudsOffset = risen }):Play()
	for _, descendant in popup:GetDescendants() do
		local goal = getFadeGoal(descendant)
		if goal then
			TweenService:Create(descendant, POPUP_FADE_INFO, goal):Play()
		end
	end
	task.delay(POPUP_RISE_INFO.Time, popup.Destroy, popup)
end

-- One burst from every emitter in the slot's Particles folder, sized by its EmitCount attribute.
-- Emitted on this client only, so nobody else sees it
local function burstParticles(slot: Model)
	local slotPart = slot:FindFirstChild(Places.SLOT_PART)
	local particles = slotPart and slotPart:FindFirstChild(PARTICLES_NAME)
	if not particles then
		return
	end
	for _, emitter in particles:GetDescendants() do
		local count = emitter:GetAttribute("EmitCount")
		if emitter:IsA("ParticleEmitter") and typeof(count) == "number" then
			emitter:Emit(count)
		end
	end
end

local function onDescendantAdded(place: Folder, descendant: Instance)
	if descendant.Name == SLOT_ITEM_NAME and descendant:IsA("BasePart") then
		FloatController.Float(descendant)
		return
	end

	local slot = getSlot(descendant)
	if not slot then
		return
	end
	watchSlot(place, slot)

	if descendant:IsA("BillboardGui") and descendant.Name == BILLBOARD_NAME then
		copyBillboard(slot, descendant)
	elseif descendant:IsA("BillboardGui") and descendant.Name == POPUP_NAME then
		-- Only the design for the popups; left showing, everyone would see it sit in the slot
		descendant.Enabled = false
	elseif descendant:IsA("ProximityPrompt") then
		-- Streamed back in as a fresh prompt that doesn't know it was hidden
		refresh(slot)
	end
end

function SlotController.Start()
	for _, place in Places.GetAll() do
		for _, descendant in place:GetDescendants() do
			onDescendantAdded(place, descendant)
		end
		place.DescendantAdded:Connect(function(descendant)
			onDescendantAdded(place, descendant)
		end)

		place:GetAttributeChangedSignal("OwnerUserId"):Connect(function()
			for slot, slotPlace in slotPlaces do
				if slotPlace == place then
					refresh(slot)
				end
			end
		end)
	end

	-- Picking an item up or putting it away shows or hides the place prompts
	LocalPlayer:GetAttributeChangedSignal("EquippedItem"):Connect(refreshAll)

	-- Bursts the moment the owner places an item, without waiting for the server. Only the owner can
	-- trigger a slot's prompt, and only while it's free, so the server takes the item
	ProximityPromptService.PromptTriggered:Connect(function(prompt)
		local slot = getSlot(prompt)
		if slot then
			burstParticles(slot)
		end
	end)

	-- Sent each second with what every earning slot made, by slot name
	IncomeTick.OnClientEvent:Connect(function(earnings: { [string]: number })
		local place = getOwnPlace()
		if not place then
			return
		end
		for name, amount in earnings do
			local slot = place:FindFirstChild(name)
			if slot and Places.IsSlot(slot) then
				showEarned(slot :: Model, amount)
			end
		end
	end)
end

return SlotController
