-- Floors above a place's first, each with slots of its own. Once every slot on a player's floors is
-- bought, the Increase Slots sign sells them the next floor instead (see SlotService). Floor <N> is a
-- copy of the Floor<N> model in ServerStorage, built where the place's Floor<N>_Position part is, and
-- the markers for its slots sit in the place's Floor<N>_Slot_Positions folder
local Floors = {
	-- What each floor costs. Everyone has floor 1 from the start. A floor needs its model and its
	-- marker to be sold. Floor 2 is priced like one more slot after floor 1's last ($15M), each of
	-- which costs about 3x the one before
	Prices = {
		[2] = 45000000,
	} :: { [number]: number },
	-- A later floor's slot markers carry copies of floor 1's prices ($100, $300, ... $15M), so its
	-- slots cost those times this instead, and the climb carries on from the floor's price rather
	-- than starting over: floor 2's second slot is $100 x 1.35M = $135M, 3x the floor (its first
	-- comes free with it), up to $20.25T for its twelfth
	SlotPriceMultipliers = {
		[2] = 1350000,
	} :: { [number]: number },
}

-- The floor's model in ServerStorage, and its copy in a place once it's built
function Floors.GetName(number: number): string
	return `Floor{number}`
end

-- The part in a place that its copy of the floor is built on: the model's pivot goes where the part is
function Floors.GetMarkerName(number: number): string
	return `Floor{number}_Position`
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
