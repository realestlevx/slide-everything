local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local ItemModel = require(ReplicatedStorage.Shared.ItemModel)

local BOB_HEIGHT = 0.25 -- Studs above and below the center
local BOB_SPEED = math.pi -- Radians per second, one full bob every 2 seconds
local TURN_SPEED = math.pi / 2 -- Radians per second, one full turn every 4 seconds

local floating: { [BasePart]: CFrame } = {} -- Item -> its resting CFrame
-- Items that keep their bottom where it is as they grow or shrink -> how tall they were when they
-- started floating
local grounded: { [BasePart]: number } = {}
-- Seconds between moves, which Fast Mode sets (see SetInterval). 0 moves them every frame
local interval = 0
local sinceMove = 0

local FloatController = {}

-- Floating is local only. One shared clock drives every item, so a new item picks up
-- the current height and turn instead of starting over
local function getFloatCFrame(rest: CFrame, now: number): CFrame
	local offset = Vector3.new(0, math.sin(now * BOB_SPEED) * BOB_HEIGHT, 0)
	local turn = CFrame.Angles(0, -now * TURN_SPEED, 0) -- Negative Y turns clockwise seen from above
	return CFrame.new(rest.Position + offset) * turn * rest.Rotation
end

-- Half of what the item has grown by since it started floating, so its middle rises that much
-- and its bottom stays put
local function getLift(item: BasePart, rest: CFrame): number
	local height = grounded[item]
	return if height then (ItemModel.GetHeight(rest.Rotation, item.Size) - height) / 2 else 0
end

-- A hidden item stays where it is, and picks up the shared clock again once it's back
local function updateFloating(dt: number)
	sinceMove += dt
	if sinceMove < interval then
		return
	end
	sinceMove = 0
	local now = os.clock()
	for item, rest in floating do
		if not item.Parent then
			floating[item] = nil
			grounded[item] = nil
		elseif not ItemModel.IsHidden(item) then
			item.CFrame = getFloatCFrame(rest, now) + Vector3.yAxis * getLift(item, rest)
		end
	end
end

-- Where an item resting at rest is floating right now, for things that have to meet one in the air
function FloatController.GetCFrame(rest: CFrame): CFrame
	return getFloatCFrame(rest, os.clock())
end

-- Bobs and turns the item around where it is now, until it's removed. With keepBottom, its bottom
-- stays where it is now as it's resized, so an item that grows rises out of its slot instead of
-- sinking into it. Applied right away so a new item never shows a frame at its resting turn
function FloatController.Float(item: BasePart, keepBottom: boolean?)
	floating[item] = item.CFrame
	grounded[item] = if keepBottom then ItemModel.GetHeight(item.CFrame.Rotation, item.Size) else nil
	item.CFrame = getFloatCFrame(item.CFrame, os.clock())
end

-- Floating items move this many seconds apart instead of every frame, for Fast Mode. 0 for every frame
function FloatController.SetInterval(seconds: number)
	interval = seconds
end

function FloatController.Start()
	RunService.Heartbeat:Connect(updateFloating)
end

return FloatController
