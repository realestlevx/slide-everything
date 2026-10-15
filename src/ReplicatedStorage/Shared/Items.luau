local Rarities = require(script.Parent.Rarities)

export type Item = {
	Id: string,
	Name: string,
	Rarity: Rarities.Rarity,
	Price: number, -- What the item costs to buy
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
		Rarity = "Common",
		Price = 25,
		BaseMoneyPerStud = 1,
		MeshName = "ToyCar",
	},
	Phone = {
		Id = "Phone",
		Name = "Phone",
		Rarity = "Uncommon",
		Price = 75,
		BaseMoneyPerStud = 2,
		MeshName = "Phone",
	},
	Controller = {
		Id = "Controller",
		Name = "Controller",
		Rarity = "Rare",
		Price = 250,
		BaseMoneyPerStud = 5,
		MeshName = "Controller",
	},
	CartoonCatfish = {
		Id = "CartoonCatfish",
		Name = "Catfish",
		Rarity = "Epic",
		Price = 1000,
		BaseMoneyPerStud = 12,
		MeshName = "CartoonCatfish",
	},
	Slide = {
		Id = "Slide",
		Name = "Slide",
		Rarity = "Legendary",
		Price = 5000,
		BaseMoneyPerStud = 30,
		MeshName = "Slide",
	},
}

return Items
