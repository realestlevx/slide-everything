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

local function findOwned(player: Player, uid: string): Items.OwnedItem?
	for _, owned in getInventory(player) or {} do
		if owned.Uid == uid then
			return owned
		end
	end
	return nil
end

-- The client only ever gets the whole inventory, so it can't fall out of step
local function sync(player: Player)
	local inventory = getInventory(player)
	if inventory then
		InventoryChanged:FireClient(player, inventory)
	end
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

	local uid = player:GetAttribute("EquippedItem")
	local owned = if typeof(uid) == "string" then findOwned(player, uid) else nil
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

local function equip(player: Player, uid: string?)
	if uid ~= nil and not findOwned(player, uid) then
		return
	end
	player:SetAttribute("EquippedItem", uid)
	updateHeldItem(player)
end

-- Adds a new copy of the item. Returns whether it was added
function InventoryService.Give(player: Player, itemId: string): boolean
	local inventory = getInventory(player)
	if not (inventory and Items[itemId]) then
		return false
	end

	table.insert(inventory, { Uid = HttpService:GenerateGUID(false), Id = itemId })
	sync(player)
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
	PlayerDataService.Loaded:Connect(sync)

	EquipItem.OnServerEvent:Connect(function(player, uid)
		if uid == nil or typeof(uid) == "string" then
			equip(player, uid)
		end
	end)
end

return InventoryService
