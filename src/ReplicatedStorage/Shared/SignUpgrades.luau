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

local MAX_LUCK = 100
local LUCK_PRICE = 10000 -- What 2x costs
local LUCK_GROWTH = 1.2 -- Each level costs this much more again on top of the (N - 1)² below

-- Rounded to 2 significant digits, so the price the panel shows (like "$3.5M") is the exact price
local function roundPrice(price: number): number
	local unit = 10 ^ math.max(math.floor(math.log10(price)) - 1, 0)
	return math.round(price / unit) * unit
end

-- 1x, 2x, 3x and so on up to MAX_LUCK. Going up to Nx costs
-- LUCK_PRICE * (N - 1)² * LUCK_GROWTH^(N - 2): 10K for 2x, 3.5M for 10x, 380M for 25x, 150B for 50x,
-- 33T for 75x and 5.6Qa for 100x
local function getLuckLevels(): { Level }
	local levels: { Level } = { { Value = 1 } }
	for luck = 2, MAX_LUCK do
		local price = LUCK_PRICE * (luck - 1) ^ 2 * LUCK_GROWTH ^ (luck - 2)
		table.insert(levels, { Value = luck, Price = roundPrice(price) })
	end
	return levels
end

local SignUpgrades = {
	Upgrades = {
		-- Multiplies every item's roll chance; see Rolling.Pick
		Luck = {
			Frame = "Luck_Frame",
			Suffix = "x",
			Levels = getLuckLevels(),
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
