local Places = {
	-- The part in a slot that its item floats at, holding the place prompt and the billboard
	SLOT_PART = "Slot_Place",
	-- On each stage, the name of the place whose slide it's on (see StageService)
	STAGE_PLACE_ATTRIBUTE = "Place",
}

local function isPlace(instance: Instance): boolean
	return instance:IsA("Folder") and instance.Name:match("^Place%d+$") ~= nil
end

-- Any Workspace folder named Place<N> is a claimable place
function Places.GetAll(): { Folder }
	local places = {}
	for _, child in workspace:GetChildren() do
		if isPlace(child) then
			table.insert(places, child)
		end
	end
	return places
end

-- The place an instance is part of, if any
function Places.Find(instance: Instance): Folder?
	local current = instance.Parent
	while current and current ~= workspace do
		if current.Parent == workspace and isPlace(current) then
			return current :: Folder
		end
		current = current.Parent
	end
	return nil
end

-- A Model in a place with a SlotNumber attribute holds one item, whatever it's called. Slots are
-- bought floor by floor, in SlotNumber order (1, 2, 3, ...), and saves remember them by their floor
-- and number, so every slot on a floor needs a number of its own. Each floor counts from 1
function Places.IsSlot(instance: Instance): boolean
	local place = instance.Parent
	return instance:IsA("Model")
		and typeof(instance:GetAttribute("SlotNumber")) == "number"
		and place ~= nil
		and place.Parent == workspace
		and isPlace(place)
end

function Places.GetSlotNumber(slot: Model): number
	return slot:GetAttribute("SlotNumber") :: number
end

-- The floor the slot is on, from its Floor attribute (see SlotService). Floor 1 without one
function Places.GetSlotFloor(slot: Model): number
	local floor = slot:GetAttribute("Floor")
	return if typeof(floor) == "number" then floor else 1
end

-- The slot's key in saves. Text, since saved tables can't have gaps in number keys. A later floor's
-- keys start with the floor, like "2-5", and floor 1's are just the number, as they were before there
-- were floors
function Places.GetSlotKey(slot: Model): string
	local number = tostring(Places.GetSlotNumber(slot))
	local floor = Places.GetSlotFloor(slot)
	return if floor > 1 then `{floor}-{number}` else number
end

-- What the slot costs on the sign, from its Price attribute. Without one it's free from the start
function Places.GetSlotPrice(slot: Model): number
	local price = slot:GetAttribute("Price")
	return if typeof(price) == "number" then price else 0
end

-- Roll stands are Models named RollStand_<number> in a place. Stand 1 is built into the place, and
-- the rest are copied in on markers (see RollService). A place's owner has the first ones, as many
-- as their Roll Slots upgrade gives
function Places.GetStandName(number: number): string
	return `RollStand_{number}`
end

-- The stand's number, or nil if the instance isn't a stand
function Places.GetStandNumber(instance: Instance): number?
	local number = if instance:IsA("Model") then instance.Name:match("^RollStand_(%d+)$") else nil
	return if number then tonumber(number) else nil
end

-- Floor by floor in SlotNumber order, which is the order they're bought in
function Places.GetSlots(place: Folder): { Model }
	local slots = {}
	for _, child in place:GetChildren() do
		if Places.IsSlot(child) then
			table.insert(slots, child :: Model)
		end
	end
	table.sort(slots, function(a, b)
		local aFloor, bFloor = Places.GetSlotFloor(a), Places.GetSlotFloor(b)
		if aFloor ~= bFloor then
			return aFloor < bFloor
		end
		return Places.GetSlotNumber(a) < Places.GetSlotNumber(b)
	end)
	return slots
end

-- Whether a position is in the place's base: over its ground (BaseMin and BaseMax, see PlaceService),
-- up to EDGE_MARGIN studs past its edge on a lip or a ledge, and not fallen more than FALL_DEPTH below
-- the top of it. Without its box the base can't be measured, so everywhere counts as in it
local EDGE_MARGIN = 2 -- Studs
local FALL_DEPTH = 12 -- Studs

function Places.IsInBase(place: Folder, position: Vector3): boolean
	local low, high = place:GetAttribute("BaseMin"), place:GetAttribute("BaseMax")
	if typeof(low) ~= "Vector3" or typeof(high) ~= "Vector3" then
		return true
	end
	return position.X >= low.X - EDGE_MARGIN
		and position.X <= high.X + EDGE_MARGIN
		and position.Z >= low.Z - EDGE_MARGIN
		and position.Z <= high.Z + EDGE_MARGIN
		and position.Y >= high.Y - FALL_DEPTH
end

-- The slide is built of stages, Models in Workspace named Stage<N>, one after another down it
function Places.IsStage(instance: Instance): boolean
	return instance:IsA("Model") and instance.Parent == workspace and instance.Name:match("^Stage%d+$") ~= nil
end

return Places
