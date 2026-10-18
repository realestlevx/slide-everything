local Places = {
	-- The part in a slot that its item floats at, holding the place prompt and the billboard
	SLOT_PART = "Slot_Place",
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
-- bought in SlotNumber order (1, 2, 3, ...) and saves remember them by it, so every slot in a place
-- needs a number of its own. Later floors' slots just carry on counting
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

-- The slot's key in saves. Text, since saved tables can't have gaps in number keys
function Places.GetSlotKey(slot: Model): string
	return tostring(Places.GetSlotNumber(slot))
end

-- What the slot costs on the sign, from its Price attribute. Without one it's free from the start
function Places.GetSlotPrice(slot: Model): number
	local price = slot:GetAttribute("Price")
	return if typeof(price) == "number" then price else 0
end

-- In SlotNumber order, which is the order they're bought in
function Places.GetSlots(place: Folder): { Model }
	local slots = {}
	for _, child in place:GetChildren() do
		if Places.IsSlot(child) then
			table.insert(slots, child :: Model)
		end
	end
	table.sort(slots, function(a, b)
		return Places.GetSlotNumber(a) < Places.GetSlotNumber(b)
	end)
	return slots
end

return Places
