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
	Cooldown: number?, -- Seconds after a click before the panel's button takes another, so it can't be spammed
}

-- Rounded to 3 significant digits, so the price the panel shows (like "$1.35K") is the exact price
local function roundPrice(price: number): number
	local unit = 10 ^ math.max(math.floor(math.log10(price)) - 2, 0)
	return math.round(price / unit) * unit
end

-- The given prices for the first levels above 1, then each one growth times the one before, rounded
-- as it goes like the economy sheet's: 150 > 233 > 361 > 560 > 868 > 1.35K
local function getPrices(first: { number }, growth: number, count: number): { number }
	local prices = table.clone(first)
	while #prices < count do
		table.insert(prices, roundPrice(prices[#prices] * growth))
	end
	return prices
end

-- 1x, 2x, 3x and so on up to MAX_LUCK: 300 for 2x, 437 for 3x and 765 for 4x, then 1.3x more each
-- level, about 3.7K for 10x, 190K for 25x, 130M for 50x, 92B for 75x and 65T for 100x
local MAX_LUCK = 100
local LUCK_PRICES = { 300, 437, 765 } -- What 2x, 3x and 4x cost
local LUCK_GROWTH = 1.3

local function getLuckLevels(): { Level }
	local prices = getPrices(LUCK_PRICES, LUCK_GROWTH, MAX_LUCK - 1)
	local levels: { Level } = { { Value = 1 } }
	for luck = 2, MAX_LUCK do
		table.insert(levels, { Value = luck, Price = prices[luck - 1] })
	end
	return levels
end

-- 1x, 1.1x, 1.2x and so on up to 5x. Drop pay is multiplied by it, so a drop at 5x pays 50 seconds of
-- income instead of 10. 300 for 1.1x, then 1.6x more each level: about 2K for 1.5x, 21K for 2x, 2.3M
-- for 3x, 250M for 4x and 27B for 5x. Values are made from whole tenths so they show as "1.1x", not
-- "1.1000000000000001x"
local SPEED_STEPS = 40
local SPEED_PRICE = 300 -- What 1.1x costs
local SPEED_PRICE_GROWTH = 1.6

local function getSpeedLevels(): { Level }
	local prices = getPrices({ SPEED_PRICE }, SPEED_PRICE_GROWTH, SPEED_STEPS)
	local levels: { Level } = { { Value = 1 } }
	for step = 1, SPEED_STEPS do
		table.insert(levels, { Value = (10 + step) / 10, Price = prices[step] })
	end
	return levels
end

-- 7.5s, 9s and so on up to 15s, then bigger steps up to 4 minutes: how long a drop's items slide
-- before they fade out, so how far they get. Not on the economy sheet yet, so the prices are a
-- placeholder: 500 for 9s, then 4x more each level, about 8.2M for 30s, 524M for 60s, 134B for 120s
-- and 34T for 240s
local TIME_VALUES = { 7.5, 9, 10.5, 12, 13.5, 15, 20, 25, 30, 40, 50, 60, 75, 90, 105, 120, 150, 180, 210, 240 } -- Seconds
local TIME_PRICE = 500 -- What 9s costs
local TIME_PRICE_GROWTH = 4

local function getTimeLevels(): { Level }
	local prices = getPrices({ TIME_PRICE }, TIME_PRICE_GROWTH, #TIME_VALUES - 1)
	local levels: { Level } = { { Value = TIME_VALUES[1] } }
	for index = 2, #TIME_VALUES do
		table.insert(levels, { Value = TIME_VALUES[index], Price = prices[index - 1] })
	end
	return levels
end

-- 1x, 1.1x, 1.2x and so on up to 6x. What it's gone up by is added to every multiplier wall on the
-- slide: at 1.1x a 1.1x wall pays 1.2x. Not on the economy sheet yet, so the prices are a
-- placeholder: 25K for 1.1x, then 1.5x more each level, about 971K for 2x, 57M for 3x, 3.3B for 4x,
-- 191B for 5x and 11T for 6x. Values are made from whole tenths, like Sliding Speed's
local SLIDE_STEPS = 50
local SLIDE_PRICE = 25000 -- What 1.1x costs
local SLIDE_PRICE_GROWTH = 1.5

local function getSlideLevels(): { Level }
	local prices = getPrices({ SLIDE_PRICE }, SLIDE_PRICE_GROWTH, SLIDE_STEPS)
	local levels: { Level } = { { Value = 1 } }
	for step = 1, SLIDE_STEPS do
		table.insert(levels, { Value = (10 + step) / 10, Price = prices[step] })
	end
	return levels
end

-- 1 stand, then one more each level up to 6, at the economy sheet's roll slot prices
local ROLL_SLOT_PRICES = { 800, 10000, 250000, 2000000, 51000000 } -- What stands 2 to 6 cost

local function getRollSlotLevels(): { Level }
	local levels: { Level } = { { Value = 1 } }
	for index, price in ROLL_SLOT_PRICES do
		table.insert(levels, { Value = index + 1, Price = price })
	end
	return levels
end

local SignUpgrades = {
	Upgrades = {
		-- How many roll stands a pull of the lever fills; see RollService. Each new stand is shown off
		-- by StandUnlockController, which takes about as long as the cooldown
		RollSlots = {
			Frame = "Rolls_Frame",
			Suffix = "",
			Levels = getRollSlotLevels(),
			Cooldown = 1.5,
		},
		-- Moves what rolls up the odds, fading out the items too common for it; see Rolling.Pick
		Luck = {
			Frame = "Luck_Frame",
			Suffix = "x",
			Levels = getLuckLevels(),
		},
		-- Multiplies drop pay, and how fast items slide; see Drops.GetPay and DropController
		SlideSpeed = {
			Frame = "Speed_Frame",
			Suffix = "x",
			Levels = getSpeedLevels(),
		},
		-- Seconds a drop lasts; see DropController
		SlideTime = {
			Frame = "Time_Frame",
			Suffix = "s",
			Levels = getTimeLevels(),
		},
		-- Raises every multiplier wall's multiplier, for this player only; see Drops.GetMultiplier
		Slide = {
			Frame = "Slide_Frame",
			Suffix = "x",
			Levels = getSlideLevels(),
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
