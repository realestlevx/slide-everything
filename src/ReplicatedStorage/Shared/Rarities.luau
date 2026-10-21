export type Rarity = "Common" | "Uncommon" | "Rare" | "Epic" | "Legendary" | "Mythic"

-- How rare an item looks. Roll odds are each item's own Chance (in Items), not its rarity
export type RarityInfo = {
	Color: Color3,
}

local Rarities: { [Rarity]: RarityInfo } = {
	Common = { Color = Color3.fromRGB(210, 210, 210) },
	Uncommon = { Color = Color3.fromRGB(90, 220, 90) },
	Rare = { Color = Color3.fromRGB(70, 150, 255) },
	Epic = { Color = Color3.fromRGB(180, 80, 255) },
	Legendary = { Color = Color3.fromRGB(255, 190, 40) },
	Mythic = { Color = Color3.fromRGB(255, 45, 85) },
}

return Rarities
