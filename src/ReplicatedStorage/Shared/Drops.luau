local Items = require(script.Parent.Items)
local Upgrades = require(script.Parent.Upgrades)

-- Dropping the slotted items down the slide. A drop pays in seconds of each item's own income, so
-- it's worth the same next to the slots whatever the item, its level or how far the player is: an
-- item that slides all the way earns SECONDS of its income, times the multiplier of the last wall it
-- passed. One that stops early earns its share of the way
local Drops = {
	SECONDS = 10,
	COOLDOWN = 10, -- Seconds from the start of one drop to the next
	MAX_TIME = 30, -- Seconds. A drop is over by then, whatever its items are doing
	MAX_PILE = 40, -- Finished items shown piled on the collect pad. Older ones still count, just unseen
}

-- What an item earns for its run. Progress is the share of the slide it covered, 0 to 1
function Drops.GetPay(item: Items.Item, level: number, progress: number, multiplier: number): number
	return Upgrades.GetMoneyPerSecond(item, level) * Drops.SECONDS * progress * multiplier
end

return Drops
