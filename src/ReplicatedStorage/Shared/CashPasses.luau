-- Multiply what the player earns, from their slots and their drops. Only the best one they have counts,
-- so they don't add up. Each is a developer product rather than a game pass, as Roblox will sell any
-- game pass to anyone at any time, and these go in order: the game only offers the next one up. That
-- relies on them staying Unlisted on the Creator Dashboard (Monetization > Shop), as a listed one can be
-- bought outside the game. What the player has is kept in their save
local CashPasses = {
	-- Lowest first. Ids from the Creator Dashboard, 0 until the product is made: it isn't offered
	Tiers = {
		{ Multiplier = 2, Id = 3721702659 },
		{ Multiplier = 4, Id = 3721703674 },
		{ Multiplier = 6, Id = 3721703795 },
		{ Multiplier = 8, Id = 3721703853 },
	},
}

-- What the player's cash pass multiplies their earnings by. The server keeps it in an attribute once
-- their data has loaded
function CashPasses.GetMultiplier(player: Player): number
	local multiplier = player:GetAttribute("CashMultiplier")
	return if typeof(multiplier) == "number" then multiplier else 1
end

return CashPasses
