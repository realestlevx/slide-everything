local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Places = require(ReplicatedStorage.Shared.Places)

local LocalPlayer = Players.LocalPlayer
local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")

-- A BillboardGui's MaxDistance counts from the camera, which hangs back behind the character, so
-- billboards came and went with the camera. Instead, each one shows while the character is within
-- the MaxDistance it was designed with. That's kept as its Range attribute, which copies of it carry
-- along, and its MaxDistance only switches it on and off from here. Billboards without a limit are
-- left as they are
local RANGE_ATTRIBUTE = "Range"
local SHOWN_DISTANCE = math.huge
local HIDDEN_DISTANCE = 0.1 -- Studs; the camera is never this close to a billboard
local CHECK_INTERVAL = 0.1 -- Seconds between checks

local ranges: { [BillboardGui]: number } = {}
-- A place's roll stands show their billboards together, while the character is in range of any of
-- them. One by one, the back row was out of range from where players stand to roll. Stand
-- billboards -> their place
local groups: { [BillboardGui]: Instance } = {}

local BillboardRangeController = {}

local function getWorldPosition(billboard: BillboardGui): Vector3?
	local target = billboard.Adornee or billboard.Parent
	if target and target:IsA("BasePart") then
		return target.Position
	elseif target and target:IsA("Attachment") then
		return target.WorldPosition
	elseif target and target:IsA("Model") then
		return target:GetPivot().Position
	end
	return nil
end

local function getCharacterPosition(): Vector3?
	local character = LocalPlayer.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	return if root and root:IsA("BasePart") then root.Position else nil
end

-- The place whose roll stand the billboard is on, if it's on one
local function getGroup(billboard: BillboardGui): Instance?
	local current = billboard.Parent
	while current and current ~= workspace do
		if Places.GetStandNumber(current) then
			return current.Parent
		end
		current = current.Parent
	end
	return nil
end

local function isNear(billboard: BillboardGui, from: Vector3): boolean
	local position = getWorldPosition(billboard)
	return position ~= nil and (position - from).Magnitude <= ranges[billboard]
end

-- The groups with a billboard in range
local function getNearGroups(from: Vector3): { [Instance]: boolean }
	local nearGroups = {}
	for billboard, group in groups do
		if isNear(billboard, from) then
			nearGroups[group] = true
		end
	end
	return nearGroups
end

local function update(billboard: BillboardGui, from: Vector3, nearGroups: { [Instance]: boolean })
	if not getWorldPosition(billboard) then
		return
	end
	local group = groups[billboard]
	local near = if group then nearGroups[group] == true else isNear(billboard, from)
	billboard.MaxDistance = if near then SHOWN_DISTANCE else HIDDEN_DISTANCE
end

-- Every billboard is tracked as it appears. Anything that scales a model down (Model:ScaleTo scales
-- MaxDistance too) tracks its billboards first, so their range is taken at full size
function BillboardRangeController.Track(instance: Instance)
	if not instance:IsA("BillboardGui") then
		return
	end
	local range = instance:GetAttribute(RANGE_ATTRIBUTE)
	if typeof(range) ~= "number" then
		range = instance.MaxDistance
		if range == math.huge then
			return
		end
		instance:SetAttribute(RANGE_ATTRIBUTE, range)
	end
	ranges[instance] = range :: number
	groups[instance] = getGroup(instance)

	-- Right away, so a new billboard doesn't show for a moment where it shouldn't
	local from = getCharacterPosition()
	if from then
		update(instance, from, getNearGroups(from))
	end
end

function BillboardRangeController.Start()
	for _, root in { workspace, PlayerGui } do
		for _, descendant in root:GetDescendants() do
			BillboardRangeController.Track(descendant)
		end
		root.DescendantAdded:Connect(BillboardRangeController.Track)
	end

	task.spawn(function()
		while true do
			task.wait(CHECK_INTERVAL)
			for billboard in ranges do
				if not billboard.Parent then
					ranges[billboard] = nil
					groups[billboard] = nil
				end
			end
			local from = getCharacterPosition()
			if from then
				local nearGroups = getNearGroups(from)
				for billboard in ranges do
					update(billboard, from, nearGroups)
				end
			end
		end
	end)
end

return BillboardRangeController
