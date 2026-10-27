local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterGui = game:GetService("StarterGui")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Icon = require(ReplicatedStorage.Packages.TopbarPlus)
local FormatMoney = require(ReplicatedStorage.Shared.FormatMoney)
local Hotbar = require(ReplicatedStorage.Shared.Hotbar)
local Items = require(ReplicatedStorage.Shared.Items)
local Rarities = require(ReplicatedStorage.Shared.Rarities)
local Upgrades = require(ReplicatedStorage.Shared.Upgrades)

local ButtonController = require(script.Parent.ButtonController)
local HudController = require(script.Parent.HudController)

local InventoryChanged = ReplicatedStorage.Remotes.InventoryChanged
local EquipItem = ReplicatedStorage.Remotes.EquipItem
local MoveHotbarItem = ReplicatedStorage.Remotes.MoveHotbarItem
local DeleteItems = ReplicatedStorage.Remotes.DeleteItems
local EquipBest = ReplicatedStorage.Remotes.EquipBest
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
local SELECTED_STROKE_COLOR = Color3.fromRGB(255, 8, 12) -- Items picked to delete, in the Remove button's red
local EQUIP_INFO = TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local POP_IN_INFO = TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
-- Empty hotbar positions only show while the backpack's open, as places to drag items to
local EMPTY_TRANSPARENCY = 0.6

-- The topbar button opens and closes the backpack, and so does the key Roblox's own backpack uses
local TOGGLE_KEY = Enum.KeyCode.Backquote
local ICON_CAPTION = "Inventory" -- Shown on hover, so the button itself is only its icon
local ICON_IMAGE = "rbxasset://textures/ui/TopBar/inventoryOff.png"
local ICON_OPEN_IMAGE = "rbxasset://textures/ui/TopBar/inventoryOn.png"
local ICON_IMAGE_SCALE = 0.75 -- Of the button, up from TopbarPlus's 0.5
-- The backpack grows from this share of its size as it opens, overshooting a little, and shrinks
-- back to it as it closes
local OPEN_SCALE = 0.85
local OPEN_INFO = TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local CLOSE_INFO = TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
local CONFIRM_TEXT = "Confirm" -- The Remove button's text while items are being picked to delete

-- While the backpack's open, items can be dragged. A mouse picks one up once it's moved this far
-- holding it down, and a touch once it's been held still on it this long; a touch that moves sooner
-- scrolls the backpack instead
local DRAG_DISTANCE = 8 -- Pixels
local TOUCH_HOLD_TIME = 0.3 -- Seconds
local DRAGGED_TRANSPARENCY = 0.6 -- The item's icon where it was picked up from, while its copy is dragged
local DRAG_Z_INDEX = 100
-- Letting go of a drag over the item it started on would click it too, so clicks this soon after a
-- drag are ignored
local CLICK_AFTER_DRAG = 0.1 -- Seconds

type Entry = {
	Owned: Items.OwnedItem,
	Item: Items.Item,
	Name: string, -- Lowercase, to sort and search by
	Rank: number,
	Income: number,
}

-- An item being pressed on, until it's let go. It's picked up once it's dragged
type Press = {
	Input: InputObject,
	Uid: string,
	From: number?, -- The hotbar position it was pressed on, nil if it was pressed in the backpack
	Button: ImageButton,
	Start: Vector2,
	At: Vector2,
	Ghost: ImageButton?, -- The copy that follows the pointer, once it's picked up
}

local inventory: { Items.OwnedItem } = {} -- As the server last sent it: every item out of a slot
local hotbar: { [number]: string } = {} -- Position -> uid of the item kept there
-- The first inventory is what the player already had, so it doesn't pop in. Later on, items bought
-- or taken back out of a slot do
local received = false
local isOpen = false
local openVersion = 0 -- Bumped on every open and close, so a close only hides it if nothing opened it since
local deleting = false -- Whether the Remove button waits for the player to confirm the items they picked
local selected: { [string]: boolean } = {} -- Uids picked to delete
local sortName = "Rarity" -- Name of the SortFrame button picked last
local searchText = "" -- Lowercase
local press: Press? = nil
local dragEndedAt = 0

-- Parts of the Inventory gui, which is remade on every respawn, so they're found again each time
local screen: ScreenGui? = nil
local hotbarList: Frame? = nil
local hotbarTemplate: ImageButton? = nil
local templateStrokeColor = Color3.new()
local backpack: GuiObject? = nil
local openScale: UIScale? = nil
local grid: ScrollingFrame? = nil
local gridLayout: UIGridLayout? = nil
local gridTemplate: ImageButton? = nil
-- The grid's cells and gaps as shares of its width, as laid out in Studio
local cellWidth = 0.1
local cellGap = 0.02
local removeLabel: TextLabel? = nil
local removeText = "" -- As laid out in Studio
local sortLabel: TextLabel? = nil
local sortOptions: GuiObject? = nil

local itemButtons: { [ImageButton]: string } = {} -- Every button showing an item, in the hotbar or the backpack -> its uid
local hotbarButtons: { [number]: ImageButton } = {} -- Position -> its button, empty or not
local gridButtons: { ImageButton } = {}

local InventoryController = {}

local function getEquipped(): string?
	local uid = LocalPlayer:GetAttribute("EquippedItem")
	return if typeof(uid) == "string" then uid else nil
end

local function findOwned(uid: string): Items.OwnedItem?
	for _, owned in inventory do
		if owned.Uid == uid then
			return owned
		end
	end
	return nil
end

local function getHotbarPosition(uid: string): number?
	for position, hotbarUid in hotbar do
		if hotbarUid == uid then
			return position
		end
	end
	return nil
end

-- The item in the player's hands, if any
function InventoryController.GetEquippedItem(): Items.Item?
	local equipped = getEquipped()
	local owned = equipped and findOwned(equipped)
	return owned and Items[owned.Id]
end

-- The server checks the item is owned and sets EquippedItem, which the buttons then follow
local function equip(uid: string?)
	EquipItem:FireServer(uid)
end

-- Equips the item, or puts it away if it's already out
local function toggleEquip(uid: string)
	equip(if getEquipped() == uid then nil else uid)
end

-- Number keys: the item at that hotbar position
local function toggleSlot(position: number)
	local uid = hotbar[position]
	if uid then
		toggleEquip(uid)
	end
end

-- Bumpers: step through the hotbar's items, with empty hands as a stop between the last and the first
local function cycle(step: number)
	local filled: { string } = {}
	for position = 1, Hotbar.SIZE do
		local uid = hotbar[position]
		if uid then
			table.insert(filled, uid)
		end
	end
	if #filled == 0 then
		return
	end

	local equipped = getEquipped()
	local current = if equipped then table.find(filled, equipped) or 0 else 0
	equip(filled[(current + step) % (#filled + 1)])
end

local function getStrokeColor(uid: string): Color3
	if selected[uid] then
		return SELECTED_STROKE_COLOR
	elseif uid == getEquipped() then
		return EQUIPPED_STROKE_COLOR
	end
	return templateStrokeColor
end

-- The item in the player's hands grows and gets a white outline, and items picked to delete a red one
local function updateLook()
	local equipped = getEquipped()
	for button, uid in itemButtons do
		local scale = (button :: any).EquipScale :: UIScale
		TweenService:Create(scale, EQUIP_INFO, { Scale = if uid == equipped then EQUIPPED_SCALE else 1 }):Play();
		(button :: any).UIStroke.Color = getStrokeColor(uid)
	end
end

-- A newly bought item grows in from nothing, overshooting a little before it settles
local function popIn(uid: string)
	for button, buttonUid in itemButtons do
		if buttonUid == uid then
			local scale = (button :: any).EquipScale :: UIScale
			local goal = scale.Scale
			scale.Scale = 0
			TweenService:Create(scale, POP_IN_INFO, { Scale = goal }):Play()
		end
	end
end

local function isPointerPress(input: InputObject): boolean
	return input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch
end

-- Each touch keeps its own InputObject from start to end; a mouse button may not
local function isSameInput(a: InputObject, b: InputObject): boolean
	return a == b or (a.UserInputType == b.UserInputType and a.UserInputType ~= Enum.UserInputType.Touch)
end

-- A copy of the item follows the pointer, and the item fades where it was until it's let go
local function pickUp(current: Press)
	local gui = screen
	local source = current.Button
	if not (gui and source.Parent) then
		press = nil
		return
	end

	local sourceScale = (source :: any).EquipScale :: UIScale
	local size = source.AbsoluteSize / sourceScale.Scale
	local ghost = source:Clone()
	ghost.Name = "DraggedItem"
	ghost.AnchorPoint = Vector2.new(0.5, 0.5)
	ghost.Size = UDim2.fromOffset(size.X, size.Y)
	ghost.Position = UDim2.fromOffset(current.At.X, current.At.Y)
	ghost.ZIndex = DRAG_Z_INDEX
	ghost.Interactable = false
	ghost.Parent = gui
	current.Ghost = ghost;
	(source :: any).ItemIcon.ImageTransparency = DRAGGED_TRANSPARENCY

	-- A touch dragging an item out of the backpack would scroll it as well
	if grid then
		grid.ScrollingEnabled = false
	end
end

local function startPress(input: InputObject, uid: string, from: number?, button: ImageButton)
	local start = Vector2.new(input.Position.X, input.Position.Y)
	local current: Press = { Input = input, Uid = uid, From = from, Button = button, Start = start, At = start }
	press = current
	if input.UserInputType == Enum.UserInputType.Touch then
		task.delay(TOUCH_HOLD_TIME, function()
			if press == current and not current.Ghost then
				pickUp(current)
			end
		end)
	end
end

-- Ends the press, and the drag if it became one. Returns whether it was a drag
local function endPress(): boolean
	local current = press
	press = nil
	if not (current and current.Ghost) then
		return false
	end
	current.Ghost:Destroy()
	dragEndedAt = os.clock()
	if grid then
		grid.ScrollingEnabled = true
	end
	return true
end

-- Lets go of the item without dropping it anywhere, unfading it where it was
local function cancelPress()
	if endPress() then
		InventoryController.Render()
	end
end

-- Puts the item at that hotbar position, swapping it with whatever was there, or back in the
-- backpack with nil. The items then close up any gap, so they're numbered from 1, and an item put
-- past the last one goes on the end. Shown straight away; the server does the same and sends it back
local function moveInHotbar(uid: string, position: number?)
	local from = getHotbarPosition(uid)
	if position then
		local other = hotbar[position]
		hotbar[position] = uid
		if from and from ~= position then
			hotbar[from] = other
		end
	elseif from then
		hotbar[from] = nil
	end

	local order: { string } = {}
	for index = 1, Hotbar.SIZE do
		local hotbarUid = hotbar[index]
		if hotbarUid then
			table.insert(order, hotbarUid)
		end
	end
	table.clear(hotbar)
	for index, hotbarUid in order do
		hotbar[index] = hotbarUid
	end

	MoveHotbarItem:FireServer(uid, position)
	InventoryController.Render()
end

local function isOver(gui: GuiObject, at: Vector2): boolean
	local topLeft = gui.AbsolutePosition
	local bottomRight = topLeft + gui.AbsoluteSize
	return at.X >= topLeft.X and at.X <= bottomRight.X and at.Y >= topLeft.Y and at.Y <= bottomRight.Y
end

-- Dropped on a hotbar position, the item goes there. Dropped anywhere on the backpack, an item
-- picked up from the hotbar leaves it. Anywhere else, it stays where it was, unfaded
local function drop(current: Press, at: Vector2)
	for position, button in hotbarButtons do
		if button.Visible and isOver(button, at) then
			if hotbar[position] ~= current.Uid then
				moveInHotbar(current.Uid, position)
			else
				InventoryController.Render()
			end
			return
		end
	end
	if current.From and backpack and isOver(backpack, at) then
		moveInHotbar(current.Uid, nil)
		return
	end
	InventoryController.Render()
end

local function onPointerMoved(input: InputObject)
	local current = press
	if not current then
		return
	end
	local isMouse = current.Input.UserInputType == Enum.UserInputType.MouseButton1
	if isMouse and input.UserInputType ~= Enum.UserInputType.MouseMovement then
		return
	elseif not isMouse and input ~= current.Input then
		return
	end

	current.At = Vector2.new(input.Position.X, input.Position.Y)
	local ghost = current.Ghost
	if ghost then
		ghost.Position = UDim2.fromOffset(current.At.X, current.At.Y)
	elseif (current.At - current.Start).Magnitude >= DRAG_DISTANCE then
		if isMouse then
			pickUp(current)
		else
			press = nil
		end
	end
end

local function onPointerReleased(input: InputObject)
	local current = press
	if not (current and isSameInput(current.Input, input)) then
		return
	end
	-- Found by the buttons as they are, before anything moves
	if endPress() then
		drop(current, Vector2.new(input.Position.X, input.Position.Y))
	end
end

-- Clicked, the item goes in or out of the player's hands, or, while picking items to delete, is
-- picked or unpicked. Pressed and dragged while the backpack's open, it's picked up
local function bindItemButton(button: ImageButton, uid: string, position: number?)
	button.Activated:Connect(function()
		if (press and press.Ghost) or os.clock() - dragEndedAt < CLICK_AFTER_DRAG then
			return
		end
		if deleting then
			if selected[uid] then
				selected[uid] = nil
			else
				selected[uid] = true
			end
			updateLook()
		else
			toggleEquip(uid)
		end
	end)
	button.InputBegan:Connect(function(input)
		if isOpen and not press and isPointerPress(input) then
			startPress(input, uid, position, button)
		end
	end)
end

-- Shows the item on a copy of the template. Its EquipScale grows it while it's in the player's hands
local function createItemButton(template: ImageButton, owned: Items.OwnedItem, item: Items.Item): ImageButton
	local button = template:Clone()
	button.Name = owned.Uid
	button.Visible = true;
	-- What the item earns in a slot, at its own level, which it keeps when taken back out of one
	(button :: any).CashPerStud.Text = `{FormatMoney(Upgrades.GetMoneyPerSecond(item, Upgrades.GetLevel(owned)), 2)}/s`;
	(button :: any).ItemIcon.Image = `rbxassetid://{item.Icon}`;
	(button :: any).UIStroke.Color = getStrokeColor(owned.Uid)

	-- The button keeps its own gradient and takes the rarity's look from UiGradients
	local rarityGradient = UiGradients:FindFirstChild(item.Rarity) :: UIGradient?
	local gradient = button:FindFirstChild("Gradient") :: UIGradient?
	if rarityGradient and gradient then
		gradient.Color = rarityGradient.Color
		gradient.Transparency = rarityGradient.Transparency
		gradient.Rotation = rarityGradient.Rotation
	end

	local equipScale = Instance.new("UIScale")
	equipScale.Name = "EquipScale"
	equipScale.Scale = if getEquipped() == owned.Uid then EQUIPPED_SCALE else 1
	equipScale.Parent = button

	itemButtons[button] = owned.Uid
	return button
end

local function createEmptyButton(template: ImageButton): ImageButton
	local button = template:Clone()
	button.Name = "Empty"
	button.Visible = isOpen
	button.BackgroundTransparency = EMPTY_TRANSPARENCY
	button.AutoButtonColor = false;
	(button :: any).ItemIcon.Visible = false;
	(button :: any).CashPerStud.Visible = false
	return button
end

local function renderHotbar()
	for _, button in hotbarButtons do
		itemButtons[button] = nil
		button:Destroy()
	end
	table.clear(hotbarButtons)
	local list, template = hotbarList, hotbarTemplate
	if not (list and template) then
		return
	end

	for position = 1, Hotbar.SIZE do
		local uid = hotbar[position]
		local owned = if uid then findOwned(uid) else nil
		local item = owned and Items[owned.Id]
		local button
		if owned and item then
			button = createItemButton(template, owned, item)
			bindItemButton(button, owned.Uid, position)
		else
			button = createEmptyButton(template)
		end
		button.LayoutOrder = position;
		(button :: any).LayoutOrderText.Text = tostring(position)
		button.Parent = list
		hotbarButtons[position] = button
	end
end

local function matchesSearch(entry: Entry): boolean
	return searchText == ""
		or string.find(entry.Name, searchText, 1, true) ~= nil
		or string.find(string.lower(entry.Item.Rarity), searchText, 1, true) ~= nil
end

-- By the SortFrame button picked last: rarest first, earning the most first, or A to Z. Ties go
-- by what they earn, then their name
local function isBefore(a: Entry, b: Entry): boolean
	if sortName == "Rarity" and a.Rank ~= b.Rank then
		return a.Rank > b.Rank
	elseif sortName == "Name" and a.Name ~= b.Name then
		return a.Name < b.Name
	elseif a.Income ~= b.Income then
		return a.Income > b.Income
	elseif a.Name ~= b.Name then
		return a.Name < b.Name
	end
	return a.Owned.Uid < b.Owned.Uid
end

-- Every item out of a slot and out of the hotbar that matches the search. Only made while the
-- backpack's on screen, closing included
local function renderGrid()
	for _, button in gridButtons do
		itemButtons[button] = nil
		button:Destroy()
	end
	table.clear(gridButtons)
	local list, template, frame = grid, gridTemplate, backpack
	if not (list and template and frame and (isOpen or frame.Visible)) then
		return
	end

	local entries: { Entry } = {}
	for _, owned in inventory do
		local item = Items[owned.Id]
		if not item or getHotbarPosition(owned.Uid) then
			continue
		end
		local rarity = Rarities[item.Rarity]
		local entry: Entry = {
			Owned = owned,
			Item = item,
			Name = string.lower(item.Name),
			Rank = if rarity then rarity.Rank else 0,
			Income = Upgrades.GetMoneyPerSecond(item, Upgrades.GetLevel(owned)),
		}
		if matchesSearch(entry) then
			table.insert(entries, entry)
		end
	end
	table.sort(entries, isBefore)

	for index, entry in entries do
		local button = createItemButton(template, entry.Owned, entry.Item)
		bindItemButton(button, entry.Owned.Uid, nil)
		button.LayoutOrder = index;
		-- Only hotbar positions have a number key
		(button :: any).LayoutOrderText.Visible = false
		button.Parent = list
		table.insert(gridButtons, button)
	end
end

function InventoryController.Render()
	renderHotbar()
	renderGrid()
end

-- Square cells as wide as the grid's layout made them, in pixels instead, so the canvas grows to
-- fit every item. Measured without the backpack's open scale, which shrinks them along with it
local function updateCells()
	local list, layout, scale = grid, gridLayout, openScale
	if not (list and layout and scale) then
		return
	end
	local width = list.AbsoluteSize.X / scale.Scale
	local cell = math.floor(width * cellWidth)
	local gap = math.floor(width * cellGap)
	layout.CellSize = UDim2.fromOffset(cell, cell)
	layout.CellPadding = UDim2.fromOffset(gap, gap)
end

local function setDeleting(on: boolean)
	deleting = on
	table.clear(selected)
	if removeLabel then
		removeLabel.Text = if on then CONFIRM_TEXT else removeText
	end
	updateLook()
end

-- The first click turns it into Confirm, so the player can pick the items to delete. The next
-- deletes them, or just turns it back if none were picked
local function onRemove()
	if not deleting then
		setDeleting(true)
		return
	end
	local uids = {}
	for uid in selected do
		if findOwned(uid) then
			table.insert(uids, uid)
		end
	end
	if #uids > 0 then
		DeleteItems:FireServer(uids)
	end
	setDeleting(false)
end

local function setSort(option: GuiObject)
	sortName = option.Name
	if sortLabel and option:IsA("TextButton") then
		sortLabel.Text = `Sort: {option.Text}`
	end
	renderGrid()
end

local function setOpen(open: boolean)
	isOpen = open
	openVersion += 1
	local version = openVersion
	if not open then
		cancelPress()
		if deleting then
			setDeleting(false)
		end
		if sortOptions then
			sortOptions.Visible = false
		end
	end
	InventoryController.Render() -- The hotbar's empty positions show only while it's open

	local frame, scale = backpack, openScale
	if not (frame and scale) then
		return
	end
	if open then
		if not frame.Visible then
			scale.Scale = OPEN_SCALE
		end
		frame.Visible = true
		TweenService:Create(scale, OPEN_INFO, { Scale = 1 }):Play()
	else
		TweenService:Create(scale, CLOSE_INFO, { Scale = OPEN_SCALE }):Play()
		task.delay(CLOSE_INFO.Time, function()
			if openVersion == version then
				frame.Visible = false
			end
		end)
	end
end

local function bindBackpack(frame: Frame)
	local list = frame:WaitForChild("Main"):WaitForChild("ScrollingFrame") :: ScrollingFrame
	local layout = list:WaitForChild("UIGridLayout") :: UIGridLayout
	local slotTemplate = list:WaitForChild("Item_Template") :: ImageButton
	-- Kept out of the grid, only as the source for its items. Any other copies are previews
	for _, child in list:GetChildren() do
		if child.Name == "Item_Template" and child ~= slotTemplate then
			child:Destroy()
		end
	end
	slotTemplate.Parent = nil

	local buttons = frame:WaitForChild("Buttons")
	local removeButton = buttons:WaitForChild("Remove") :: GuiButton
	local equipBestButton = buttons:WaitForChild("EquipBest") :: GuiButton
	local controls = frame:WaitForChild("Buttons2")
	local controlsMain = controls:WaitForChild("Main")
	local sortButton = controlsMain:WaitForChild("Sort") :: GuiButton
	local searchBox = controlsMain:WaitForChild("Search"):WaitForChild("TextBox") :: TextBox
	local options = controls:WaitForChild("SortFrame") :: GuiObject
	local optionButtons: { GuiButton } = {}
	for _, child in options:GetChildren() do
		if child:IsA("GuiButton") then
			table.insert(optionButtons, child)
		end
	end

	backpack = frame
	grid = list
	gridLayout = layout
	gridTemplate = slotTemplate
	cellWidth = layout.CellSize.X.Scale
	cellGap = layout.CellPadding.X.Scale
	removeLabel = removeButton:WaitForChild("Text") :: TextLabel
	removeText = (removeLabel :: TextLabel).Text
	sortLabel = sortButton:WaitForChild("Text") :: TextLabel
	sortOptions = options
	deleting = false
	table.clear(selected)
	searchText = ""

	local scale = Instance.new("UIScale")
	scale.Name = "OpenScale"
	scale.Scale = if isOpen then 1 else OPEN_SCALE
	scale.Parent = frame
	openScale = scale
	frame.Visible = isOpen
	options.Visible = false

	list.CanvasSize = UDim2.new()
	list.AutomaticCanvasSize = Enum.AutomaticSize.Y
	list.ScrollingDirection = Enum.ScrollingDirection.Y
	list:GetPropertyChangedSignal("AbsoluteSize"):Connect(updateCells)
	updateCells()

	-- Laid out with its hint as its text, so the hint keeps the text's color
	if searchBox.PlaceholderText == "" then
		searchBox.PlaceholderText = searchBox.Text
		searchBox.PlaceholderColor3 = searchBox.TextColor3
	end
	searchBox.Text = ""
	searchBox.ClearTextOnFocus = false
	searchBox:GetPropertyChangedSignal("Text"):Connect(function()
		searchText = string.lower(searchBox.Text)
		renderGrid()
	end)

	for _, option in optionButtons do
		if option.Name == sortName then
			setSort(option)
		end
	end

	-- Found before they're animated, which moves each into a holder of its own
	for _, button in { removeButton, equipBestButton, sortButton, table.unpack(optionButtons) } do
		ButtonController.Animate(button)
	end
	removeButton.Activated:Connect(onRemove)
	-- The server picks the items and fills the slots (see SlotService)
	equipBestButton.Activated:Connect(function()
		EquipBest:FireServer()
	end)
	sortButton.Activated:Connect(function()
		options.Visible = not options.Visible
	end)
	for _, option in optionButtons do
		option.Activated:Connect(function()
			options.Visible = false
			setSort(option)
		end)
	end
end

local function bindGui(gui: Instance)
	endPress() -- Its copy went away with the old gui
	local main = gui:WaitForChild("Main") :: Frame
	local itemTemplate = main:WaitForChild("Item_Template") :: ImageButton
	-- Kept out of the hotbar, only as the source for its positions
	itemTemplate.Parent = nil

	screen = gui :: ScreenGui
	hotbarList = main
	hotbarTemplate = itemTemplate
	templateStrokeColor = (itemTemplate :: any).UIStroke.Color
	-- The old buttons went away with the old gui
	table.clear(itemButtons)
	table.clear(hotbarButtons)
	table.clear(gridButtons)
	bindBackpack(gui:WaitForChild("BackPack") :: Frame)
	InventoryController.Render()
end

local function createIcon()
	local icon = Icon.new()
		:setName("Inventory")
		:setRight()
		:setCaption(ICON_CAPTION)
		:setImage(ICON_IMAGE, "Deselected")
		:setImage(ICON_OPEN_IMAGE, "Selected")
		:setImageScale(ICON_IMAGE_SCALE)
		:bindToggleKey(TOGGLE_KEY)
		:bindEvent("toggled", function(_, isSelected: boolean)
			setOpen(isSelected)
		end)

	-- Out of the way while the player's items drop, along with the hotbar
	HudController.DropViewChanged:Connect(function(on: boolean)
		if on then
			icon:deselect()
		end
		icon:setEnabled(not on)
	end)
end

function InventoryController.Start()
	-- This backpack takes the place of Roblox's own, which would open on the same key
	StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Backpack, false)

	InventoryChanged.OnClientEvent:Connect(function(newInventory: { Items.OwnedItem }, newHotbar: { [string]: string })
		local hadBefore: { [string]: boolean } = {}
		for _, owned in inventory do
			hadBefore[owned.Uid] = true
		end
		local isFirst = not received
		received = true

		inventory = newInventory
		table.clear(hotbar)
		for position, uid in newHotbar do
			local index = tonumber(position)
			if index then
				hotbar[index] = uid
			end
		end
		InventoryController.Render()
		if not isFirst then
			for _, owned in inventory do
				if not hadBefore[owned.Uid] then
					popIn(owned.Uid)
				end
			end
		end
	end)
	LocalPlayer:GetAttributeChangedSignal("EquippedItem"):Connect(updateLook)

	PlayerGui.ChildAdded:Connect(function(child)
		if child.Name == "Inventory" then
			bindGui(child)
		end
	end)
	local gui = PlayerGui:FindFirstChild("Inventory")
	if gui then
		task.spawn(bindGui, gui)
	end
	createIcon()

	UserInputService.InputChanged:Connect(onPointerMoved)
	-- Listened for everywhere, since a drag is let go wherever the item's dropped
	UserInputService.InputEnded:Connect(onPointerReleased)
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
