-- Upgrades bought a level at a time from the panels on a place's signs. Every player starts at
-- level 1. Each level's Value is what the upgrade is worth at that level, and its Price is what
-- going up to it costs. Saves keep the level, so the values and prices here can be changed any time
export type Level = {
	Value: number,
	Price: number?, -- Level 1 has none: everyone starts there
}

export type Upgrade = {
	Frame: string, -- The panel on a sign (a Frame) that shows and sells it
	Suffix: string, -- Shown after the value on the panel, like "1x > 2x"
	Levels: { Level },
}

local SignUpgrades = {
	Upgrades = {
		-- Multiplies every item's roll chance; see Rolling.Pick
		Luck = {
			Frame = "Luck_Frame",
			Suffix = "x",
			Levels = {
				{ Value = 1 },
				{ Value = 1.5, Price = 3000 },
				{ Value = 2, Price = 10000 },
				{ Value = 3, Price = 40000 },
				{ Value = 5, Price = 150000 },
				{ Value = 7.5, Price = 500000 },
				{ Value = 10, Price = 2000000 },
				{ Value = 15, Price = 7500000 },
				{ Value = 25, Price = 25000000 },
				{ Value = 50, Price = 100000000 },
			},
		},
	} :: { [string]: Upgrade },
}

local function getLevels(name: string): { Level }
	return SignUpgrades.Upgrades[name].Levels
end

-- Levels past the last one (from an old save, after levels were taken out) count as the last one
function SignUpgrades.GetValue(name: string, level: number): number
	local levels = getLevels(name)
	return levels[math.clamp(level, 1, #levels)].Value
end

-- What the next level costs, or nil at the top level
function SignUpgrades.GetNextPrice(name: string, level: number): number?
	local nextLevel = getLevels(name)[level + 1]
	return nextLevel and nextLevel.Price
end

-- The value the next level brings, or nil at the top level
function SignUpgrades.GetNextValue(name: string, level: number): number?
	local nextLevel = getLevels(name)[level + 1]
	return nextLevel and nextLevel.Value
end

return SignUpgrades
