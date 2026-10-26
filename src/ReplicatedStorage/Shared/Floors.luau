-- Floors above a place's first, each with slots of its own. Once every slot on a player's floors is
-- bought, the Increase Slots sign sells them the next floor instead (see SlotService). Floor <N> is a
-- copy of the Floor<N> model in ServerStorage, built where the place's Floor<N>_Position part is, and
-- the markers for its slots sit in the place's Floor<N>_Slot_Positions folder. A place without them
-- gets them in the same spot as a place that has them, so they only need to be in one
local Floors = {
	-- What each floor costs, from the economy sheet. Everyone has floor 1 from the start. A floor
	-- needs its model and its marker to be sold. Each floor's slots climb evenly from its own price
	-- to the next floor's: floor 1's last ones go $85k to $400k before floor 2's $700k, and floor 2's
	-- go $1M to $42M (about 1.45x each, its first comes free with it) toward floor 3's $61M
	Prices = {
		[2] = 700000,
		[3] = 61000000,
	} :: { [number]: number },
	-- For a floor whose slot markers are left as copies of an earlier floor's prices: its slots cost
	-- those times this instead. Floor 2's markers carry their own prices, so it has none. Floor 3's
	-- are floor 2's, and 87x (its price over floor 2's) puts them $87M to $3.65B, as far above floor
	-- 3's price as floor 2's are above its own
	SlotPriceMultipliers = {
		[3] = 87,
	} :: { [number]: number },
}

-- The floor's model in ServerStorage, and its copy in a place once it's built
function Floors.GetName(number: number): string
	return `Floor{number}`
end

-- The part in a place that its copy of the floor is built on: the model's pivot goes where the part is,
-- turned from how the model sits in ServerStorage as far as the part is turned
function Floors.GetMarkerName(number: number): string
	return `Floor{number}_Position`
end

-- The part in the floor's model that the top bar's Next and Back buttons send the owner to (see
-- BaseController). Floor 1's is the place's own Spawn
function Floors.GetSpawnName(number: number): string
	return `Floor{number}Spawn`
end

-- What the sign sells the floor for, or nil if it isn't for sale
function Floors.GetPrice(number: number): number?
	return Floors.Prices[number]
end

-- What the prices on the floor's slot markers are multiplied by (see SlotService). 1 without one
function Floors.GetSlotPriceMultiplier(number: number): number
	return Floors.SlotPriceMultipliers[number] or 1
end

return Floors
