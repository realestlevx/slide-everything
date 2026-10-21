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
	-- Part in ReplicatedStorage.Items, which collides as a box: a MeshPart, or an invisible box with
	-- the item's meshes and effects inside it (see ItemModel)
	MeshName: string,
}

-- One item in a player's inventory. Every copy gets its own Uid, so two of the same item stay apart
export type OwnedItem = {
	Uid: string,
	Id: string, -- Key in Items
	Level: number?, -- Upgrade level, nil for items saved before upgrades (level 1)
}

-- Each rarity earns about 5x the one below it, but takes longer to earn back its price: 10s for a
-- Toy Car, up to about 4.5 min for a D20 and 6.5 min for a Lightsaber. Slots are the limit, so rarer is always worth having, and
-- the rarest can't be bought the moment they first roll. A second item in a rarity is its better
-- version: 1.5x the earnings for twice the price, and 2-2.5x rarer.
-- The chances add up to about 100%, so the odds the stands show match the ones written here
local Items: { [string]: Item } = {
	ToyCar = {
		Id = "ToyCar",
		Name = "Toy Car",
		Icon = 115762315554217,
		Rarity = "Common",
		Chance = 58,
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
		Chance = 28,
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
	RubiksCube = {
		Id = "RubiksCube",
		Name = "Rubik's Cube",
		Icon = 133035680603276,
		Rarity = "Rare",
		OneIn = 25,
		Price = 150000,
		MoneyPerSecond = 3000,
		BaseMoneyPerStud = 8,
		MeshName = "RubiksCube",
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
	D20 = {
		Id = "D20",
		Name = "D20",
		Icon = 127955549258628,
		Rarity = "Legendary",
		OneIn = 1000,
		Price = 20000000,
		MoneyPerSecond = 75000,
		BaseMoneyPerStud = 45,
		MeshName = "D20",
	},
	Lightsaber = {
		Id = "Lightsaber",
		Name = "Lightsaber",
		Icon = 0, -- TODO: the Lightsaber's icon image id
		Rarity = "Mythic",
		OneIn = 5000,
		Price = 100000000,
		MoneyPerSecond = 250000,
		BaseMoneyPerStud = 100,
		MeshName = "Lightsaber",
	},
}

return Items
