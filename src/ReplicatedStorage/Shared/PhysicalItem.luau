local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Items = require(script.Parent.Items)

local PhysicalItem = {}

-- An unanchored copy of the item's mesh with its hitbox, at the given CFrame, for physics on the
-- client that makes it. Comes with all its parts, and isn't parented yet
function PhysicalItem.Create(item: Items.Item, cframe: CFrame, physics: PhysicalProperties?): (BasePart, { BasePart })
	local copy = ReplicatedStorage.Items[item.MeshName]:Clone() :: BasePart
	local parts: { BasePart } = { copy }
	for _, descendant in copy:GetDescendants() do
		if descendant:IsA("BasePart") then
			table.insert(parts, descendant)
		end
	end

	-- Placed part by part, since welds don't carry the hitbox along before it's in the workspace
	local offsets: { [BasePart]: CFrame } = {}
	for _, part in parts do
		offsets[part] = copy.CFrame:ToObjectSpace(part.CFrame)
	end
	for _, part in parts do
		part.CFrame = cframe * offsets[part]
		part.Anchored = false
		if physics and part.CanCollide then
			part.CustomPhysicalProperties = physics
		end
	end
	return copy, parts
end

-- How the item's mesh is turned when it rests the way it was modelled, and its size
function PhysicalItem.GetShape(item: Items.Item): (CFrame, Vector3)
	local template = ReplicatedStorage.Items[item.MeshName] :: BasePart
	return template.CFrame.Rotation, template.Size
end

return PhysicalItem
