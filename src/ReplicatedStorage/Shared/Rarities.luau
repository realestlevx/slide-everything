export type Rarity = "Common" | "Uncommon" | "Rare" | "Epic" | "Legendary"

export type RarityInfo = {
	Weight: number, -- Relative roll chance; only rarities that have items count
	Color: Color3,
}

local Rarities: { [Rarity]: RarityInfo } = {
	Common = { Weight = 60, Color = Color3.fromRGB(210, 210, 210) },
	Uncommon = { Weight = 25, Color = Color3.fromRGB(90, 220, 90) },
	Rare = { Weight = 10, Color = Color3.fromRGB(70, 150, 255) },
	Epic = { Weight = 4, Color = Color3.fromRGB(180, 80, 255) },
	Legendary = { Weight = 1, Color = Color3.fromRGB(255, 190, 40) },
}

return Rarities
