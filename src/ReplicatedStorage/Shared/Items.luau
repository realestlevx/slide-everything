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
	-- Items rarer than Common roll at exactly these odds. The Common items share whatever's left, so
	-- their stands show better odds than written when the rest don't add up to 100%. Neither, or 0,
	-- means it never rolls. Luck doesn't change these; it changes what a roll lands on (see Rolling.Pick)
	Chance: number?,
	OneIn: number?,
	-- How luck changes this item's chance: it's multiplied by the luck to this power. 1 (or none) is
	-- luck times the chance, 2 is luck squared, 0 leaves it alone and -1 divides it by the luck, so
	-- luck pushes the item out. Every chance is then scaled back to add up to 100% (see Rolling.Pick)
	LuckPower: number?,
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

-- Prices, odds and earnings follow the economy sheet, its spots filled in order within each rarity
-- (a rarity's later spots wait for more items). The Hyperlaser has no spot there, so it's a third
-- Mythic a step above the Diamond, as the Diamond is above the Lightsaber
local Items: { [string]: Item } = {
	ToyCar = {
		Id = "ToyCar",
		Name = "Toy Car",
		Icon = 115762315554217,
		Rarity = "Common",
		OneIn = 3,
		LuckPower = -1,
		Price = 100,
		MoneyPerSecond = 12,
		BaseMoneyPerStud = 1,
		MeshName = "ToyCar",
	},
	Bread = {
		Id = "Bread",
		Name = "Bread",
		Icon = 126948471423300,
		Rarity = "Common",
		OneIn = 5,
		LuckPower = -1,
		Price = 400,
		MoneyPerSecond = 14,
		BaseMoneyPerStud = 1,
		MeshName = "Bread",
	},
	Phone = {
		Id = "Phone",
		Name = "Phone",
		Icon = 71237800789095,
		Rarity = "Uncommon",
		OneIn = 45,
		LuckPower = 1,
		Price = 38000,
		MoneyPerSecond = 120,
		BaseMoneyPerStud = 2,
		MeshName = "Phone",
	},
	Controller = {
		Id = "Controller",
		Name = "Controller",
		Icon = 112844902116541,
		Rarity = "Rare",
		OneIn = 600,
		LuckPower = 1.2,
		Price = 500000,
		MoneyPerSecond = 839,
		BaseMoneyPerStud = 5,
		MeshName = "Controller",
	},
	RubiksCube = {
		Id = "RubiksCube",
		Name = "Rubik's Cube",
		Icon = 133035680603276,
		Rarity = "Rare",
		OneIn = 960,
		LuckPower = 1.2,
		Price = 860000,
		MoneyPerSecond = 1260,
		BaseMoneyPerStud = 8,
		MeshName = "RubiksCube",
	},
	CartoonCatfish = {
		Id = "CartoonCatfish",
		Name = "Catfish",
		Icon = 118233477633149,
		Rarity = "Epic",
		OneIn = 5000,
		LuckPower = 1.4,
		Price = 2000000,
		MoneyPerSecond = 3150,
		BaseMoneyPerStud = 12,
		MeshName = "CartoonCatfish",
	},
	Slide = {
		Id = "Slide",
		Name = "Slide",
		Icon = 112614433925436,
		Rarity = "Legendary",
		OneIn = 70000,
		LuckPower = 1.6,
		Price = 14000000,
		MoneyPerSecond = 39430,
		BaseMoneyPerStud = 30,
		MeshName = "Slide",
	},
	D20 = {
		Id = "D20",
		Name = "D20",
		Icon = 127955549258628,
		Rarity = "Legendary",
		OneIn = 96000,
		LuckPower = 1.6,
		Price = 26000000,
		MoneyPerSecond = 52000,
		BaseMoneyPerStud = 45,
		MeshName = "D20",
	},
	Amulet = {
		Id = "Amulet",
		Name = "Amulet",
		Icon = 83477652107290,
		Rarity = "Legendary",
		OneIn = 112000,
		LuckPower = 1.6,
		Price = 36000000,
		MoneyPerSecond = 80000,
		BaseMoneyPerStud = 60,
		MeshName = "Amulet",
	},
	Lightsaber = {
		Id = "Lightsaber",
		Name = "Lightsaber",
		Icon = 130835982359444,
		Rarity = "Mythic",
		OneIn = 1700000,
		LuckPower = 1.8,
		Price = 550000000,
		MoneyPerSecond = 240000,
		BaseMoneyPerStud = 100,
		MeshName = "Lightsaber",
	},
	Diamond = {
		Id = "Diamond",
		Name = "Diamond",
		Icon = 87959573635126,
		Rarity = "Mythic",
		OneIn = 2000000,
		LuckPower = 1.8,
		Price = 2600000000,
		MoneyPerSecond = 700000,
		BaseMoneyPerStud = 120,
		MeshName = "Diamond",
	},
	HyperLaserRifle = {
		Id = "HyperLaserRifle",
		Name = "Hyperlaser",
		Icon = 95328050969656,
		Rarity = "Mythic",
		OneIn = 3000000,
		LuckPower = 1.8,
		Price = 5000000000,
		MoneyPerSecond = 1200000,
		BaseMoneyPerStud = 140,
		MeshName = "HyperLaserRifle",
	},
}

return Items
