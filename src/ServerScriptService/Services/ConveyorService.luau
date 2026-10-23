-- Conveyor belts carry whatever stands on them toward their front, the way their arrows scroll. A
-- belt is an anchored part named ConveyorBelt anywhere in Workspace: in each belt model, the one on
-- top that's stood on. It never moves itself; an anchored part given a velocity pushes along whatever
-- touches it. Turn a belt round to send it the other way, and give it a Speed attribute (studs per
-- second) to change how fast it goes
local BELT_NAME = "ConveyorBelt"
local SPEED_ATTRIBUTE = "Speed"
local DEFAULT_SPEED = 60 -- Studs per second, nearly four times walking speed

local ConveyorService = {}

local function setUp(instance: Instance)
	if not (instance:IsA("BasePart") and instance.Name == BELT_NAME and instance.Anchored) then
		return
	end
	local speed = instance:GetAttribute(SPEED_ATTRIBUTE)
	instance.AssemblyLinearVelocity = instance.CFrame.LookVector
		* (if typeof(speed) == "number" then speed else DEFAULT_SPEED)
end

function ConveyorService.Start()
	for _, descendant in workspace:GetDescendants() do
		setUp(descendant)
	end
end

return ConveyorService
