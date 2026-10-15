local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local FormatMoney = require(ReplicatedStorage.Shared.FormatMoney)
local Items = require(ReplicatedStorage.Shared.Items)

local InventoryChanged = ReplicatedStorage.Remotes.InventoryChanged
local EquipItem = ReplicatedStorage.Remotes.EquipItem
local UiGradients = ReplicatedStorage.UiGradients
local LocalPlayer = Players.LocalPlayer
local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")

local SLOT_KEYS = {
	[Enum.KeyCode.One] = 1,
	[Enum.KeyCode.Two] = 2,
	[Enum.KeyCode.Three] = 3,
	[Enum.KeyCode.Four] = 4,
	[Enum.KeyCode.Five] = 5,
	[Enum.KeyCode.Six] = 6,
	[Enum.KeyCode.Seven] = 7,
	[Enum.KeyCode.Eight] = 8,
	[Enum.KeyCode.Nine] = 9,
}
local EQUIPPED_SCALE = 1.1
local EQUIPPED_STROKE_COLOR = Color3.new(1, 1, 1)
local EQUIP_INFO = TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

local inventory: { Items.OwnedItem } = {} -- As the server last sent it
local shown: { Items.OwnedItem } = {} -- The items with a slot, in slot order (unknown ids are skipped)
local slots: { [string]: ImageButton } = {} -- Uid -> its slot
local list: Frame? = nil
local template: ImageButton? = nil
local templateStrokeColor = Color3.new()

local InventoryController = {}

local function getEquipped(): string?
	local uid = LocalPlayer:GetAttribute("EquippedItem")
	return if typeof(uid) == "string" then uid else nil
end

-- The server checks the item is owned and sets EquippedItem, which the slots then follow
local function equip(uid: string?)
	EquipItem:FireServer(uid)
end

-- Number keys and clicks: equip that slot's item, or put it away if it's already out
local function toggleSlot(index: number)
	local owned = shown[index]
	if owned then
		equip(if getEquipped() == owned.Uid then nil else owned.Uid)
	end
end

-- Bumpers: step through the slots, with empty hands as a stop between the last slot and the first
local function cycle(step: number)
	if #shown == 0 then
		return
	end

	local current = 0
	local equipped = getEquipped()
	for index, owned in shown do
		if owned.Uid == equipped then
			current = index
		end
	end

	local nextIndex = (current + step) % (#shown + 1)
	local owned = shown[nextIndex]
	equip(owned and owned.Uid)
end

local function updateEquipped()
	local equipped = getEquipped()
	for uid, slot in slots do
		local isEquipped = uid == equipped
		TweenService:Create(slot.EquipScale, EQUIP_INFO, { Scale = if isEquipped then EQUIPPED_SCALE else 1 }):Play()
		slot.UIStroke.Color = if isEquipped then EQUIPPED_STROKE_COLOR else templateStrokeColor
	end
end

local function createSlot(owned: Items.OwnedItem, item: Items.Item, index: number): ImageButton
	local slot = (template :: ImageButton):Clone()
	slot.Name = owned.Uid
	slot.LayoutOrder = index
	slot.Visible = true;
	(slot :: any).LayoutOrderText.Text = tostring(index);
	(slot :: any).CashPerStud.Text = `{FormatMoney(item.BaseMoneyPerStud)}/stud`

	-- The slot keeps its own gradient and takes the rarity's look from UiGradients
	local rarityGradient = UiGradients:FindFirstChild(item.Rarity) :: UIGradient?
	local gradient = slot:FindFirstChild("Gradient") :: UIGradient?
	if rarityGradient and gradient then
		gradient.Color = rarityGradient.Color
		gradient.Transparency = rarityGradient.Transparency
		gradient.Rotation = rarityGradient.Rotation
	end

	local equipScale = Instance.new("UIScale")
	equipScale.Name = "EquipScale"
	equipScale.Parent = slot

	slot.Activated:Connect(function()
		toggleSlot(index)
	end)
	return slot
end

local function render()
	for _, slot in slots do
		slot:Destroy()
	end
	table.clear(slots)
	table.clear(shown)
	if not (list and template) then
		return
	end

	for _, owned in inventory do
		local item = Items[owned.Id]
		if item then
			table.insert(shown, owned)
			local slot = createSlot(owned, item, #shown)
			slot.Parent = list
			slots[owned.Uid] = slot
		end
	end
	updateEquipped()
end

-- The Inventory gui is remade on every respawn, so its template is picked up again each time
local function bindGui(gui: Instance)
	local main = gui:WaitForChild("Main") :: Frame
	local itemTemplate = main:WaitForChild("Item_Template") :: ImageButton
	-- Kept out of the list, only as the source for slots
	itemTemplate.Parent = nil

	list = main
	template = itemTemplate
	templateStrokeColor = (itemTemplate :: any).UIStroke.Color
	table.clear(slots) -- The old slots went away with the old gui
	render()
end

function InventoryController.Start()
	InventoryChanged.OnClientEvent:Connect(function(newInventory: { Items.OwnedItem })
		inventory = newInventory
		render()
	end)
	LocalPlayer:GetAttributeChangedSignal("EquippedItem"):Connect(updateEquipped)

	PlayerGui.ChildAdded:Connect(function(child)
		if child.Name == "Inventory" then
			bindGui(child)
		end
	end)
	local gui = PlayerGui:FindFirstChild("Inventory")
	if gui then
		task.spawn(bindGui, gui)
	end

	UserInputService.InputBegan:Connect(function(input, gameProcessed)
		-- Typing in chat or a text box shouldn't swap items
		if gameProcessed then
			return
		end

		local index = SLOT_KEYS[input.KeyCode]
		if index then
			toggleSlot(index)
		elseif input.KeyCode == Enum.KeyCode.ButtonR1 then
			cycle(1)
		elseif input.KeyCode == Enum.KeyCode.ButtonL1 then
			cycle(-1)
		end
	end)
end

return InventoryController
