local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Items = require(ReplicatedStorage.Shared.Items)
local Places = require(ReplicatedStorage.Shared.Places)
local Rolling = require(ReplicatedStorage.Shared.Rolling)

local InventoryService = require(script.Parent.InventoryService)
local PlaceService = require(script.Parent.PlaceService)
local PlayerDataService = require(script.Parent.PlayerDataService)

local RemoveFromSlot = ReplicatedStorage.Remotes.RemoveFromSlot

local SLOT_ITEM_NAME = "SlotItem"

local SlotService = {}

-- Shows the item in the slot for everyone, or empties it. The ItemId attribute tells clients
-- what's in it for the billboard and the place prompt
local function show(slot: Model, item: Items.Item?)
	local old = slot:FindFirstChild(SLOT_ITEM_NAME)
	if old then
		old:Destroy()
	end
	slot:SetAttribute("ItemId", if item then item.Id else nil)
	if not item then
		return
	end

	local display = Rolling.CreateDisplay(item, (slot :: any).Roll_Place)
	display.Name = SLOT_ITEM_NAME
	display.Parent = slot
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
end

function SlotService.Start()
	for _, place in Places.GetAll() do
		local names = {}
		for _, slot in Places.GetSlots(place) do
			if names[slot.Name] then
				warn(`{place.Name} has more than one {slot.Name}. Slots are saved by name, so give each its own`)
			end
			names[slot.Name] = true

			local prompt = (slot :: any).Roll_Place.ProximityPrompt
			prompt.Triggered:Connect(function(player)
				onPlaceTriggered(place, slot, player)
			end)
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
end

return SlotService
