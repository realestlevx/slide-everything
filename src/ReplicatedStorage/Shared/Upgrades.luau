local Items = require(script.Parent.Items)

-- Items in slots are upgraded a level at a time. Every level earns 1.2x what the one before it did.
-- The first upgrade costs 5 seconds of the item's income, and each one after costs twice the last.
-- Costs follow income, not price, so every item's upgrades pay for themselves equally fast and an
-- item that earns more is always better at the same level, whatever rarities are added later. A
-- cheap Common can't be upgraded past a rarer item. Costs grow much faster than income, so each
-- upgrade takes about 1.7x longer to pay for itself than the one before: cheap boosts early, then a
-- wall around level 10-20 that sends players back to rolling for a better item
local Upgrades = {
	INCOME_MULTIPLIER = 1.2,
	FIRST_COST = 5, -- Seconds of the item's base income
	COST_GROWTH = 2,
	MAX_LEVEL = 100, -- An item at this level can't be upgraded any further
	-- Items in slots grow with their level, so a well upgraded one stands out: 5% bigger for every
	-- level above 1, up to 2.5 times their own size from level 31 on
	SIZE_STEP = 0.05,
	MAX_SIZE = 2.5,
}

-- Items saved before upgrades existed have no level
function Upgrades.GetLevel(owned: Items.OwnedItem): number
	return owned.Level or 1
end

function Upgrades.GetMoneyPerSecond(item: Items.Item, level: number): number
	return item.MoneyPerSecond * Upgrades.INCOME_MULTIPLIER ^ (level - 1)
end

-- How big the item shows in its slot at this level, as a share of its own size
function Upgrades.GetSize(level: number): number
	return math.min(1 + (level - 1) * Upgrades.SIZE_STEP, Upgrades.MAX_SIZE)
end

-- What going from this level to the next costs, in whole dollars
function Upgrades.GetCost(item: Items.Item, level: number): number
	return math.round(item.MoneyPerSecond * Upgrades.FIRST_COST * Upgrades.COST_GROWTH ^ (level - 1))
end

return Upgrades
