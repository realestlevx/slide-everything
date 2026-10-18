local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ApplyGradient = require(script.Parent.ApplyGradient)
local FormatMoney = require(script.Parent.FormatMoney)
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

-- Every item that can roll, rarest first, with its share of all the odds together (adding up to 1)
local rollable: { Items.Item } = {}
local shares: { [Items.Item]: number } = {}
local totalWeight = 0

for _, item in Items do
	local weight = getWeight(item)
	if weight > 0 then
		table.insert(rollable, item)
		totalWeight += weight
	end
end
for _, item in rollable do
	shares[item] = getWeight(item) / totalWeight
end
table.sort(rollable, function(a, b)
	return shares[a] < shares[b]
end)

-- The roll is divided by the luck, then matched against the items' odds stacked rarest first. At 1x
-- luck the odds are exactly what the stands show. At 50x, a 1 in 2M item hits on any roll under
-- 50 in 2M, so every item's chance is 50x and the extra comes out of the commonest items' share
function Rolling.Pick(rng: Random, luck: number?): Items.Item
	local roll = rng:NextNumber() / math.max(luck or 1, 1)
	local reach = 0
	for _, item in rollable do
		reach += shares[item]
		if roll < reach then
			return item
		end
	end

	-- Floating point leftovers land on the commonest item
	return rollable[#rollable]
end

-- What the cheapest item a roll at this luck can land on costs. Enough luck skips the commonest
-- items altogether, so their price stops counting
function Rolling.GetCheapestPrice(luck: number?): number
	local limit = 1 / math.max(luck or 1, 1)
	local cheapest = math.huge
	local reach = 0
	for _, item in rollable do
		if reach >= limit then
			break
		end
		cheapest = math.min(cheapest, item.Price)
		reach += shares[item]
	end
	return cheapest
end

-- The item's odds without luck, as shown on the stand. Infinite for items that never roll
function Rolling.GetOneIn(item: Items.Item): number
	local share = shares[item]
	return if share then 1 / share else math.huge
end

-- A visual-only copy of the item's mesh (no hitbox), centered in Roll_Place
function Rolling.CreateDisplay(item: Items.Item, rollPlace: BasePart): MeshPart
	local display = ReplicatedStorage.Items[item.MeshName]:Clone()
	for _, child in display:GetChildren() do
		if child:IsA("BasePart") or child:IsA("WeldConstraint") or child:IsA("JointInstance") then
			child:Destroy()
		end
	end

	display.Anchored = true
	display.CanCollide = false
	display.CanTouch = false
	display.CanQuery = false
	-- Keep the mesh's original rotation, relative to the stand in case a place is turned
	display.CFrame = rollPlace.CFrame * display.CFrame.Rotation

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

function Rolling.AddHighlight(display: BasePart, style: { [string]: any }): Highlight
	local highlight: any = Instance.new("Highlight")
	highlight.DepthMode = Enum.HighlightDepthMode.Occluded
	for property, value in style do
		highlight[property] = value
	end
	highlight.Parent = display
	return highlight
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
