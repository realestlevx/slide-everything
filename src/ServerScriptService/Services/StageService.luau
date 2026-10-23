local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Drops = require(ReplicatedStorage.Shared.Drops)
local Places = require(ReplicatedStorage.Shared.Places)

local DROP_FLOOR_NAME = "DropPart" -- Under a place's slots; its slide runs from there

-- Every stage is tagged with the place whose slide it's on, so clients can show its obstacles and
-- decorations to that place's owner only (see StageController). Clients can't work it out themselves,
-- since other places' DropParts may not be streamed in to them. It's the place the stage is down the
-- slide of whose slide line passes closest to it. A Place attribute set on a stage in Studio is kept
local StageService = {}

local function findPlace(stage: Model): Folder?
	local position = stage:GetPivot().Position
	local best, bestSide = nil, math.huge
	for _, place in Places.GetAll() do
		local floor = place:FindFirstChild(DROP_FLOOR_NAME)
		if floor and floor:IsA("BasePart") then
			local start, direction = Drops.GetSlideLine(floor)
			local offset = position - start
			offset = Vector3.new(offset.X, 0, offset.Z)
			local along = offset:Dot(direction)
			local side = (offset - direction * along).Magnitude
			if along > 0 and side < bestSide then
				best, bestSide = place, side
			end
		end
	end
	return best
end

local function tag(instance: Instance)
	if not Places.IsStage(instance) or instance:GetAttribute(Places.STAGE_PLACE_ATTRIBUTE) ~= nil then
		return
	end
	local place = findPlace(instance :: Model)
	if place then
		instance:SetAttribute(Places.STAGE_PLACE_ATTRIBUTE, place.Name)
	else
		warn(`{instance.Name} isn't down any place's slide, so nobody sees its obstacles and decorations`)
	end
end

function StageService.Start()
	for _, child in workspace:GetChildren() do
		tag(child)
	end
	workspace.ChildAdded:Connect(tag)
end

return StageService
