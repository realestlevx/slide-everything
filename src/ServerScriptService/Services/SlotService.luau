local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Items = require(ReplicatedStorage.Shared.Items)
local Places = require(ReplicatedStorage.Shared.Places)
local Rarities = require(ReplicatedStorage.Shared.Rarities)
local Rolling = require(ReplicatedStorage.Shared.Rolling)

local InventoryService = require(script.Parent.InventoryService)
local PlaceService = require(script.Parent.PlaceService)
local PlayerDataService = require(script.Parent.PlayerDataService)

local RemoveFromSlot = ReplicatedStorage.Remotes.RemoveFromSlot
local IncomeTick = ReplicatedStorage.Remotes.IncomeTick

local SLOT_ITEM_NAME = "SlotItem"
local RARITY_PART_NAME = "Rarity" -- Part in a slot tinted with its item's rarity color

local rarityPartColors: { [BasePart]: Color3 } = {} -- Each Rarity part's own color, for empty slots

local SlotService = {}

local function tintRarityPart(slot: Model, item: Items.Item?)
	local part = slot:FindFirstChild(RARITY_PART_NAME)
	if not (part and part:IsA("BasePart")) then
		return
	end
	local ownColor = rarityPartColors[part] or part.Color
	rarityPartColors[part] = ownColor
	part.Color = if item then Rarities[item.Rarity].Color else ownColor
end

-- Shows the item in the slot for everyone, or empties it. The ItemId attribute tells clients
-- what's in it for the billboard and the place prompt
local function show(slot: Model, item: Items.Item?)
	local old = slot:FindFirstChild(SLOT_ITEM_NAME)
	if old then
		old:Destroy()
	end
	tintRarityPart(slot, item)
	slot:SetAttribute("ItemId", if item then item.Id else nil)
	local slotPart = slot:FindFirstChild(Places.SLOT_PART) :: BasePart?
	if not (item and slotPart) then
		return
	end

	local display = Rolling.CreateDisplay(item, slotPart)
	display.Name = SLOT_ITEM_NAME
	display.Parent = slot
end

-- What each of the player's slots earns per second, by slot name, and all of them together
local function getEarnings(player: Player): ({ [string]: number }, number)
	local data = PlayerDataService.Get(player)
	local earnings, total = {}, 0
	for name, uid in if data then data.Slots else {} do
		local owned = InventoryService.Find(player, uid)
		local item = owned and Items[owned.Id]
		if item then
			earnings[name] = item.MoneyPerSecond
			total += item.MoneyPerSecond
		end
	end
	return earnings, total
end

-- Keeps MoneyPerSecond (shown on the place's owner billboard) in step with the slots
local function updateMoneyPerSecond(player: Player)
	local _, total = getEarnings(player)
	PlayerDataService.SetMoneyPerSecond(player, total)
end

-- Pays out a second's earnings. Only the player's own client hears what each slot made,
-- for its popups
local function payOut(player: Player)
	local earnings, total = getEarnings(player)
	if total > 0 then
		PlayerDataService.AddMoney(player, total)
		IncomeTick:FireClient(player, earnings)
	end
end

local function getOwner(place: Folder): Player?
	local ownerId = place:GetAttribute("OwnerUserId")
	return if typeof(ownerId) == "number" then Players:GetPlayerByUserId(ownerId) else nil
end

-- A slot renamed or removed in Studio would keep its item hidden for good, so that item goes
-- back to the hotbar instead
local function dropMissingSlots(player: Player, place: Folder)
	local data = PlayerDataService.Get(player)
	if not data then
		return
	end

	local names = {}
	for _, slot in Places.GetSlots(place) do
		names[slot.Name] = true
	end

	local dropped = false
	for name, uid in data.Slots do
		if not names[name] or not InventoryService.Find(player, uid) then
			data.Slots[name] = nil
			dropped = true
		end
	end
	if dropped then
		InventoryService.Sync(player)
	end
end

-- Slots show what the place's owner keeps in them. They stay empty while nobody owns the place
-- or the owner's data is still loading
local function refreshPlace(place: Folder)
	local owner = getOwner(place)
	local data = if owner then PlayerDataService.Get(owner) else nil
	if owner and data then
		dropMissingSlots(owner, place)
		updateMoneyPerSecond(owner)
	end

	for _, slot in Places.GetSlots(place) do
		local uid = data and data.Slots[slot.Name]
		local owned = if owner and uid then InventoryService.Find(owner, uid) else nil
		show(slot, owned and Items[owned.Id])
	end
end

-- The owner puts the item in their hands into an empty slot
local function onPlaceTriggered(place: Folder, slot: Model, player: Player)
	local data = PlayerDataService.Get(player)
	local owned = InventoryService.GetEquipped(player)
	local item = owned and Items[owned.Id]
	if place:GetAttribute("OwnerUserId") ~= player.UserId or not (data and owned and item) then
		return
	end
	if data.Slots[slot.Name] then
		return
	end

	data.Slots[slot.Name] = owned.Uid
	InventoryService.Equip(player, nil)
	show(slot, item)
	InventoryService.Sync(player)
	updateMoneyPerSecond(player)
end

-- The slot's Remove button: its item goes back to the hotbar
local function onRemove(player: Player, slot: any)
	local place = PlaceService.GetPlace(player)
	local data = PlayerDataService.Get(player)
	if not (place and data and typeof(slot) == "Instance" and slot.Parent == place and Places.IsSlot(slot)) then
		return
	end
	if not data.Slots[slot.Name] then
		return
	end

	data.Slots[slot.Name] = nil
	show(slot, nil)
	InventoryService.Sync(player)
	updateMoneyPerSecond(player)
end

function SlotService.Start()
	for _, place in Places.GetAll() do
		local names = {}
		for _, slot in Places.GetSlots(place) do
			if names[slot.Name] then
				warn(`{place.Name} has more than one {slot.Name}. Slots are saved by name, so give each its own`)
			end
			names[slot.Name] = true

			-- The prompt lives in the place file, so it can go missing; that slot just can't be filled then
			local slotPart = slot:FindFirstChild(Places.SLOT_PART)
			local prompt = slotPart and slotPart:FindFirstChildOfClass("ProximityPrompt")
			if prompt then
				prompt.Triggered:Connect(function(player)
					onPlaceTriggered(place, slot, player)
				end)
			else
				warn(`{slot:GetFullName()} needs a {Places.SLOT_PART} part with a ProximityPrompt to be filled`)
			end
		end

		refreshPlace(place)
		place:GetAttributeChangedSignal("OwnerUserId"):Connect(function()
			refreshPlace(place)
		end)
	end

	PlayerDataService.Loaded:Connect(function(player)
		local place = PlaceService.GetPlace(player)
		if place then
			refreshPlace(place)
		end
	end)

	RemoveFromSlot.OnServerEvent:Connect(onRemove)

	-- Items in slots pay out once a second
	task.spawn(function()
		while true do
			task.wait(1)
			for _, player in Players:GetPlayers() do
				payOut(player)
			end
		end
	end)
end

return SlotService
