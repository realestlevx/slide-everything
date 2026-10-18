local Rarities = require(script.Parent.Rarities)

export type Item = {
	Id: string,
	Name: string,
	-- Image asset id (the number only) shown in the hotbar and on slot billboards. It has to be the
	-- Image's id, not a Decal's: in Asset Manager, right-click the image and Copy Asset ID
	Icon: number,
	Rarity: Rarities.Rarity,
	-- How likely this item is to roll, whatever its rarity. Give it one of the two, whichever reads
	-- easier: Chance as a percent (Chance = 60) or OneIn for rare ones (OneIn = 2000000 is 1 in 2M).
	-- Odds are relative: if they don't add up to 100%, each is scaled to fit. Neither, or 0, means it
	-- never rolls. Luck doesn't change these; it changes what a roll lands on (see Rolling.Pick)
	Chance: number?,
	OneIn: number?,
	Price: number, -- What the item costs to buy
	MoneyPerSecond: number, -- Earned every second while the item sits in a slot
	BaseMoneyPerStud: number,
	MeshName: string, -- MeshPart in ReplicatedStorage.Items (with its Hitbox)
}

-- One item in a player's inventory. Every copy gets its own Uid, so two of the same item stay apart
export type OwnedItem = {
	Uid: string,
	Id: string, -- Key in Items
	Level: number?, -- Upgrade level, nil for items saved before upgrades (level 1)
}

-- Each rarity earns about 5x the one below it, but takes longer to earn back its price: 10s for a
-- Common, up to about 3.5 min for a Legendary. Slots are the limit, so rarer is always worth having,
-- and the rarest can't be bought the moment they first roll
local Items: { [string]: Item } = {
	ToyCar = {
		Id = "ToyCar",
		Name = "Toy Car",
		Icon = 115762315554217,
		Rarity = "Common",
		Chance = 60,
		Price = 1000,
		MoneyPerSecond = 100,
		BaseMoneyPerStud = 1,
		MeshName = "ToyCar",
	},
	Phone = {
		Id = "Phone",
		Name = "Phone",
		Icon = 71237800789095,
		Rarity = "Uncommon",
		Chance = 30,
		Price = 5000,
		MoneyPerSecond = 400,
		BaseMoneyPerStud = 2,
		MeshName = "Phone",
	},
	Controller = {
		Id = "Controller",
		Name = "Controller",
		Icon = 112844902116541,
		Rarity = "Rare",
		Chance = 8,
		Price = 75000,
		MoneyPerSecond = 2000,
		BaseMoneyPerStud = 5,
		MeshName = "Controller",
	},
	CartoonCatfish = {
		Id = "CartoonCatfish",
		Name = "Catfish",
		Icon = 118233477633149,
		Rarity = "Epic",
		OneIn = 60,
		Price = 1000000,
		MoneyPerSecond = 10000,
		BaseMoneyPerStud = 12,
		MeshName = "CartoonCatfish",
	},
	Slide = {
		Id = "Slide",
		Name = "Slide",
		Icon = 112614433925436,
		Rarity = "Legendary",
		OneIn = 400,
		Price = 10000000,
		MoneyPerSecond = 50000,
		BaseMoneyPerStud = 30,
		MeshName = "Slide",
	},
}

return Items
