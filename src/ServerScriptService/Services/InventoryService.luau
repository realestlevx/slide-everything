local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Items = require(ReplicatedStorage.Shared.Items)
local Rolling = require(ReplicatedStorage.Shared.Rolling)

local PlayerDataService = require(script.Parent.PlayerDataService)

local InventoryChanged = ReplicatedStorage.Remotes.InventoryChanged
local EquipItem = ReplicatedStorage.Remotes.EquipItem

local HELD_NAME = "HeldItem"
local HELD_SIZE = 2.5 -- Studs; bigger items are shrunk to this along their longest side
local HELD_GAP = 1 -- Studs between the character's center and the near side of the item

local InventoryService = {}

local function getInventory(player: Player): { Items.OwnedItem }?
	local data = PlayerDataService.Get(player)
	return data and data.Inventory
end

-- Items in a slot stay owned, but sit there instead of in the player's hands
local function isPlaced(data: PlayerDataService.Data, uid: string): boolean
	for _, placedUid in data.Slots do
		if placedUid == uid then
			return true
		end
	end
	return false
end

-- Any owned item, placed in a slot or not
function InventoryService.Find(player: Player, uid: string): Items.OwnedItem?
	for _, owned in getInventory(player) or {} do
		if owned.Uid == uid then
			return owned
		end
	end
	return nil
end

local function findHoldable(player: Player, uid: string): Items.OwnedItem?
	local data = PlayerDataService.Get(player)
	local owned = InventoryService.Find(player, uid)
	return if data and owned and not isPlaced(data, uid) then owned else nil
end

-- The item in the player's hands, if any
function InventoryService.GetEquipped(player: Player): Items.OwnedItem?
	local uid = player:GetAttribute("EquippedItem")
	return if typeof(uid) == "string" then findHoldable(player, uid) else nil
end

-- The client only ever gets the whole hotbar, so it can't fall out of step. Items in a slot
-- are left out; the slot shows them instead
function InventoryService.Sync(player: Player)
	local data = PlayerDataService.Get(player)
	if not data then
		return
	end

	local hotbar = {}
	for _, owned in data.Inventory do
		if not isPlaced(data, owned.Uid) then
			table.insert(hotbar, owned)
		end
	end
	InventoryChanged:FireClient(player, hotbar)
end

-- The equipped item is carried in front of the character, welded so it follows every move.
-- Made on the server so everyone sees what each player is holding
local function updateHeldItem(player: Player)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not (character and root) then
		return
	end

	local old = character:FindFirstChild(HELD_NAME)
	if old then
		old:Destroy()
	end

	local owned = InventoryService.GetEquipped(player)
	local item = owned and Items[owned.Id]
	if not item then
		return
	end

	-- Centered on the root and turned with it, like an item on its roll stand
	local held = Rolling.CreateDisplay(item, root)
	held.Name = HELD_NAME
	local longestSide = math.max(held.Size.X, held.Size.Y, held.Size.Z)
	local scale = math.min(1, HELD_SIZE / longestSide)
	held.Size *= scale
	held.Massless = true
	held.CFrame += root.CFrame.LookVector * (HELD_GAP + longestSide * scale / 2)
	held.Parent = character

	local weld = Instance.new("WeldConstraint")
	weld.Part0 = root
	weld.Part1 = held
	weld.Parent = held
	held.Anchored = false
end

-- Nil puts the held item away
function InventoryService.Equip(player: Player, uid: string?)
	if uid ~= nil and not findHoldable(player, uid) then
		return
	end
	player:SetAttribute("EquippedItem", uid)
	updateHeldItem(player)
end

-- Deletes the item for good. Only items out of slots, so no slot is left showing a deleted item
function InventoryService.Delete(player: Player, uid: string)
	local inventory = getInventory(player)
	if not (inventory and findHoldable(player, uid)) then
		return
	end

	for index, owned in inventory do
		if owned.Uid == uid then
			table.remove(inventory, index)
			break
		end
	end
	if player:GetAttribute("EquippedItem") == uid then
		InventoryService.Equip(player, nil)
	end
	InventoryService.Sync(player)
end

-- Adds a new copy of the item. Returns whether it was added
function InventoryService.Give(player: Player, itemId: string): boolean
	local inventory = getInventory(player)
	if not (inventory and Items[itemId]) then
		return false
	end

	table.insert(inventory, { Uid = HttpService:GenerateGUID(false), Id = itemId })
	InventoryService.Sync(player)
	return true
end

local function onPlayerAdded(player: Player)
	player.CharacterAdded:Connect(function(character)
		character:WaitForChild("HumanoidRootPart")
		updateHeldItem(player)
	end)
end

function InventoryService.Start()
	for _, player in Players:GetPlayers() do
		onPlayerAdded(player)
	end
	Players.PlayerAdded:Connect(onPlayerAdded)
	PlayerDataService.Loaded:Connect(InventoryService.Sync)

	EquipItem.OnServerEvent:Connect(function(player, uid)
		if uid == nil or typeof(uid) == "string" then
			InventoryService.Equip(player, uid)
		end
	end)
end

return InventoryService
