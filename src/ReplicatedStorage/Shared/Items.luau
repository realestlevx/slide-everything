local Rarities = require(script.Parent.Rarities)

export type Item = {
	Id: string,
	Name: string,
	-- Image asset id (the number only) shown in the hotbar and on slot billboards. It has to be the
	-- Image's id, not a Decal's: in Asset Manager, right-click the image and Copy Asset ID
	Icon: number,
	Rarity: Rarities.Rarity,
	-- Percent chance of rolling this item, whatever its rarity. Chances are relative: if they don't
	-- add up to 100, each is scaled to fit. 0 means it never rolls
	Chance: number,
	Price: number, -- What the item costs to buy
	MoneyPerSecond: number, -- Earned every second while the item sits in a slot
	BaseMoneyPerStud: number,
	MeshName: string, -- MeshPart in ReplicatedStorage.Items (with its Hitbox)
}

-- One item in a player's inventory. Every copy gets its own Uid, so two of the same item stay apart
export type OwnedItem = {
	Uid: string,
	Id: string, -- Key in Items
}

local Items: { [string]: Item } = {
	ToyCar = {
		Id = "ToyCar",
		Name = "Toy Car",
		Icon = 115762315554217,
		Rarity = "Common",
		Chance = 60,
		Price = 25,
		MoneyPerSecond = 1,
		BaseMoneyPerStud = 1,
		MeshName = "ToyCar",
	},
	Phone = {
		Id = "Phone",
		Name = "Phone",
		Icon = 71237800789095,
		Rarity = "Uncommon",
		Chance = 25,
		Price = 75,
		MoneyPerSecond = 3,
		BaseMoneyPerStud = 2,
		MeshName = "Phone",
	},
	Controller = {
		Id = "Controller",
		Name = "Controller",
		Icon = 112844902116541,
		Rarity = "Rare",
		Chance = 10,
		Price = 250,
		MoneyPerSecond = 10,
		BaseMoneyPerStud = 5,
		MeshName = "Controller",
	},
	CartoonCatfish = {
		Id = "CartoonCatfish",
		Name = "Catfish",
		Icon = 118233477633149,
		Rarity = "Epic",
		Chance = 4,
		Price = 1000,
		MoneyPerSecond = 40,
		BaseMoneyPerStud = 12,
		MeshName = "CartoonCatfish",
	},
	Slide = {
		Id = "Slide",
		Name = "Slide",
		Icon = 112614433925436,
		Rarity = "Legendary",
		Chance = 1,
		Price = 5000,
		MoneyPerSecond = 200,
		BaseMoneyPerStud = 30,
		MeshName = "Slide",
	},
}

return Items
