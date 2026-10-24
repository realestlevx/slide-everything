-- The row of items along the bottom of the screen. Items kept in it are picked up with the number
-- keys; the rest of the items out of slots wait in the backpack
local Hotbar = {
	SIZE = 9, -- Positions, one for each of the keys 1 to 9
}

-- Whether a position sent by a client is one of the hotbar's
function Hotbar.IsPosition(position: any): boolean
	return typeof(position) == "number" and position % 1 == 0 and position >= 1 and position <= Hotbar.SIZE
end

return Hotbar
