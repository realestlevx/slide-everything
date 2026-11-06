-- Game pass ids, from the Creator Dashboard (the game's Monetization > Passes page). 0 until the
-- pass is made: nobody has it, and it isn't offered
local GamePasses = {
	PaidSlots = 2040123667, -- Opens every slot whose marker has GamePass = true
	-- Multiply what the player earns, from their slots and their drops, lowest first. Only the best one
	-- they have counts, so the tiers don't add up
	CashTiers = {
		{ Multiplier = 2, Id = 0 },
		{ Multiplier = 4, Id = 0 },
		{ Multiplier = 6, Id = 0 },
		{ Multiplier = 8, Id = 0 },
	},
}

-- What the player's cash pass multiplies their earnings by. The server keeps it in an attribute, once
-- it's heard from Roblox which passes they have (see PassService)
function GamePasses.GetCashMultiplier(player: Player): number
	local multiplier = player:GetAttribute("CashMultiplier")
	return if typeof(multiplier) == "number" then multiplier else 1
end

return GamePasses
