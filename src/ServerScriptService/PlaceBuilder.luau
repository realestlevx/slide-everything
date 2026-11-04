local ServerStorage = game:GetService("ServerStorage")

-- Every place is a copy of the Place model in ServerStorage, built on one of the parts in
-- Workspace.Connectors as the server starts, so a change to the base only has to be made once. The
-- model's Connector part goes where the connector is, turned as far as it is. The copy is named after
-- its connector, like Place3; a connector without a Place<N> name of its own, like a duplicated one,
-- gets the next free number. Saves don't keep which place a player had, so the numbers can change
local TEMPLATE_NAME = "Place"
local ANCHOR_NAME = "Connector"
local CONNECTORS_NAME = "Connectors"
-- The model is split in two. Its Layout folder holds what stays the same whatever the place looks
-- like: the signs, the slot and stand positions, the prompts and pads. That goes straight into the
-- place, as it was before the split, since that's where everything looks for it. Its Design folder
-- holds the look, like the bottoms and the decoration, and stays a folder of its own in the place, so
-- the look can be swapped without building the rest again
local LAYOUT_NAME = "Layout"
local DESIGN_NAME = "Design"
-- Other looks are folders in ServerStorage.PlaceDesigns, named after them; they can be left in
-- Workspace while they're being built. A place's Design attribute names the one it wears, and without
-- one it wears the model's own. Each look lines up with the model as it sits, or, if it has a
-- Connector part of its own, by that, marking where the model's Connector would be
local DESIGNS_NAME = "PlaceDesigns"
local DESIGN_ATTRIBUTE = "Design"

local template: Model? = nil
local designs: Instance? = nil
-- Where each place's Connector went
local anchors: { [Folder]: CFrame } = {}

local PlaceBuilder = {}

-- The model can be left in Workspace after editing it there. It's taken out before anything sees it
local function getTemplate(): Model?
	local template = ServerStorage:FindFirstChild(TEMPLATE_NAME) or workspace:FindFirstChild(TEMPLATE_NAME)
	if not (template and template:IsA("Model")) then
		warn(`ServerStorage needs a {TEMPLATE_NAME} model for the places to be built`)
		return nil
	end
	template.Parent = ServerStorage
	local anchor = template:FindFirstChild(ANCHOR_NAME)
	if not (anchor and anchor:IsA("BasePart")) then
		warn(`The {TEMPLATE_NAME} model needs a {ANCHOR_NAME} part to be built on the connectors`)
		return nil
	end
	return template
end

local function getConnectors(): { [string]: BasePart }
	local folder = workspace:FindFirstChild(CONNECTORS_NAME)
	if not folder then
		warn(`Workspace needs a {CONNECTORS_NAME} folder of parts for the places to be built on`)
		return {}
	end
	local named: { [string]: BasePart } = {}
	local unnamed: { BasePart } = {}
	for _, connector in folder:GetChildren() do
		if not connector:IsA("BasePart") then
			continue
		end
		if connector.Name:match("^Place%d+$") and not named[connector.Name] then
			named[connector.Name] = connector
		else
			table.insert(unnamed, connector)
		end
	end
	local number = 0
	for _, connector in unnamed do
		repeat
			number += 1
		until not named[`Place{number}`]
		named[`Place{number}`] = connector
	end
	-- They only mark where the places go
	folder:Destroy()
	return named
end

-- Like the model, the looks can be left in Workspace, and are taken out before anything sees them
local function getDesigns(): Instance?
	local folder = ServerStorage:FindFirstChild(DESIGNS_NAME) or workspace:FindFirstChild(DESIGNS_NAME)
	if folder then
		folder.Parent = ServerStorage
	end
	return folder
end

-- Moves everything in the folder as far as it takes `from` to `to`
local function lineUp(folder: Instance, from: CFrame, to: CFrame)
	local holder = Instance.new("Model")
	for _, child in folder:GetChildren() do
		child.Parent = holder
	end
	holder:PivotTo(to * from:ToObjectSpace(holder:GetPivot()))
	for _, child in holder:GetChildren() do
		child.Parent = folder
	end
	holder:Destroy()
end

-- Puts on the place the look its Design attribute names, in place of the one it wears
local function setDesign(place: Folder)
	local model = template :: Model
	local name = place:GetAttribute(DESIGN_ATTRIBUTE)
	local source = model:FindFirstChild(DESIGN_NAME)
	if typeof(name) == "string" and name ~= "" then
		local found = designs and designs:FindFirstChild(name)
		if found then
			source = found
		else
			warn(`ServerStorage.{DESIGNS_NAME} has no {name} design, so {place.Name} wears the {TEMPLATE_NAME} model's own`)
		end
	end
	if not source then
		return
	end

	local design = source:Clone()
	design.Name = DESIGN_NAME
	local from = (model :: any)[ANCHOR_NAME].CFrame
	local anchor = design:FindFirstChild(ANCHOR_NAME)
	if anchor and anchor:IsA("BasePart") then
		from = anchor.CFrame
		anchor:Destroy()
	end
	lineUp(design, from, anchors[place])

	local old = place:FindFirstChild(DESIGN_NAME)
	if old then
		old:Destroy()
	end
	design.Parent = place
end

function PlaceBuilder.Build()
	template = getTemplate()
	local connectors = getConnectors()
	if not template then
		return
	end
	designs = getDesigns()
	for name, connector in connectors do
		local copy = template:Clone()
		local anchor = copy:FindFirstChild(ANCHOR_NAME) :: BasePart
		copy:PivotTo(connector.CFrame * anchor.CFrame:ToObjectSpace(copy:GetPivot()))
		anchor:Destroy()

		-- Places are Folders, as they were when they were built by hand
		local place = Instance.new("Folder")
		place.Name = name
		for _, child in copy:GetChildren() do
			if child.Name == LAYOUT_NAME and child:IsA("Folder") then
				for _, part in child:GetChildren() do
					part.Parent = place
				end
			else
				child.Parent = place
			end
		end
		copy:Destroy()
		anchors[place] = connector.CFrame
		place:GetAttributeChangedSignal(DESIGN_ATTRIBUTE):Connect(function()
			setDesign(place)
		end)
		place.Parent = workspace
	end
end

return PlaceBuilder
