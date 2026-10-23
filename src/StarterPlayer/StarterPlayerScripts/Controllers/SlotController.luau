local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")

local ApplyGradient = require(ReplicatedStorage.Shared.ApplyGradient)
local FormatMoney = require(ReplicatedStorage.Shared.FormatMoney)
local ItemModel = require(ReplicatedStorage.Shared.ItemModel)
local Items = require(ReplicatedStorage.Shared.Items)
local Places = require(ReplicatedStorage.Shared.Places)
local Rolling = require(ReplicatedStorage.Shared.Rolling)
local Upgrades = require(ReplicatedStorage.Shared.Upgrades)

local ButtonController = require(script.Parent.ButtonController)
local FloatController = require(script.Parent.FloatController)
local InventoryController = require(script.Parent.InventoryController)
local PromptController = require(script.Parent.PromptController)

local RemoveFromSlot = ReplicatedStorage.Remotes.RemoveFromSlot
local IncomeTick = ReplicatedStorage.Remotes.IncomeTick
local UpgradeSlot = ReplicatedStorage.Remotes.UpgradeSlot
local UpgradeResult = ReplicatedStorage.Remotes.UpgradeResult
local LocalPlayer = Players.LocalPlayer
local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")

local BILLBOARD_NAME = "Stuff_UpgradeDisplay"
local SLOT_ITEM_NAME = "SlotItem"
local PARTICLES_NAME = "Particles" -- Folder in the slot part with the emitters that burst on an upgrade
local FINISH_NAME = "Finish" -- Attachment in the slot part with the emitters that burst when an item lands
-- On a pass slot's prompt until its owner has the pass
local BUY_TEXT = " Buy Slot"
local BUY_TEXT_COLOR = Color3.fromRGB(40, 220, 70)

local PRICE_ERROR_COLOR = Color3.fromRGB(255, 50, 50)
local PRICE_FLASH = TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.In) -- Fades the red back out
local SLOT_FADE_INFO = TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
-- Items show bigger the higher their level (see Upgrades.GetSize). The server's copy in the slot is
-- at the item's own size, and each client grows it, from its bottom so it rises out of the slot.
-- Upgraded, it grows to the new size, popping a little past it. Its billboard stays where it is
local GROW_INFO = TweenInfo.new(0.4, Enum.EasingStyle.Back, Enum.EasingDirection.Out)

-- "+ $X" popups over each earning slot, copied from the Cash BillboardGui in its slot part (with an
-- Amount TextLabel). They start at its StudsOffset and float up while fading out
local POPUP_NAME = "Cash"
local POPUP_RISE = 4 -- Studs a popup floats up over its life
local POPUP_RISE_INFO = TweenInfo.new(1, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
-- Fully faded as the rise ends, when the popup is removed
local POPUP_FADE_INFO = TweenInfo.new(1, Enum.EasingStyle.Linear)

-- Putting an item in a slot: on the player's own screen it flies out of their hand in an arc, the
-- moment the prompt fires. Once it lands, the item the server put in springs up from a little
-- smaller, the slot's particles burst and its rarity part lights up. Everyone else sees the landing
local HELD_NAME = "HeldItem" -- The item in a character's hand, made by the server
local FLY_TIME = 0.45 -- Seconds from the hand to the slot
local FLY_ARC = 5 -- Studs the flight rises above a straight line
local LAND_SCALE = 0.6 -- Share of its size the landed item springs up from
local LAND_INFO = TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local FLASH_TRANSPARENCY = 0 -- The rarity part at its brightest, fading back to its own transparency
local FLASH_INFO = TweenInfo.new(0.6, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local PLACE_TIMEOUT = 3 -- Seconds the flown item waits for the server's before going back to the hand
-- Seconds after a slot's PlaceCount goes up (an item put in by hand, not one shown as its owner's
-- save loads) that an item arriving in it lands
local FRESH_TIME = 1
local GIVE_UP_INFO = TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

type Placing = {
	Copy: BasePart, -- Flying from the hand, then floating where the item goes until the server's arrives
	Rest: CFrame, -- Where the item sits in the slot before it floats
	Held: BasePart, -- The item in the hand, hidden on this screen while its copy flies
	Landed: boolean,
}

local slotPlaces: { [Model]: Folder } = {} -- Every slot seen so far -> its place
local billboards: { [Model]: BillboardGui } = {} -- Slot -> the copy of its billboard in PlayerGui
local priceColors: { [TextLabel]: Color3 } = {} -- Each upgrade price label's own color, taken before it first flashes
-- Each pass slot prompt's own text color, taken before it first turns green to sell the pass
local promptColors: { [ProximityPrompt]: Color3 } = {}
local fadedPlaces: { [Folder]: boolean } = {} -- Places whose slots are faded out while their items drop
local billboardSizes: { [BillboardGui]: UDim2 } = {} -- Each billboard's own size, taken before it first shrinks away
-- Each slot item -> the size it's growing to, or at, so it only grows again when its level changes
local itemSizes: { [BasePart]: number } = setmetatable({}, { __mode = "k" }) :: any
local placing: { [Model]: Placing } = {} -- Slots this player is putting an item into right now
local filledAt: { [Model]: number } = {} -- When an item was last put in each slot by hand
local rarityTransparencies: { [BasePart]: number } = {} -- Each rarity part's own transparency, taken before it first flashes

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

-- Items saved before upgrades existed show as level 1
local function getLevel(slot: Model): number
	local level = slot:GetAttribute("ItemLevel")
	return if typeof(level) == "number" then level else 1
end

-- How big the slot's item shows, as a share of its own size
local function getSize(slot: Model): number
	return Upgrades.GetSize(getLevel(slot))
end

-- The item's level changed, like after an upgrade: it grows to its new size
local function grow(slot: Model)
	local display = slot:FindFirstChild(SLOT_ITEM_NAME)
	local size = getSize(slot)
	if display and display:IsA("BasePart") and itemSizes[display] ~= size then
		itemSizes[display] = size
		ItemModel.TweenScale(display, GROW_INFO, size)
	end
end

local function showStats(billboard: BillboardGui, item: Items.Item, level: number)
	local main = (billboard :: any).Main
	local stats = main.Stats
	-- FindFirstChild because stats.Name is the Name property, not the label
	local nameLabel = stats:FindFirstChild("Name") :: TextLabel
	local rarityLabel = stats.Rarity :: TextLabel
	local levelLabel = stats:FindFirstChild("Level") :: TextLabel?
	local priceLabel = billboard:FindFirstChild("UpgradePrice", true) :: TextLabel?

	main.Icon.Image = `rbxassetid://{item.Icon}`
	nameLabel.Text = item.Name
	rarityLabel.Text = item.Rarity
	-- Tinted by the rarity's gradient (named after it), which needs white text underneath
	rarityLabel.TextColor3 = Color3.new(1, 1, 1)
	ApplyGradient(rarityLabel, item.Rarity)
	stats.Cash.Text = `{FormatMoney(Upgrades.GetMoneyPerSecond(item, level), 2)}/s`
	if levelLabel then
		levelLabel.Text = `Level {level}`
	end
	if priceLabel then
		priceLabel.Text = if level >= Upgrades.MAX_LEVEL then "MAX" else FormatMoney(Upgrades.GetCost(item, level))
	end
end

local function refresh(slot: Model)
	local place = slotPlaces[slot]
	local item = getItem(slot)

	local billboard = billboards[slot]
	if billboard then
		local buttons = (billboard :: any).Main.Buttons :: Frame
		billboard.Enabled = item ~= nil
		if item then
			showStats(billboard, item, getLevel(slot))
		end
		-- Everyone sees what's in a slot; only the owner gets its buttons
		buttons.Visible = place:GetAttribute("OwnerUserId") == LocalPlayer.UserId
	end

	local slotPart = slot:FindFirstChild(Places.SLOT_PART)
	local prompt = slotPart and slotPart:FindFirstChildOfClass("ProximityPrompt")
	local unlocked = slot:GetAttribute("Unlocked") == true
	-- The server keeps how many floors the owner has on the place
	local floors = place:GetAttribute("Floors")
	local built = Places.GetSlotFloor(slot) <= (if typeof(floors) == "number" then floors else 1)
	if prompt and slot:GetAttribute("GamePass") == true and not unlocked and built then
		-- A pass slot the owner doesn't have yet sells the pass, so its prompt is always up
		local color = prompt:GetAttribute("ProximityTextColor")
		if not promptColors[prompt] and typeof(color) == "Color3" then
			promptColors[prompt] = color
		end
		prompt.ActionText = BUY_TEXT
		prompt:SetAttribute("ProximityTextColor", BUY_TEXT_COLOR)
		prompt:SetAttribute("ProximityTextGradient", nil)
		prompt:SetAttribute("ProximityGradientText", nil)
		PromptController.SetHidden(place, prompt, false)
	elseif prompt then
		-- Back to its own color once the pass is the owner's
		if promptColors[prompt] then
			prompt:SetAttribute("ProximityTextColor", promptColors[prompt])
			promptColors[prompt] = nil
		end
		local held = InventoryController.GetEquippedItem()
		-- The text is set while the prompt is still hidden, since the prompt UI only reads it when shown
		if held then
			prompt.ActionText = `Place {held.Name}`
			prompt:SetAttribute("ProximityTextGradient", held.Rarity)
			prompt:SetAttribute("ProximityGradientText", held.Name)
		end
		-- Only up while the player holds an item and the slot is bought and empty
		PromptController.SetHidden(place, prompt, item ~= nil or held == nil or not unlocked)
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
	slot:GetAttributeChangedSignal("PlaceCount"):Connect(function()
		filledAt[slot] = os.clock()
	end)
	slot:GetAttributeChangedSignal("ItemId"):Connect(function()
		refresh(slot)
	end)
	slot:GetAttributeChangedSignal("ItemLevel"):Connect(function()
		refresh(slot)
		grow(slot)
	end)
	slot:GetAttributeChangedSignal("Unlocked"):Connect(function()
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

	local buttons = (billboard :: any).Main.Buttons
	local removeButton = buttons.RemoveButton :: ImageButton
	removeButton.Activated:Connect(function()
		RemoveFromSlot:FireServer(slot)
	end)
	local upgradeButton = buttons.UpgradeButton :: ImageButton
	upgradeButton.Activated:Connect(function()
		UpgradeSlot:FireServer(slot)
	end)
	ButtonController.Animate(removeButton)
	ButtonController.Animate(upgradeButton)

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
		amountLabel.Text = `+ {FormatMoney(amount, 2)}`
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

-- One burst from every emitter in the named folder or attachment in the slot part, sized by its
-- EmitCount attribute. Emitted on this client only, so nobody else sees it
local function burstParticles(slot: Model, name: string)
	local slotPart = slot:FindFirstChild(Places.SLOT_PART)
	local particles = slotPart and slotPart:FindFirstChild(name)
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

-- Played from the client, so only this player hears them
local function playSound(name: string) -- Sound under SoundService.SFX
	local sfx = SoundService:FindFirstChild("SFX")
	local sound = sfx and sfx:FindFirstChild(name)
	if sound and sound:IsA("Sound") then
		sound:Play()
	end
end

-- Too expensive: the upgrade price flashes red and fades back to its own color
local function showUpgradeError(slot: Model)
	playSound("Error")

	local billboard = billboards[slot]
	local price = billboard and billboard:FindFirstChild("UpgradePrice", true)
	if not (price and price:IsA("TextLabel")) then
		return
	end
	local color = priceColors[price] or price.TextColor3
	priceColors[price] = color
	-- Starting a new tween on TextColor3 cancels a flash that's still fading
	price.TextColor3 = PRICE_ERROR_COLOR
	TweenService:Create(price, PRICE_FLASH, { TextColor3 = color }):Play()
end

-- The slot's rarity part lights up, then fades back to how see-through it is
local function flashRarity(slot: Model)
	local part = slot:FindFirstChild("Rarity")
	if not (part and part:IsA("BasePart")) then
		return
	end
	local own = rarityTransparencies[part] or part.Transparency
	rarityTransparencies[part] = own
	part.Transparency = FLASH_TRANSPARENCY
	TweenService:Create(part, FLASH_INFO, { Transparency = own }):Play()
end

-- The item springs up into its slot from a little smaller than its level's size, with a burst and a
-- flash
local function land(slot: Model, display: BasePart)
	local size = getSize(slot)
	itemSizes[display] = size
	ItemModel.SetScale(display, LAND_SCALE * size)
	ItemModel.TweenScale(display, LAND_INFO, size)
	burstParticles(slot, FINISH_NAME)
	flashRarity(slot)
end

-- The flown copy has landed and the server's item is in: one swaps for the other as it lands.
-- Until the server's arrives, the copy floats where it'll be
local function finishPlacing(slot: Model)
	local entry = placing[slot]
	if not (entry and entry.Landed) then
		return
	end
	local display = slot:FindFirstChild(SLOT_ITEM_NAME)
	if not (display and display:IsA("BasePart")) then
		entry.Copy.CFrame = entry.Rest
		FloatController.Float(entry.Copy)
		return
	end

	placing[slot] = nil
	entry.Copy:Destroy()
	if not fadedPlaces[slotPlaces[slot]] then
		ItemModel.SetLocalTransparency(display, 0)
	end
	land(slot, display)
	playSound("Place")
end

-- The server didn't put the item in after all: the copy fades and the hand has it again
local function givePlacingUp(slot: Model, entry: Placing)
	if placing[slot] ~= entry then
		return
	end
	placing[slot] = nil
	ItemModel.TweenLocalTransparency(entry.Copy, GIVE_UP_INFO, 1)
	task.delay(GIVE_UP_INFO.Time, entry.Copy.Destroy, entry.Copy)
	ItemModel.SetLocalTransparency(entry.Held, 0)
	for _, descendant in entry.Held:GetDescendants() do
		if descendant:IsA("BillboardGui") then
			descendant.Enabled = true
		end
	end
end

-- A copy of the held item flies from the hand to the slot in an arc, growing to its full size and
-- turning to how it floats there. Made on this screen only, as the prompt fires
local function flyIn(slot: Model, slotPart: BasePart, item: Items.Item, held: BasePart)
	local copy = Rolling.CreateDisplay(item, slotPart)
	local entry: Placing = { Copy = copy, Rest = copy.CFrame, Held = held, Landed = false }
	local from = held.CFrame
	-- The held one is a copy shrunk evenly to fit the hand
	local fromScale = held.Size.X / copy.Size.X
	ItemModel.SetScale(copy, fromScale)
	ItemModel.PivotTo(copy, from)
	copy.Parent = workspace
	placing[slot] = entry

	-- The real one is still in the hand until the server takes it, so it's hidden here meanwhile
	ItemModel.SetLocalTransparency(held, 1)
	for _, descendant in held:GetDescendants() do
		if descendant:IsA("BillboardGui") then
			descendant.Enabled = false
		end
	end

	local started = os.clock()
	local connection: RBXScriptConnection
	connection = RunService.RenderStepped:Connect(function()
		local alpha = math.min((os.clock() - started) / FLY_TIME, 1)
		local eased = alpha * alpha * (3 - 2 * alpha)
		local target = FloatController.GetCFrame(entry.Rest)
		local top = (from.Position + target.Position) / 2 + Vector3.yAxis * FLY_ARC
		local position = from.Position:Lerp(top, eased):Lerp(top:Lerp(target.Position, eased), eased)
		copy.CFrame = from.Rotation:Lerp(target.Rotation, eased) + position
		ItemModel.SetScale(copy, fromScale + (1 - fromScale) * eased)
		if alpha >= 1 then
			connection:Disconnect()
			entry.Landed = true
			finishPlacing(slot)
		end
	end)
	task.delay(PLACE_TIMEOUT, givePlacingUp, slot, entry)
end

-- The player's own place prompt on an empty slot they can use, while holding an item. The server
-- makes the same checks before it puts the item in
local function onPromptTriggered(prompt: ProximityPrompt)
	local slot = getSlot(prompt)
	local place = slot and slotPlaces[slot]
	if not (slot and place and place:GetAttribute("OwnerUserId") == LocalPlayer.UserId) then
		return
	end
	if placing[slot] or getItem(slot) or slot:GetAttribute("Unlocked") ~= true then
		return
	end
	local character = LocalPlayer.Character
	local held = character and character:FindFirstChild(HELD_NAME)
	local item = InventoryController.GetEquippedItem()
	local slotPart = prompt.Parent
	if held and held:IsA("BasePart") and item and slotPart and slotPart:IsA("BasePart") then
		flyIn(slot, slotPart, item, held)
	end
end

local function onDescendantAdded(place: Folder, descendant: Instance)
	if descendant.Name == SLOT_ITEM_NAME and descendant:IsA("BasePart") then
		FloatController.Float(descendant, true)
		local slot = descendant.Parent
		if slot and slot:IsA("Model") then
			itemSizes[descendant] = getSize(slot)
			ItemModel.SetScale(descendant, itemSizes[descendant])
		end
		if fadedPlaces[place] then
			ItemModel.SetLocalTransparency(descendant, 1)
		end
		if slot and slot:IsA("Model") and placing[slot] then
			-- Hidden until the flown copy lands on it
			ItemModel.SetLocalTransparency(descendant, 1)
			finishPlacing(slot)
		elseif slot and slot:IsA("Model") and os.clock() - (filledAt[slot] or -math.huge) < FRESH_TIME then
			land(slot, descendant)
		end
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

-- Fades the place's slots out on this client while its items drop, or back in. LocalTransparencyModifier
-- only changes how they look here, so the server's own transparencies (like a locked slot's) stay as
-- they are. The items in them go at once, since dropped copies take their place
function SlotController.SetFaded(place: Folder, faded: boolean)
	fadedPlaces[place] = if faded then true else nil
	for _, slot in Places.GetSlots(place) do
		for _, descendant in slot:GetDescendants() do
			if not (descendant:IsA("BasePart") or descendant:IsA("Decal")) then
				continue
			end
			if descendant.Name == SLOT_ITEM_NAME and descendant:IsA("BasePart") then
				if faded then
					ItemModel.SetLocalTransparency(descendant, 1)
				else
					ItemModel.TweenLocalTransparency(descendant, SLOT_FADE_INFO, 0)
				end
			elseif descendant:FindFirstAncestor(SLOT_ITEM_NAME) then
				continue -- Part of the item, which goes along with it
			else
				TweenService:Create(descendant, SLOT_FADE_INFO, { LocalTransparencyModifier = if faded then 1 else 0 }):Play()
			end
		end

		-- Billboards have no transparency of their own, so they shrink away instead
		local billboard = billboards[slot]
		if billboard then
			local size = billboardSizes[billboard] or billboard.Size
			billboardSizes[billboard] = size
			TweenService:Create(billboard, SLOT_FADE_INFO, { Size = if faded then UDim2.new() else size }):Play()
		end
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

		local function refreshPlace()
			for slot, slotPlace in slotPlaces do
				if slotPlace == place then
					refresh(slot)
				end
			end
		end
		place:GetAttributeChangedSignal("OwnerUserId"):Connect(refreshPlace)
		place:GetAttributeChangedSignal("Floors"):Connect(refreshPlace)
	end

	-- Picking an item up or putting it away shows or hides the place prompts
	LocalPlayer:GetAttributeChangedSignal("EquippedItem"):Connect(refreshAll)
	ProximityPromptService.PromptTriggered:Connect(onPromptTriggered)

	UpgradeResult.OnClientEvent:Connect(function(slot: Model?, upgraded: boolean)
		-- Nil when the slot has streamed out by the time the answer arrives
		if not slot then
			return
		elseif upgraded then
			playSound("Buy")
			burstParticles(slot, PARTICLES_NAME)
		else
			showUpgradeError(slot)
		end
	end)

	-- Sent each second with what every earning slot made, by slot key
	IncomeTick.OnClientEvent:Connect(function(earnings: { [string]: number })
		local place = getOwnPlace()
		-- Nothing pops up over slots that are faded out
		if not place or fadedPlaces[place] then
			return
		end
		for _, slot in Places.GetSlots(place) do
			local amount = earnings[Places.GetSlotKey(slot)]
			if amount then
				showEarned(slot, amount)
			end
		end
	end)
end

return SlotController
