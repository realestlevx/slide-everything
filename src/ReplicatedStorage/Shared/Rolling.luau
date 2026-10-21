local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ApplyGradient = require(script.Parent.ApplyGradient)
local FormatMoney = require(script.Parent.FormatMoney)
local ItemModel = require(script.Parent.ItemModel)
local Items = require(script.Parent.Items)
local Rarities = require(script.Parent.Rarities)

local Rolling = {
	SPIN_DURATION = 3, -- Seconds from the lever pull until the result lands
	SPIN_STEPS = 25, -- Items shown during a spin, including the result
	POP_TIME = 0.1, -- Each shown item grows to full size in this long
}

local function getWeight(item: Items.Item): number
	if item.OneIn and item.OneIn > 0 then
		return 1 / item.OneIn
	end
	return (item.Chance or 0) / 100
end

-- Every item that can roll, rarest first, with its share of all the odds together (adding up to 1).
-- Items rarer than Common keep their written odds, and the Common items share what's left between
-- them. Without Commons, or with the rest at 100% or more, every share is scaled to fit instead
local rollable: { Items.Item } = {}
local shares: { [Items.Item]: number } = {}
local totalWeight = 0
local commonWeight = 0

for _, item in Items do
	local weight = getWeight(item)
	totalWeight += weight
	if item.Rarity == "Common" then
		commonWeight += weight
	end
end
local restWeight = totalWeight - commonWeight
local fillCommons = commonWeight > 0 and restWeight < 1
for _, item in Items do
	local weight = getWeight(item)
	if weight > 0 then
		table.insert(rollable, item)
		shares[item] = if not fillCommons
			then weight / totalWeight
			elseif item.Rarity == "Common" then weight * (1 - restWeight) / commonWeight
			else weight
	end
end
table.sort(rollable, function(a, b)
	return if shares[a] ~= shares[b] then shares[a] < shares[b] else a.Id < b.Id
end)

-- The item's share with luck: multiplied by the luck to the item's LuckPower (see Items)
local function getLuckyWeight(item: Items.Item, luck: number): number
	return shares[item] * luck ^ (item.LuckPower or 1)
end

-- Every item's share is changed by the luck as its LuckPower says, then all of them are scaled back
-- to add up to 1 and the roll is matched against them. At 1x luck the odds are exactly what the
-- stands show. Luck that boosts the rare items and shrinks the Commons takes both ways at once: at 9x,
-- a Common at -1 is 9x less likely next to an item at 1, so the rare items gain more than 9x
function Rolling.Pick(rng: Random, luck: number?): Items.Item
	local multiplier = math.max(luck or 1, 1)
	local total = 0
	for _, item in rollable do
		total += getLuckyWeight(item, multiplier)
	end

	local roll = rng:NextNumber() * total
	local reach = 0
	for _, item in rollable do
		reach += getLuckyWeight(item, multiplier)
		if roll < reach then
			return item
		end
	end

	-- Floating point leftovers land on the commonest item
	return rollable[#rollable]
end

-- What the cheapest item a roll can land on costs. Luck makes items rarer or likelier, but never
-- rules one out
function Rolling.GetCheapestPrice(): number
	local cheapest = math.huge
	for _, item in rollable do
		cheapest = math.min(cheapest, item.Price)
	end
	return cheapest
end

-- The item's odds without luck, as shown on the stand. Infinite for items that never roll
function Rolling.GetOneIn(item: Items.Item): number
	local share = shares[item]
	return if share then 1 / share else math.huge
end

-- A visual-only copy of the item, with any parts inside it, centered in Roll_Place. Resize and fade
-- it through ItemModel, so the parts inside go along
function Rolling.CreateDisplay(item: Items.Item, rollPlace: BasePart): BasePart
	local display = ReplicatedStorage.Items[item.MeshName]:Clone() :: BasePart
	ItemModel.Prepare(display)
	ItemModel.SetVisualOnly(display)

	display.Anchored = true
	-- Keep the mesh's original rotation, relative to the stand in case a place is turned
	ItemModel.PivotTo(display, rollPlace.CFrame * display.CFrame.Rotation)

	return display
end

-- Spinning items' fill, and the owner's view of the stand's Inside while rolling
Rolling.ROLLING_COLOR = Color3.new(0, 0, 0)

-- Empties a stand for a new roll. The server does it for everyone; the owner's client also
-- does it straight away so the old result doesn't linger while the roll request travels
function Rolling.ClearStand(stand: Instance)
	local rolledItem = stand:FindFirstChild("RolledItem")
	if rolledItem then
		rolledItem:Destroy()
	end
	local rollPlace = stand:FindFirstChild("Roll_Place")
	local billboard = rollPlace and rollPlace:FindFirstChild("Stuff_StatsDisplay") :: BillboardGui?
	if billboard then
		billboard.Enabled = false
	end
end

-- Black silhouette with a white outline while the items are spinning
Rolling.ROLLING_HIGHLIGHT = {
	FillColor = Rolling.ROLLING_COLOR,
	FillTransparency = 0,
	OutlineColor = Color3.new(1, 1, 1),
	OutlineTransparency = 0,
}

-- Rarity-colored outline only, for the rolled outcome
function Rolling.GetOutcomeHighlight(item: Items.Item): { [string]: any }
	return {
		FillColor = Color3.new(0, 0, 0),
		FillTransparency = 1,
		OutlineColor = Rarities[item.Rarity].Color,
		OutlineTransparency = 0,
	}
end

-- A Highlight in a part only outlines that part, so every part of the item that can be seen gets
-- its own. An item with parts inside has an invisible outer part, which gets none
function Rolling.AddHighlight(display: BasePart, style: { [string]: any }): { Highlight }
	local highlights = {}
	for _, part in ItemModel.GetParts(display) do
		if part.Transparency >= 1 then
			continue
		end
		local highlight: any = Instance.new("Highlight")
		highlight.DepthMode = Enum.HighlightDepthMode.Occluded
		for property, value in style do
			highlight[property] = value
		end
		highlight.Parent = part
		table.insert(highlights, highlight)
	end
	return highlights
end

-- Shown over an item while the player is close enough to use it (see FocusController). It's only
-- there for a moment, so GetHighlights leaves it out
Rolling.FOCUS_HIGHLIGHT_NAME = "FocusHighlight"

-- The highlights AddHighlight gave the item
function Rolling.GetHighlights(display: BasePart): { Highlight }
	local highlights = {}
	for _, descendant in display:GetDescendants() do
		if descendant:IsA("Highlight") and descendant.Name ~= Rolling.FOCUS_HIGHLIGHT_NAME then
			table.insert(highlights, descendant)
		end
	end
	return highlights
end

local function formatOneIn(oneIn: number): string
	if oneIn < 10 then
		return (string.format("%.1f", oneIn):gsub("%.0$", ""))
	elseif oneIn >= 1000 then
		-- Shortened like money is, without the $: 2000000 -> "2M"
		return (FormatMoney(oneIn):gsub("^%$", ""))
	end
	return tostring(math.round(oneIn))
end

function Rolling.ShowStats(billboard: BillboardGui, item: Items.Item)
	-- FindFirstChild because billboard.Name is the Name property, not the label
	local nameLabel = billboard:FindFirstChild("Name") :: TextLabel
	local rarityLabel = billboard:FindFirstChild("Rarity") :: TextLabel
	local chanceLabel = billboard:FindFirstChild("Chance") :: TextLabel
	local priceLabel = billboard:FindFirstChild("Price") :: TextLabel

	nameLabel.Text = item.Name
	rarityLabel.Text = item.Rarity
	-- Tinted by the rarity's gradient (named after it), which needs white text underneath
	rarityLabel.TextColor3 = Color3.new(1, 1, 1)
	ApplyGradient(rarityLabel, item.Rarity)
	chanceLabel.Text = `[ 1 in {formatOneIn(Rolling.GetOneIn(item))} ]`
	priceLabel.Text = FormatMoney(item.Price)
	billboard.Enabled = true
end

return Rolling
