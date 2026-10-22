local Items = require(script.Parent.Items)
local Upgrades = require(script.Parent.Upgrades)

-- Dropping the slotted items down the slide. Items slide until the drop's time is up (the owner's
-- Sliding Time upgrade), and a drop pays in seconds of each item's own income, so it's worth the same
-- next to the slots whatever the item, its level or how far the player is: every stud an item gets
-- down the slide pays STUD_SECONDS of its income. A multiplier wall across the slide multiplies what
-- every stud past it pays, not what was made before it
local Drops = {
	STUD_SECONDS = 0.05, -- Items get about 200 studs with no upgrades, which pays 10 seconds
	COOLDOWN = 10, -- Seconds from the start of one drop to the next
	MAX_PILE = 50, -- Finished items shown piled on the collect pad. Older ones still count, just unseen
	-- Studs per second items slide at, before any Sliding Speed upgrade. The upgrade raises it by
	-- SPEED_SHARE of its own rise, so there's still time to steer, and each stud pays the rest: 3x
	-- slides at 2x, and each stud pays 1.5x
	SLIDE_SPEED = 30,
	SPEED_SHARE = 0.5,
	MULTIPLIER_ATTRIBUTE = "Multiplier", -- On the walls across the slide
}

-- A multiplier wall, by how far down the slide it is
export type Wall = {
	Along: number, -- Studs
	Multiplier: number,
}

function Drops.IsWall(instance: Instance): boolean
	return instance:IsA("BasePart") and typeof(instance:GetAttribute(Drops.MULTIPLIER_ATTRIBUTE)) == "number"
end

-- Studs per second items are held to down the slide, at this Sliding Speed (see SignUpgrades)
function Drops.GetSlideSpeed(speed: number): number
	return Drops.SLIDE_SPEED * (1 + (speed - 1) * Drops.SPEED_SHARE)
end

-- Where the way down a place's slide is measured from, the middle of the floor its items drop
-- through, and which way the slide runs across the ground, toward the floor's -X side
function Drops.GetSlideLine(floor: BasePart): (Vector3, Vector3)
	local direction = -floor.CFrame.RightVector
	return floor.Position, Vector3.new(direction.X, 0, direction.Z).Unit
end

-- Adds the part to walls if it's a multiplier wall down the slide from start, keeping them nearest
-- first, as Measure needs them
function Drops.AddWall(walls: { Wall }, part: BasePart, start: Vector3, direction: Vector3)
	local along = (part.Position - start):Dot(direction)
	if not Drops.IsWall(part) or along <= 0 then
		return
	end
	local index = #walls + 1
	while index > 1 and walls[index - 1].Along > along do
		index -= 1
	end
	table.insert(walls, index, { Along = along, Multiplier = part:GetAttribute(Drops.MULTIPLIER_ATTRIBUTE) :: number })
end

-- A run that got distance studs down the slide, as studs at 1x: each stud counts as many times as
-- the last wall before it multiplies. Also the multiplier it ended at, and how many of the walls it
-- passed multiply at all
function Drops.Measure(walls: { Wall }, distance: number): (number, number, number)
	local paid, from, multiplier, passed = 0, 0, 1, 0
	for _, wall in walls do
		if wall.Along > distance then
			break
		end
		paid += (wall.Along - from) * multiplier
		from, multiplier = wall.Along, wall.Multiplier
		if multiplier > 1 then
			passed += 1
		end
	end
	return paid + (distance - from) * multiplier, multiplier, passed
end

-- What an item earns for its run, from the studs at 1x that Measure gives and the owner's Sliding Speed
function Drops.GetPay(item: Items.Item, level: number, paidDistance: number, speed: number): number
	local perStud = speed * Drops.SLIDE_SPEED / Drops.GetSlideSpeed(speed)
	return Upgrades.GetMoneyPerSecond(item, level) * Drops.STUD_SECONDS * paidDistance * perStud
end

return Drops
