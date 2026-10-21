local Items = require(script.Parent.Items)

-- Items in slots are upgraded a level at a time. Every level earns 1.2x what the one before it did.
-- The first upgrade costs half the item's price, and each one after costs 40% more than the last.
-- Costs grow faster than income, so each upgrade takes about a sixth longer to pay for itself than
-- the one before: cheap boosts early, a slow grind later. That keeps a heavily upgraded item from
-- outrunning a better rarity for long, and income from running away once every slot is full
local Upgrades = {
	INCOME_MULTIPLIER = 1.2,
	FIRST_COST = 0.5, -- Share of the item's price
	COST_GROWTH = 1.4,
	MAX_LEVEL = 100, -- An item at this level can't be upgraded any further
}

-- Items saved before upgrades existed have no level
function Upgrades.GetLevel(owned: Items.OwnedItem): number
	return owned.Level or 1
end

function Upgrades.GetMoneyPerSecond(item: Items.Item, level: number): number
	return item.MoneyPerSecond * Upgrades.INCOME_MULTIPLIER ^ (level - 1)
end

-- What going from this level to the next costs, in whole dollars
function Upgrades.GetCost(item: Items.Item, level: number): number
	return math.round(item.Price * Upgrades.FIRST_COST * Upgrades.COST_GROWTH ^ (level - 1))
end

return Upgrades
