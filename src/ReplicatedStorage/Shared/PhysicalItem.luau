local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ItemModel = require(script.Parent.ItemModel)
local Items = require(script.Parent.Items)

local PhysicalItem = {}

-- An unanchored copy of the item, at the given CFrame and share of its own size (full size if not
-- given), for physics on the client that makes it. The parts inside it are welded on and only show;
-- the outer part is what collides. Comes with all its parts, and isn't parented yet
function PhysicalItem.Create(
	item: Items.Item,
	cframe: CFrame,
	physics: PhysicalProperties?,
	scale: number?
): (BasePart, { BasePart })
	local copy = ReplicatedStorage.Items[item.MeshName]:Clone() :: BasePart
	ItemModel.Prepare(copy)
	if scale then
		ItemModel.SetScale(copy, scale)
	end
	ItemModel.PivotTo(copy, cframe)
	local parts = ItemModel.GetParts(copy)
	for _, part in parts do
		part.Anchored = false
		if physics and part.CanCollide then
			part.CustomPhysicalProperties = physics
		end
	end
	return copy, parts
end

-- How the item is turned when it rests the way it was modelled, and its size
function PhysicalItem.GetShape(item: Items.Item): (CFrame, Vector3)
	local template = ReplicatedStorage.Items[item.MeshName] :: BasePart
	return template.CFrame.Rotation, template.Size
end

return PhysicalItem
