export type Rarity = "Common" | "Uncommon" | "Rare" | "Epic" | "Legendary" | "Mythic" | "Exotic"

-- How rare an item looks. Roll odds are each item's own Chance (in Items), not its rarity
export type RarityInfo = {
	Color: Color3,
	Rank: number, -- Higher is rarer; the backpack sorts by it
}

local Rarities: { [Rarity]: RarityInfo } = {
	Common = { Color = Color3.fromRGB(210, 210, 210), Rank = 1 },
	Uncommon = { Color = Color3.fromRGB(90, 220, 90), Rank = 2 },
	Rare = { Color = Color3.fromRGB(70, 150, 255), Rank = 3 },
	Epic = { Color = Color3.fromRGB(180, 80, 255), Rank = 4 },
	Legendary = { Color = Color3.fromRGB(255, 190, 40), Rank = 5 },
	Mythic = { Color = Color3.fromRGB(255, 45, 85), Rank = 6 },
	Exotic = { Color = Color3.fromRGB(225, 0, 150), Rank = 7 },
}

return Rarities
