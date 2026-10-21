local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ItemModel = require(ReplicatedStorage.Shared.ItemModel)
local Places = require(ReplicatedStorage.Shared.Places)
local Rolling = require(ReplicatedStorage.Shared.Rolling)

local LocalPlayer = Players.LocalPlayer

-- Items the player is close enough to use grow and light up white, on their screen only: their own
-- slotted items while the slot's upgrade billboard is in range, and the item on their roll stand
-- while its buy prompt is up. Any highlight the item already has, like its rarity outline, is
-- swapped out meanwhile
local FOCUS_SCALE = 1.3
local FOCUS_HIGHLIGHT = {
	FillColor = Color3.new(1, 1, 1),
	FillTransparency = 0.7,
	OutlineColor = Color3.new(1, 1, 1),
	OutlineTransparency = 0,
}
local FOCUS_INFO = TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out) -- Overshoots a little
local CHECK_INTERVAL = 0.1 -- Seconds between checks

local SLOT_ITEM_NAME = "SlotItem"
-- In the slot part. BillboardRangeController keeps the range it shows within as its Range attribute
local UPGRADE_BILLBOARD_NAME = "Stuff_UpgradeDisplay"
local RANGE_ATTRIBUTE = "Range"
local DEFAULT_RANGE = 15 -- Studs, for a slot whose billboard hasn't streamed in
local STAND_NAME = "RollStand_1"
local ROLL_PLACE_NAME = "Roll_Place" -- Holds the stand's buy prompt
-- The owner's own copy of what's on the stand, or the server's when it wasn't rolled just now
local STAND_ITEM_NAMES = { "RollPreview", "RolledItem" }

type Focus = {
	Highlights: { Highlight }, -- Its focus highlights
	Hidden: { Highlight }, -- Its own highlights, turned off until it's let go
}

local focused: { [BasePart]: Focus } = {}
local buyShown: { [Folder]: boolean } = {} -- Places whose buy prompt is up for this player

local FocusController = {}

local function focus(item: BasePart)
	if focused[item] then
		return
	end
	local hidden = {}
	for _, highlight in Rolling.GetHighlights(item) do
		if highlight.Enabled then
			highlight.Enabled = false
			table.insert(hidden, highlight)
		end
	end
	local highlights = Rolling.AddHighlight(item, FOCUS_HIGHLIGHT)
	for _, highlight in highlights do
		highlight.Name = Rolling.FOCUS_HIGHLIGHT_NAME
	end
	focused[item] = { Highlights = highlights, Hidden = hidden }
	ItemModel.TweenFocus(item, FOCUS_INFO, FOCUS_SCALE)
end

local function unfocus(item: BasePart)
	local entry = focused[item]
	if not entry then
		return
	end
	focused[item] = nil
	for _, highlight in entry.Highlights do
		highlight:Destroy()
	end
	for _, highlight in entry.Hidden do
		highlight.Enabled = true
	end
	ItemModel.TweenFocus(item, FOCUS_INFO, 1)
end

local function getRange(slotPart: Instance): number
	local billboard = slotPart:FindFirstChild(UPGRADE_BILLBOARD_NAME)
	local range = billboard and billboard:GetAttribute(RANGE_ATTRIBUTE)
	return if typeof(range) == "number" then range else DEFAULT_RANGE
end

local function findWanted(from: Vector3): { [BasePart]: boolean }
	local wanted: { [BasePart]: boolean } = {}
	for _, place in Places.GetAll() do
		if place:GetAttribute("OwnerUserId") ~= LocalPlayer.UserId then
			continue
		end
		for _, slot in Places.GetSlots(place) do
			local item = slot:FindFirstChild(SLOT_ITEM_NAME)
			local slotPart = slot:FindFirstChild(Places.SLOT_PART)
			if item and item:IsA("BasePart") and slotPart and slotPart:IsA("BasePart") then
				-- Not while it's hidden, like while the items drop
				local shown = item.LocalTransparencyModifier < 1
				if shown and (slotPart.Position - from).Magnitude <= getRange(slotPart) then
					wanted[item] = true
				end
			end
		end

		local stand = place:FindFirstChild(STAND_NAME)
		if buyShown[place] and stand then
			for _, name in STAND_ITEM_NAMES do
				local item = stand:FindFirstChild(name)
				if item and item:IsA("BasePart") then
					wanted[item] = true
				end
			end
		end
	end
	return wanted
end

local function update()
	local character = LocalPlayer.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local wanted = if root and root:IsA("BasePart") then findWanted(root.Position) else {}

	for item in focused do
		if not item.Parent then
			focused[item] = nil
		elseif not wanted[item] then
			unfocus(item)
		end
	end
	for item in wanted do
		focus(item)
	end
end

local function getBuyPlace(prompt: ProximityPrompt): Folder?
	local rollPlace = prompt.Parent
	local stand = rollPlace and rollPlace.Parent
	if rollPlace and rollPlace.Name == ROLL_PLACE_NAME and stand and stand.Name == STAND_NAME then
		return Places.Find(prompt)
	end
	return nil
end

function FocusController.Start()
	ProximityPromptService.PromptShown:Connect(function(prompt)
		local place = getBuyPlace(prompt)
		if place then
			buyShown[place] = true
			update()
		end
	end)
	ProximityPromptService.PromptHidden:Connect(function(prompt)
		local place = getBuyPlace(prompt)
		if place then
			buyShown[place] = nil
			update()
		end
	end)

	task.spawn(function()
		while true do
			task.wait(CHECK_INTERVAL)
			update()
		end
	end)
end

return FocusController
