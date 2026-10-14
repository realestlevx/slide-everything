local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Items = require(ReplicatedStorage.Shared.Items)
local Places = require(ReplicatedStorage.Shared.Places)
local Rolling = require(ReplicatedStorage.Shared.Rolling)

local RollStarted = ReplicatedStorage.Remotes.RollStarted

local LEVER_ANGLE = math.rad(45) -- Pulled towards the player
local LEVER_BOUNCE_ANGLE = math.rad(-15) -- Swings back past upright before settling
local LEVER_PULL = TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
local LEVER_BOUNCE = TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local LEVER_SETTLE = TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local POP = TweenInfo.new(Rolling.POP_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local OUTCOME_FADE = TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local BOB_HEIGHT = 0.25 -- Studs above and below the center
local BOB_SPEED = math.pi -- Radians per second, one full bob every 2 seconds
local TURN_SPEED = math.pi / 2 -- Radians per second, one full turn every 4 seconds

local allItems: { Items.Item } = {}
for _, item in Items do
	table.insert(allItems, item)
end

local spinTokens: { [Folder]: number } = {} -- Bumped to stop a spin early
local previews: { [Folder]: MeshPart } = {}
local leverRestCFrames: { [BasePart]: CFrame } = {}
local floating: { [BasePart]: CFrame } = {} -- Item -> its resting CFrame

local RollController = {}

-- FindFirstChild down a path; parts may not be streamed in yet
local function find(root: Instance, ...: string): any
	local current: Instance? = root
	for _, name in { ... } do
		current = current and current:FindFirstChild(name)
	end
	return current
end

local function pullLever(place: Folder)
	local shaft = find(place, "RollTools_Model", "Lever", "Lever_Shaft")
	local base = find(place, "RollTools_Model", "Lever", "Lever_Bottom")
	local holder = find(place, "RollTools_Model", "Proximity_Holder")
	if not (shaft and base and holder) then
		return
	end

	local rest = leverRestCFrames[shaft] or shaft.CFrame
	leverRestCFrames[shaft] = rest

	-- Swing around the bottom of the shaft, along the base's long side, towards the prompt
	local pivot = rest.Position - rest.UpVector * shaft.Size.Y / 2
	local axis = base.CFrame.LookVector
	local towardsPlayer = if axis:Cross(rest.UpVector):Dot(holder.Position - pivot) >= 0 then 1 else -1

	local angle = Instance.new("NumberValue")
	angle.Changed:Connect(function(value)
		local rotation = CFrame.new(pivot) * CFrame.fromAxisAngle(axis, value * towardsPlayer) * CFrame.new(-pivot)
		shaft.CFrame = rotation * rest
	end)

	for _, step in { { LEVER_PULL, LEVER_ANGLE }, { LEVER_BOUNCE, LEVER_BOUNCE_ANGLE }, { LEVER_SETTLE, 0 } } do
		local tween = TweenService:Create(angle, step[1], { Value = step[2] })
		tween:Play()
		tween.Completed:Wait()
	end
	angle:Destroy()
end

-- Floating is local only. One shared clock drives every item, so a new item picks up
-- the current height and turn instead of starting over
local function getFloatCFrame(rest: CFrame, now: number): CFrame
	local offset = Vector3.new(0, math.sin(now * BOB_SPEED) * BOB_HEIGHT, 0)
	local turn = CFrame.Angles(0, -now * TURN_SPEED, 0) -- Negative Y turns clockwise seen from above
	return CFrame.new(rest.Position + offset) * turn * rest.Rotation
end

local function updateFloating()
	local now = os.clock()
	for item, rest in floating do
		if item.Parent then
			item.CFrame = getFloatCFrame(rest, now)
		else
			floating[item] = nil
		end
	end
end

-- Applied right away so a new item never shows a frame at its resting turn
local function startFloating(item: BasePart)
	floating[item] = item.CFrame
	item.CFrame = getFloatCFrame(item.CFrame, os.clock())
end

local function clearPreview(place: Folder)
	local preview = previews[place]
	if preview then
		preview:Destroy()
		previews[place] = nil
	end
end

local function cancelSpin(place: Folder)
	spinTokens[place] = (spinTokens[place] or 0) + 1
	clearPreview(place)
end

local function showPreview(place: Folder, item: Items.Item)
	local stand = find(place, "RollStand_1")
	local rollPlace = find(place, "RollStand_1", "Roll_Place")
	if not rollPlace then
		return
	end

	clearPreview(place)
	local preview = Rolling.CreateDisplay(item, rollPlace)
	preview.Name = "RollPreview"
	Rolling.AddHighlight(preview, Rolling.ROLLING_HIGHLIGHT)

	local fullSize = preview.Size
	preview.Size = fullSize * 0.01
	preview.Parent = stand
	previews[place] = preview
	startFloating(preview)
	TweenService:Create(preview, POP, { Size = fullSize }):Play()

	local billboard = rollPlace:FindFirstChild("Stuff_StatsDisplay")
	if billboard then
		Rolling.ShowStats(billboard, item)
	end
end

-- The server's item arrives with the outcome highlight; start it black so the owner sees it fade in
local function fadeToOutcome(item: Instance)
	local highlight: any = item:FindFirstChildOfClass("Highlight")
	if not highlight then
		return
	end

	local outcome = {}
	for property, rollingValue in Rolling.ROLLING_HIGHLIGHT do
		outcome[property] = highlight[property]
		highlight[property] = rollingValue
	end
	TweenService:Create(highlight, OUTCOME_FADE, outcome):Play()
end

local function randomFiller(previous: Items.Item?): Items.Item
	local item
	repeat
		item = allItems[math.random(#allItems)]
	until item ~= previous or #allItems == 1
	return item
end

local function spin(place: Folder, resultId: string)
	local token = (spinTokens[place] or 0) + 1
	spinTokens[place] = token

	local startTime = os.clock()
	local previous
	for step = 1, Rolling.SPIN_STEPS do
		-- Quadratic ease-out: swaps start fast and slow down until the result
		local progress = (step - 1) / (Rolling.SPIN_STEPS - 1)
		local swapTime = Rolling.SPIN_DURATION * (1 - math.sqrt(1 - progress))
		local remaining = swapTime - (os.clock() - startTime)
		if remaining > 0 then
			task.wait(remaining)
		end
		if spinTokens[place] ~= token then
			return
		end

		local item = if step == Rolling.SPIN_STEPS then Items[resultId] else randomFiller(previous)
		showPreview(place, item)
		previous = item
	end
end

function RollController.Start()
	RollStarted.OnClientEvent:Connect(function(place: Folder, resultId: string)
		task.spawn(pullLever, place)
		task.spawn(spin, place, resultId)
	end)

	RunService.Heartbeat:Connect(updateFloating)

	for _, place in Places.GetAll() do
		for _, descendant in place:GetDescendants() do
			if descendant.Name == "RolledItem" then
				startFloating(descendant)
			end
		end

		-- The server's real item takes over from the local preview (and streams in later for others)
		place.DescendantAdded:Connect(function(descendant)
			if descendant.Name == "RolledItem" then
				local wasSpinning = previews[place] ~= nil
				cancelSpin(place)
				startFloating(descendant)
				if wasSpinning then
					fadeToOutcome(descendant)
				end
			end
		end)
		place:GetAttributeChangedSignal("OwnerUserId"):Connect(function()
			cancelSpin(place)
		end)
	end
end

return RollController
