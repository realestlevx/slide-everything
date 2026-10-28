local ServerStorage = game:GetService("ServerStorage")

-- Every place is a copy of the Place model in ServerStorage, built on one of the parts in
-- Workspace.Connectors as the server starts, so a change to the base only has to be made once. The
-- model's Connector part goes where the connector is, turned as far as it is. The copy is named after
-- its connector, like Place3; a connector without a Place<N> name of its own, like a duplicated one,
-- gets the next free number. Saves don't keep which place a player had, so the numbers can change
local TEMPLATE_NAME = "Place"
local ANCHOR_NAME = "Connector"
local CONNECTORS_NAME = "Connectors"

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

function PlaceBuilder.Build()
	local template = getTemplate()
	local connectors = getConnectors()
	if not template then
		return
	end
	for name, connector in connectors do
		local copy = template:Clone()
		local anchor = copy:FindFirstChild(ANCHOR_NAME) :: BasePart
		copy:PivotTo(connector.CFrame * anchor.CFrame:ToObjectSpace(copy:GetPivot()))
		anchor:Destroy()

		-- Places are Folders, as they were when they were built by hand
		local place = Instance.new("Folder")
		place.Name = name
		for _, child in copy:GetChildren() do
			child.Parent = place
		end
		copy:Destroy()
		place.Parent = workspace
	end
end

return PlaceBuilder
