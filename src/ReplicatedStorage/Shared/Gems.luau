-- Gems, the rarer currency, for item boosts and chests. They're found on the collect pad: a collect
-- has COLLECT_CHANCE of finding some (see DropService), and how many grows with the player's money
-- per second, as its fourth root. That grows far slower than money does, so gems keep their worth
-- however far a player gets: 16/s finds 2, 10K/s finds 10, 1M/s finds 32 and 100M/s finds 100.
-- Later players collect less often, as their drops last longer (Sliding Time), so what they find in
-- an hour climbs gently, from about 50 starting out to a few hundred late on
local Gems = {
	COLLECT_CHANCE = 0.1, -- Of a collect finding gems
	INCOME_ROOT = 4, -- A find is the player's money per second to the power of 1 / INCOME_ROOT
	MIN_FIND = 1, -- Found however little the player earns
}

-- How many gems a collect finds, when it finds any, for a player earning this much a second
function Gems.GetFind(moneyPerSecond: number): number
	return math.max(math.round(math.max(moneyPerSecond, 0) ^ (1 / Gems.INCOME_ROOT)), Gems.MIN_FIND)
end

return Gems
