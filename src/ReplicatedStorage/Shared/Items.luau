local Rarities = require(script.Parent.Rarities)

export type Item = {
	Id: string,
	Name: string,
	Rarity: Rarities.Rarity,
	BaseMoneyPerStud: number,
	MeshName: string, -- MeshPart in ReplicatedStorage.Items (with its Hitbox)
}

local Items: { [string]: Item } = {
	ToyCar = {
		Id = "ToyCar",
		Name = "Toy Car",
		Rarity = "Common",
		BaseMoneyPerStud = 1,
		MeshName = "ToyCar",
	},
	Phone = {
		Id = "Phone",
		Name = "Phone",
		Rarity = "Uncommon",
		BaseMoneyPerStud = 2,
		MeshName = "Phone",
	},
	Controller = {
		Id = "Controller",
		Name = "Controller",
		Rarity = "Rare",
		BaseMoneyPerStud = 5,
		MeshName = "Controller",
	},
	CartoonCatfish = {
		Id = "CartoonCatfish",
		Name = "Catfish",
		Rarity = "Epic",
		BaseMoneyPerStud = 12,
		MeshName = "CartoonCatfish",
	},
	Slide = {
		Id = "Slide",
		Name = "Slide",
		Rarity = "Legendary",
		BaseMoneyPerStud = 30,
		MeshName = "Slide",
	},
}

return Items
