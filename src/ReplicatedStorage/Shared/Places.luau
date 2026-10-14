local Places = {}

-- Any Workspace folder named Place<N> is a claimable place
function Places.GetAll(): { Folder }
	local places = {}
	for _, child in workspace:GetChildren() do
		if child:IsA("Folder") and child.Name:match("^Place%d+$") then
			table.insert(places, child)
		end
	end
	return places
end

return Places
