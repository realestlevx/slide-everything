local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ApplyGradient = require(ReplicatedStorage.Shared.ApplyGradient)
local FormatMoney = require(ReplicatedStorage.Shared.FormatMoney)
local ItemModel = require(ReplicatedStorage.Shared.ItemModel)
local Items = require(ReplicatedStorage.Shared.Items)
local Rolling = require(ReplicatedStorage.Shared.Rolling)
local Upgrades = require(ReplicatedStorage.Shared.Upgrades)

local PlayerDataService = require(script.Parent.PlayerDataService)

local InventoryChanged = ReplicatedStorage.Remotes.InventoryChanged
local EquipItem = ReplicatedStorage.Remotes.EquipItem

local HELD_NAME = "HeldItem"
local HELD_SIZE = 4 -- Studs; bigger items are shrunk to this along their longest side
local HELD_GAP = 0.3 -- Studs from the hand's grip to the back of the item, so the hand isn't inside it
-- BillboardGui in ReplicatedStorage shown over the held item, if there is one
local HELD_BILLBOARD_NAME = "HeldItemBillboard"

-- The arm pose played while holding an item (the one tools use) for each rig, and how far the hand's
-- RightGripAttachment ends up turned against the character in that pose (measured in Studio).
-- Held items undo that turn, so they face the way they do on the stands
local HOLD_POSES = {
	[Enum.HumanoidRigType.R15] = { AnimationId = "rbxassetid://507768375", GripTurn = CFrame.Angles(math.rad(2), 0, 0) },
	[Enum.HumanoidRigType.R6] = { AnimationId = "rbxassetid://182393478", GripTurn = CFrame.Angles(math.rad(88.6), 0, 0) },
}

local holdTracks: { [Model]: AnimationTrack } = setmetatable({}, { __mode = "k" }) :: any -- Character -> its hold pose

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

-- Loaded once per character, then played and stopped as items are picked up and put away
local function getHoldTrack(character: Model): AnimationTrack?
	local track = holdTracks[character]
	if track then
		return track
	end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local animator = humanoid and humanoid:FindFirstChildOfClass("Animator")
	local pose = humanoid and HOLD_POSES[humanoid.RigType]
	if not (animator and pose) then
		return nil
	end

	local animation = Instance.new("Animation")
	animation.AnimationId = pose.AnimationId
	track = animator:LoadAnimation(animation)
	track.Priority = Enum.AnimationPriority.Action -- Over walking, so the arm stays out
	track.Looped = true
	holdTracks[character] = track
	return track
end

-- Fills whichever of the Name, Rarity, Level and Cash labels the billboard was designed with
local function fillHeldBillboard(billboard: BillboardGui, item: Items.Item, level: number)
	local nameLabel = billboard:FindFirstChild("Name", true)
	if nameLabel and nameLabel:IsA("TextLabel") then
		nameLabel.Text = item.Name
	end

	local rarityLabel = billboard:FindFirstChild("Rarity", true)
	if rarityLabel and rarityLabel:IsA("TextLabel") then
		rarityLabel.Text = item.Rarity
		-- Tinted by the rarity's gradient (named after it), which needs white text underneath
		rarityLabel.TextColor3 = Color3.new(1, 1, 1)
		ApplyGradient(rarityLabel, item.Rarity)
	end

	local levelLabel = billboard:FindFirstChild("Level", true)
	if levelLabel and levelLabel:IsA("TextLabel") then
		levelLabel.Text = `Level {level}`
	end

	local cashLabel = billboard:FindFirstChild("Cash", true)
	if cashLabel and cashLabel:IsA("TextLabel") then
		cashLabel.Text = `{FormatMoney(Upgrades.GetMoneyPerSecond(item, level), 2)}/s`
	end
end

-- The equipped item is held in the right hand, with the arm out the way tools are held. Made on
-- the server so everyone sees what each player is holding
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
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local pose = humanoid and HOLD_POSES[humanoid.RigType]
	local grip = character:FindFirstChild("RightGripAttachment", true)
	local track = getHoldTrack(character)
	if not (item and pose and grip and grip:IsA("Attachment")) then
		if track then
			track:Stop()
		end
		return
	end

	-- Turned with the character, like an item on its roll stand
	local held = Rolling.CreateDisplay(item, root)
	local turn = root.CFrame.Rotation:ToObjectSpace(held.CFrame.Rotation)
	held.Name = HELD_NAME
	local longestSide = math.max(held.Size.X, held.Size.Y, held.Size.Z)
	ItemModel.SetScale(held, math.min(1, HELD_SIZE / longestSide))
	held.Massless = true
	held.Anchored = false

	-- How far the item reaches towards the character's front from its center, however it's turned
	local front = turn:VectorToObjectSpace(Vector3.new(0, 0, -1))
	local halfDepth = (math.abs(front.X) * held.Size.X + math.abs(front.Y) * held.Size.Y + math.abs(front.Z) * held.Size.Z) / 2

	-- Out in front of the hand's grip, so it follows the arm. Undoing GripTurn lines the grip up with
	-- the character, so -Z there is the character's front
	local weld = Instance.new("Weld")
	weld.Part0 = grip.Parent :: BasePart
	weld.Part1 = held
	weld.C0 = grip.CFrame * pose.GripTurn:Inverse() * CFrame.new(0, 0, -(HELD_GAP + halfDepth)) * turn
	weld.Parent = held

	local billboardTemplate = ReplicatedStorage:FindFirstChild(HELD_BILLBOARD_NAME)
	if billboardTemplate and billboardTemplate:IsA("BillboardGui") then
		local billboard = billboardTemplate:Clone()
		fillHeldBillboard(billboard, item, Upgrades.GetLevel(owned :: Items.OwnedItem))
		billboard.Parent = held -- A billboard inside a part shows over that part
	end

	held.Parent = character
	if track and not track.IsPlaying then
		track:Play()
	end
end

-- Slots are the only income, so a player who owns nothing and can't pay for anything their rolls
-- land on could never earn again. They're topped up to what the cheapest of those costs instead.
-- Checked on join and after anything that spends money or deletes an item
function InventoryService.EnsureCanStart(player: Player)
	local data = PlayerDataService.Get(player)
	if not (data and #data.Inventory == 0) then
		return
	end
	local cheapest = Rolling.GetCheapestPrice()
	if data.Money < cheapest then
		PlayerDataService.SetMoney(player, cheapest)
	end
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
	InventoryService.EnsureCanStart(player)
end

-- Adds a new copy of the item. Returns whether it was added
function InventoryService.Give(player: Player, itemId: string): boolean
	local inventory = getInventory(player)
	if not (inventory and Items[itemId]) then
		return false
	end

	table.insert(inventory, { Uid = HttpService:GenerateGUID(false), Id = itemId, Level = 1 })
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
	PlayerDataService.Loaded:Connect(function(player)
		InventoryService.EnsureCanStart(player)
		InventoryService.Sync(player)
	end)

	EquipItem.OnServerEvent:Connect(function(player, uid)
		if uid == nil or typeof(uid) == "string" then
			InventoryService.Equip(player, uid)
		end
	end)
end

return InventoryService
