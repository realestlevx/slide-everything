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

-- A Model in a place named Slot, optionally numbered (Slot_2), holds one item. Saves remember
-- items by slot name, so every slot in a place needs a name of its own
function Places.IsSlot(instance: Instance): boolean
	local place = instance.Parent
	return instance:IsA("Model")
		and instance.Name:match("^Slot_?%d*$") ~= nil
		and place ~= nil
		and place.Parent == workspace
		and isPlace(place)
end

function Places.GetSlots(place: Folder): { Model }
	local slots = {}
	for _, child in place:GetChildren() do
		if Places.IsSlot(child) then
			table.insert(slots, child)
		end
	end
	return slots
end

return Places
