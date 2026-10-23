local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local Floors = require(ReplicatedStorage.Shared.Floors)
local GamePasses = require(ReplicatedStorage.Shared.GamePasses)
local Items = require(ReplicatedStorage.Shared.Items)
local Places = require(ReplicatedStorage.Shared.Places)
local Rarities = require(ReplicatedStorage.Shared.Rarities)
local Rolling = require(ReplicatedStorage.Shared.Rolling)
local Upgrades = require(ReplicatedStorage.Shared.Upgrades)

local FloorService = require(script.Parent.FloorService)
local InventoryService = require(script.Parent.InventoryService)
local PlaceService = require(script.Parent.PlaceService)
local PlayerDataService = require(script.Parent.PlayerDataService)

local RemoveFromSlot = ReplicatedStorage.Remotes.RemoveFromSlot
local IncomeTick = ReplicatedStorage.Remotes.IncomeTick
local UpgradeSlot = ReplicatedStorage.Remotes.UpgradeSlot
local UpgradeResult = ReplicatedStorage.Remotes.UpgradeResult
local BuySlot = ReplicatedStorage.Remotes.BuySlot
local BuySlotResult = ReplicatedStorage.Remotes.BuySlotResult

local SLOT_ITEM_NAME = "SlotItem"
local RARITY_PART_NAME = "Rarity" -- Part in a slot tinted with its item's rarity color
local SLOT_TEMPLATE_NAME = "Slot" -- Model in ServerStorage every slot is copied from
local PASS_SLOT_TEMPLATE_NAME = "Paid_Slot" -- Model in ServerStorage that pass slots are copied from instead
-- Invisible parts anywhere in a place marking where its slots go. Each stands in for its slot's
-- Slot_Place and carries the slot's SlotNumber and Price attributes
local SLOT_POSITION_NAME = "Slot_Position"
-- A later floor's markers are in a folder named after it, like Floor2_Slot_Positions; any others are
-- on floor 1
local FLOOR_FOLDER_PATTERN = "^Floor(%d+)_Slot_Positions$"
-- On a slot that comes with the GamePasses.PaidSlots pass instead of a price: there for everyone to
-- see from the start, and usable once the place's owner has the pass
local GAME_PASS_ATTRIBUTE = "GamePass"
-- Billboards in a slot that are only designs: each client copies them (the stats and buttons, and
-- the "+ $" popups) and shows its copies, so the slot's own stay hidden, even in the server's view
local DESIGN_BILLBOARDS = { "Stuff_UpgradeDisplay", "Cash" }
local PLACE_COUNT_ATTRIBUTE = "PlaceCount" -- On a slot: how many times an item was put in it by hand

local rarityPartColors: { [BasePart]: Color3 } = {} -- Each Rarity part's own color, for empty slots
local partTransparencies: { [BasePart]: number } = {} -- Each slot part's own transparency, for once it's bought
local passOwners: { [Player]: boolean } = {} -- Players who own the paid slots pass

local SlotService = {}

-- A slot template in ServerStorage, with where its pivot sits from its Slot_Place, so each copy's
-- Slot_Place lands on its marker. Warns and gives nil without one
local function getTemplate(name: string): (Model?, CFrame)
	local template = ServerStorage:FindFirstChild(name)
	local templatePart = template and template:FindFirstChild(Places.SLOT_PART)
	if not (template and template:IsA("Model") and templatePart and templatePart:IsA("BasePart")) then
		warn(`ServerStorage needs a {name} model with a {Places.SLOT_PART} part for its slots to be placed`)
		return nil, CFrame.identity
	end
	return template, templatePart.CFrame:ToObjectSpace(template:GetPivot())
end

local function getMarkerFloor(marker: BasePart): number
	local folder = marker.Parent
	local number = folder and folder.Name:match(FLOOR_FOLDER_PATTERN)
	return if number then tonumber(number) :: number else 1
end

-- Puts a copy of the slot template on each of the place's Slot_Position parts, with the part's
-- attributes and the floor it's on; pass slots get the pass slot template. The part goes once its
-- slot is there
local function spawnSlots(place: Folder)
	local slotTemplate, slotOffset = getTemplate(SLOT_TEMPLATE_NAME)
	local passTemplate, passOffset = getTemplate(PASS_SLOT_TEMPLATE_NAME)

	for _, marker in place:GetDescendants() do
		if not (marker:IsA("BasePart") and marker.Name == SLOT_POSITION_NAME) then
			continue
		end
		local number = marker:GetAttribute("SlotNumber")
		if typeof(number) ~= "number" then
			warn(`{marker:GetFullName()} needs a SlotNumber attribute to get a slot`)
			continue
		end
		local isPass = marker:GetAttribute(GAME_PASS_ATTRIBUTE) == true
		local template = if isPass then passTemplate else slotTemplate
		local pivotOffset = if isPass then passOffset else slotOffset
		if not template then
			continue
		end

		local floor = getMarkerFloor(marker)
		local slot = template:Clone()
		slot.Name = if floor > 1 then `Floor{floor}_Slot_{number}` else `Slot_{number}`
		for name, value in marker:GetAttributes() do
			slot:SetAttribute(name, value)
		end
		slot:SetAttribute("Floor", floor)
		-- A later floor's markers carry floor 1's prices, which go up from there (see Floors)
		local price = marker:GetAttribute("Price")
		if typeof(price) == "number" then
			slot:SetAttribute("Price", math.round(price * Floors.GetSlotPriceMultiplier(floor)))
		end
		for _, billboardName in DESIGN_BILLBOARDS do
			local billboard = slot:FindFirstChild(billboardName, true)
			if billboard and billboard:IsA("BillboardGui") then
				billboard.Enabled = false
			end
		end
		slot:PivotTo(marker.CFrame * pivotOffset)
		slot.Parent = place
		marker:Destroy()
	end
end

local function tintRarityPart(slot: Model, item: Items.Item?)
	local part = slot:FindFirstChild(RARITY_PART_NAME)
	if not (part and part:IsA("BasePart")) then
		return
	end
	local ownColor = rarityPartColors[part] or part.Color
	rarityPartColors[part] = ownColor
	part.Color = if item then Rarities[item.Rarity].Color else ownColor
end

-- Shows the item in the slot for everyone, or empties it. The ItemId and ItemLevel attributes tell
-- clients what's in it for the billboard and the place prompt
local function show(slot: Model, owned: Items.OwnedItem?)
	local item = owned and Items[owned.Id]
	local old = slot:FindFirstChild(SLOT_ITEM_NAME)
	if old then
		old:Destroy()
	end
	tintRarityPart(slot, item)
	slot:SetAttribute("ItemId", if item then item.Id else nil)
	slot:SetAttribute("ItemLevel", if owned and item then Upgrades.GetLevel(owned) else nil)
	local slotPart = slot:FindFirstChild(Places.SLOT_PART) :: BasePart?
	if not (item and slotPart) then
		return
	end

	-- At the item's own size: every client grows it to its level's (see SlotController)
	local display = Rolling.CreateDisplay(item, slotPart)
	display.Name = SLOT_ITEM_NAME
	display.Parent = slot
end

local function isPassSlot(slot: Model): boolean
	return slot:GetAttribute(GAME_PASS_ATTRIBUTE) == true
end

-- Whether the place's owner has the floor the slot is on. Only floor 1 while nobody owns it
local function isOnBuiltFloor(data: PlayerDataService.Data?, slot: Model): boolean
	return Places.GetSlotFloor(slot) <= (if data then data.Floors else 1)
end

-- Nothing on a floor the owner doesn't have is there. On the floors they have, free slots are always
-- there, pass slots once the owner has the pass, and the rest once bought from the sign
local function isUnlocked(owner: Player?, data: PlayerDataService.Data?, slot: Model): boolean
	if not isOnBuiltFloor(data, slot) then
		return false
	elseif isPassSlot(slot) then
		return owner ~= nil and passOwners[owner] == true
	end
	return Places.GetSlotPrice(slot) <= 0 or (data ~= nil and data.BoughtSlots[Places.GetSlotKey(slot)] == true)
end

-- A slot that isn't bought yet isn't there: hidden for everyone. Pass slots are there as soon as
-- their floor is, to show what the pass gets. The Unlocked attribute tells clients what its place
-- prompt is for, and the sign which slot is next
local function setUnlocked(slot: Model, data: PlayerDataService.Data?, unlocked: boolean)
	slot:SetAttribute("Unlocked", unlocked)
	local shown = unlocked or (isPassSlot(slot) and isOnBuiltFloor(data, slot))
	for _, part in slot:GetDescendants() do
		if part:IsA("BasePart") and part.Name ~= SLOT_ITEM_NAME and not part:FindFirstAncestor(SLOT_ITEM_NAME) then
			local ownTransparency = partTransparencies[part] or part.Transparency
			partTransparencies[part] = ownTransparency
			part.Transparency = if shown then ownTransparency else 1
		end
	end
end

-- The next slot up for sale: the first, floor by floor in SlotNumber order, that isn't free or bought
-- yet, on a floor the player has. Pass slots aren't sold on the sign
local function getNextSlot(place: Folder, data: PlayerDataService.Data): Model?
	for _, slot in Places.GetSlots(place) do
		if not isPassSlot(slot) and isOnBuiltFloor(data, slot) and not isUnlocked(nil, data, slot) then
			return slot
		end
	end
	return nil
end

-- The floor the sign sells once every slot on the player's floors is bought, and its price. Nil
-- while there are slots left, or once there are no more floors
local function getNextFloor(place: Folder, data: PlayerDataService.Data): (number?, number?)
	if getNextSlot(place, data) then
		return nil, nil
	end
	local number = data.Floors + 1
	local price = FloorService.GetPrice(place, number)
	return if price then number else nil, price
end

-- What the place's Increase Slots sign shows, as attributes on the place: slots are streamed, so
-- clients can't always count them. NextSlotPrice is what the next slot costs, or the next floor once
-- every slot is bought (NextFloor says which), and nil once there's nothing left. Pass slots don't
-- count, as the sign doesn't sell them
local function updateSign(place: Folder, data: PlayerDataService.Data?)
	local unlocked = 0
	for _, slot in Places.GetSlots(place) do
		if not isPassSlot(slot) and isUnlocked(nil, data, slot) then
			unlocked += 1
		end
	end
	local nextSlot = if data then getNextSlot(place, data) else nil
	local nextFloor, floorPrice = nil, nil
	if data then
		nextFloor, floorPrice = getNextFloor(place, data)
	end
	place:SetAttribute("SlotsUnlocked", unlocked)
	place:SetAttribute("NextSlotPrice", if nextSlot then Places.GetSlotPrice(nextSlot) else floorPrice)
	place:SetAttribute("NextFloor", nextFloor)
end

-- What each of the player's slots earns per second, by slot key, and all of them together
local function getEarnings(player: Player): ({ [string]: number }, number)
	local data = PlayerDataService.Get(player)
	local earnings, total = {}, 0
	for name, uid in if data then data.Slots else {} do
		local owned = InventoryService.Find(player, uid)
		local item = owned and Items[owned.Id]
		if owned and item then
			local amount = Upgrades.GetMoneyPerSecond(item, Upgrades.GetLevel(owned))
			earnings[name] = amount
			total += amount
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

-- A slot renumbered, removed or given a price in Studio would keep its item hidden for good, so that
-- item goes back to the hotbar instead
local function dropMissingSlots(player: Player, place: Folder)
	local data = PlayerDataService.Get(player)
	if not data then
		return
	end

	local keys = {}
	for _, slot in Places.GetSlots(place) do
		if isUnlocked(player, data, slot) then
			keys[Places.GetSlotKey(slot)] = true
		end
	end

	local dropped = false
	for key, uid in data.Slots do
		if not keys[key] or not InventoryService.Find(player, uid) then
			data.Slots[key] = nil
			dropped = true
		end
	end
	if dropped then
		InventoryService.Sync(player)
	end
end

-- Slots show what the place's owner bought and keeps in them. Only the free ones are there, empty,
-- while nobody owns the place or the owner's data is still loading
local function refreshPlace(place: Folder)
	local owner = getOwner(place)
	local data = if owner then PlayerDataService.Get(owner) else nil
	if owner and data then
		dropMissingSlots(owner, place)
		updateMoneyPerSecond(owner)
	end

	for _, slot in Places.GetSlots(place) do
		setUnlocked(slot, data, isUnlocked(owner, data, slot))
		local uid = data and data.Slots[Places.GetSlotKey(slot)]
		local owned = if owner and uid then InventoryService.Find(owner, uid) else nil
		show(slot, owned)
	end
	updateSign(place, data)
end

-- The owner puts the item in their hands into an empty slot. A pass slot they don't have yet sells
-- them the pass instead
local function onPlaceTriggered(place: Folder, slot: Model, player: Player)
	if place:GetAttribute("OwnerUserId") ~= player.UserId then
		return
	end
	local data = PlayerDataService.Get(player)
	if not isOnBuiltFloor(data, slot) then
		return
	end
	if isPassSlot(slot) and not passOwners[player] then
		if GamePasses.PaidSlots > 0 then
			MarketplaceService:PromptGamePassPurchase(player, GamePasses.PaidSlots)
		else
			warn("GamePasses.PaidSlots needs the paid slots pass's id before it can be sold")
		end
		return
	end

	local owned = InventoryService.GetEquipped(player)
	local item = owned and Items[owned.Id]
	if not (data and owned and item) then
		return
	end
	local key = Places.GetSlotKey(slot)
	if data.Slots[key] or not isUnlocked(player, data, slot) then
		return
	end

	data.Slots[key] = owned.Uid
	InventoryService.Equip(player, nil)
	-- Counted before the item shows, so clients know it was put in by hand and play its landing. A
	-- slot filled from its owner's save as they join doesn't count, and just shows its item
	slot:SetAttribute(PLACE_COUNT_ATTRIBUTE, (slot:GetAttribute(PLACE_COUNT_ATTRIBUTE) or 0) + 1)
	show(slot, owned)
	InventoryService.Sync(player)
	updateMoneyPerSecond(player)
end

-- Whether a slot sent by a client is one of that player's own
local function isOwnSlot(player: Player, slot: any): boolean
	local place = PlaceService.GetPlace(player)
	return place ~= nil and typeof(slot) == "Instance" and slot.Parent == place and Places.IsSlot(slot)
end

-- The slot's Remove button: its item goes back to the hotbar
local function onRemove(player: Player, slot: any)
	local data = PlayerDataService.Get(player)
	if not (data and isOwnSlot(player, slot)) then
		return
	end
	local key = Places.GetSlotKey(slot)
	if not data.Slots[key] then
		return
	end

	data.Slots[key] = nil
	show(slot, nil)
	InventoryService.Sync(player)
	updateMoneyPerSecond(player)
end

-- The slot's Upgrade button: the item in it goes up a level, if it isn't at the top level already and
-- the player can pay for it. The level is the item's own, so it keeps it when taken back out of the
-- slot
local function onUpgrade(player: Player, slot: any)
	local data = PlayerDataService.Get(player)
	if not (data and isOwnSlot(player, slot)) then
		return
	end
	local uid = data.Slots[Places.GetSlotKey(slot)]
	local owned = uid and InventoryService.Find(player, uid)
	local item = owned and Items[owned.Id]
	if not (owned and item) then
		return
	end

	local level = Upgrades.GetLevel(owned)
	local cost = Upgrades.GetCost(item, level)
	if level >= Upgrades.MAX_LEVEL or data.Money < cost then
		UpgradeResult:FireClient(player, slot, false)
		return
	end

	PlayerDataService.AddMoney(player, -cost)
	owned.Level = level + 1
	-- Just the attribute, so the item already floating in the slot isn't made again
	slot:SetAttribute("ItemLevel", owned.Level)
	updateMoneyPerSecond(player)
	UpgradeResult:FireClient(player, slot, true)
end

-- With every slot on their floors bought, the sign sells the player the next floor. Its free slots
-- open with it
local function buyFloor(player: Player, place: Folder, data: PlayerDataService.Data)
	local number, price = getNextFloor(place, data)
	if not (number and price) then
		return
	end
	if data.Money < price then
		BuySlotResult:FireClient(player, false)
		return
	end

	PlayerDataService.AddMoney(player, -price)
	-- The result goes out before the floor is built, so the client knows the floor that arrives is
	-- its own purchase, and can build it up in front of the player
	BuySlotResult:FireClient(player, true, number)
	FloorService.Add(place, data)
	for _, slot in Places.GetSlots(place) do
		if Places.GetSlotFloor(slot) == number then
			setUnlocked(slot, data, isUnlocked(player, data, slot))
		end
	end
	updateSign(place, data)
	InventoryService.EnsureCanStart(player)
end

-- The sign's Increase Slots button: buys the next slot, or the next floor once there are none left,
-- if the player can pay for it. Only at the player's own place, whichever sign was clicked
local function onBuySlot(player: Player, place: any)
	local data = PlayerDataService.Get(player)
	if not (data and place ~= nil and place == PlaceService.GetPlace(player)) then
		return
	end
	local slot = getNextSlot(place, data)
	if not slot then
		buyFloor(player, place, data)
		return
	end

	local price = Places.GetSlotPrice(slot)
	if data.Money < price then
		BuySlotResult:FireClient(player, false)
		return
	end

	PlayerDataService.AddMoney(player, -price)
	data.BoughtSlots[Places.GetSlotKey(slot)] = true
	setUnlocked(slot, data, true)
	updateSign(place, data)
	-- Spending the starting money on slots before buying an item would leave nothing to earn with
	InventoryService.EnsureCanStart(player)
	BuySlotResult:FireClient(player, true)
end

local function givePass(player: Player)
	passOwners[player] = true
	local place = PlaceService.GetPlace(player)
	if place then
		refreshPlace(place)
	end
end

-- Checked once as the player joins, and their pass slots open up if they have it
local function checkPass(player: Player)
	if GamePasses.PaidSlots <= 0 then
		return
	end
	local ok, owns = pcall(MarketplaceService.UserOwnsGamePassAsync, MarketplaceService, player.UserId, GamePasses.PaidSlots)
	if ok and owns and player.Parent == Players then
		givePass(player)
	end
end

function SlotService.Start()
	for _, player in Players:GetPlayers() do
		task.spawn(checkPass, player)
	end
	Players.PlayerAdded:Connect(checkPass)
	Players.PlayerRemoving:Connect(function(player)
		passOwners[player] = nil
	end)
	MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player, passId, purchased)
		if purchased and passId == GamePasses.PaidSlots then
			givePass(player)
		end
	end)

	for _, place in Places.GetAll() do
		spawnSlots(place)

		local numbers = {}
		for _, slot in Places.GetSlots(place) do
			local key = Places.GetSlotKey(slot)
			if numbers[key] then
				warn(
					`{place.Name} has more than one slot with SlotNumber {Places.GetSlotNumber(slot)} on floor {Places.GetSlotFloor(slot)}. Slots are saved by floor and number, so give each its own`
				)
			end
			numbers[key] = true

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
	UpgradeSlot.OnServerEvent:Connect(onUpgrade)
	BuySlot.OnServerEvent:Connect(onBuySlot)

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
