local CashPasses = require(script.Parent.CashPasses)

-- What a player's slots earn while they're away. It's worked out as they join and waits in their save
-- until they take it from the popup, as it is or multiplied with a developer product. New players
-- don't get any until they're through the tutorial
local OfflineEarnings = {
	ATTRIBUTE = "OfflineCash", -- The player attribute with what's waiting, before any cash pass
	SHARE = 0.5, -- Of what their slots earn while they're playing
	MAX_SECONDS = 3 * 24 * 60 * 60, -- The most time away that counts, each time they're away
	MULTIPLIER = 4, -- What the developer product multiplies it by
	PRODUCT_ID = 3728447543, -- The developer product, from the Creator Dashboard
}

-- What a player earning this much a second makes in this many seconds away, before any cash pass
function OfflineEarnings.GetEarned(seconds: number, moneyPerSecond: number): number
	return math.floor(math.clamp(seconds, 0, OfflineEarnings.MAX_SECONDS) * moneyPerSecond * OfflineEarnings.SHARE)
end

-- What the player gets for taking what's waiting as it is, with their cash pass
function OfflineEarnings.GetWaiting(player: Player): number
	local cash = player:GetAttribute(OfflineEarnings.ATTRIBUTE)
	return if typeof(cash) == "number" then cash * CashPasses.GetMultiplier(player) else 0
end

return OfflineEarnings
