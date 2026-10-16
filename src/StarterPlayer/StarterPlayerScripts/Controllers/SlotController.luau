local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ApplyGradient = require(ReplicatedStorage.Shared.ApplyGradient)
local FormatMoney = require(ReplicatedStorage.Shared.FormatMoney)
local Items = require(ReplicatedStorage.Shared.Items)
local Places = require(ReplicatedStorage.Shared.Places)

local FloatController = require(script.Parent.FloatController)
local InventoryController = require(script.Parent.InventoryController)
local PromptController = require(script.Parent.PromptController)

local RemoveFromSlot = ReplicatedStorage.Remotes.RemoveFromSlot
local LocalPlayer = Players.LocalPlayer
local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")

local BILLBOARD_NAME = "Stuff_UpgradeDisplay"
local SLOT_ITEM_NAME = "SlotItem"

local slotPlaces: { [Model]: Folder } = {} -- Every slot seen so far -> its place
local billboards: { [Model]: BillboardGui } = {} -- Slot -> the copy of its billboard in PlayerGui

local SlotController = {}

-- The slot whose Roll_Place holds this instance, if any. Parts stream in and out, so slots are
-- picked up from what arrives in their Roll_Place
local function getSlot(instance: Instance): Model?
	local rollPlace = instance.Parent
	local slot = rollPlace and rollPlace.Parent
	if rollPlace and rollPlace.Name == "Roll_Place" and slot and Places.IsSlot(slot) then
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
	stats.Cash.Text = `{FormatMoney(item.BaseMoneyPerStud)}/stud`
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

	local rollPlace = slot:FindFirstChild("Roll_Place")
	local prompt = rollPlace and rollPlace:FindFirstChildOfClass("ProximityPrompt")
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
end

return SlotController
