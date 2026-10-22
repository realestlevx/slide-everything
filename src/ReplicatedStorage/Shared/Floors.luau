-- Floors above a place's first, each with slots of its own. Once every slot on a player's floors is
-- bought, the Increase Slots sign sells them the next floor instead (see SlotService). Floor <N> is a
-- copy of the Floor<N> model in ServerStorage, built where the place's Floor<N>_Position part is, and
-- the markers for its slots sit in the place's Floor<N>_Slot_Positions folder
local Floors = {
	-- What each floor costs, from the economy sheet. Everyone has floor 1 from the start. A floor
	-- needs its model and its marker to be sold
	Prices = {
		[2] = 700000,
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

return Floors
