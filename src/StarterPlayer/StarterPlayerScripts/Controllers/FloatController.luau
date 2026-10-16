local RunService = game:GetService("RunService")

local BOB_HEIGHT = 0.25 -- Studs above and below the center
local BOB_SPEED = math.pi -- Radians per second, one full bob every 2 seconds
local TURN_SPEED = math.pi / 2 -- Radians per second, one full turn every 4 seconds

local floating: { [BasePart]: CFrame } = {} -- Item -> its resting CFrame

local FloatController = {}

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

-- Bobs and turns the item around where it is now, until it's removed.
-- Applied right away so a new item never shows a frame at its resting turn
function FloatController.Float(item: BasePart)
	floating[item] = item.CFrame
	item.CFrame = getFloatCFrame(item.CFrame, os.clock())
end

function FloatController.Start()
	RunService.Heartbeat:Connect(updateFloating)
end

return FloatController
