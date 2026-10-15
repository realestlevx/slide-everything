local ReplicatedStorage = game:GetService("ReplicatedStorage")

local FormatMoney = require(script.Parent.FormatMoney)
local Items = require(script.Parent.Items)
local Rarities = require(script.Parent.Rarities)

local Rolling = {
	SPIN_DURATION = 3, -- Seconds from the lever pull until the result lands
	SPIN_STEPS = 25, -- Items shown during a spin, including the result
	POP_TIME = 0.1, -- Each shown item grows to full size in this long
}

type Pool = { Weight: number, Items: { Items.Item } }

-- One pool per rarity that has items, so empty rarities never get rolled
local pools: { Pool } = {}
local poolByRarity: { [string]: Pool } = {}
local totalWeight = 0

for _, item in Items do
	local pool = poolByRarity[item.Rarity]
	if not pool then
		pool = { Weight = Rarities[item.Rarity].Weight, Items = {} }
		poolByRarity[item.Rarity] = pool
		table.insert(pools, pool)
		totalWeight += pool.Weight
	end
	table.insert(pool.Items, item)
end

function Rolling.Pick(rng: Random): Items.Item
	local roll = rng:NextNumber() * totalWeight
	for _, pool in pools do
		roll -= pool.Weight
		if roll <= 0 then
			return pool.Items[rng:NextInteger(1, #pool.Items)]
		end
	end

	-- Floating point leftovers land in the last pool
	local last = pools[#pools]
	return last.Items[rng:NextInteger(1, #last.Items)]
end

-- The item's own odds: its rarity's chance split between the items of that rarity
function Rolling.GetOneIn(item: Items.Item): number
	local pool = poolByRarity[item.Rarity]
	return totalWeight / pool.Weight * #pool.Items
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
	rarityLabel.TextColor3 = Rarities[item.Rarity].Color
	chanceLabel.Text = `[ 1 in {formatOneIn(Rolling.GetOneIn(item))} ]`
	priceLabel.Text = FormatMoney(item.Price)
	billboard.Enabled = true
end

return Rolling
