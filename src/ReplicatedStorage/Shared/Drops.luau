local Items = require(script.Parent.Items)
local Upgrades = require(script.Parent.Upgrades)

-- Dropping the slotted items down the slide. Items slide until the drop's time is up (the owner's
-- Sliding Time upgrade), and a drop pays in seconds of each item's own income, so it's worth the same
-- next to the slots whatever the item, its level or how far the player is: every stud an item gets
-- down the slide pays STUD_SECONDS of its income. A multiplier wall on the slide multiplies what
-- every stud past it pays, not what was made before it, for the items that touch it. Every wall an
-- item goes through raises the ones after it by WALL_GROWTH, for that item, so the walls it misses
-- cost it
local Drops = {
	STUD_SECONDS = 0.05, -- Items get about 200 studs with no upgrades, which pays 10 seconds
	COOLDOWN = 10, -- Seconds from the start of one drop to the next
	MAX_PILE = 50, -- Finished items shown piled on the collect pad. Older ones still count, just unseen
	-- Studs per second items slide at, before any Sliding Speed upgrade. The upgrade raises it by
	-- SPEED_SHARE of its own rise, so there's still time to steer, and each stud pays the rest: 3x
	-- slides at 2x, and each stud pays 1.5x; 5x slides at 3x, and each stud pays 1.67x
	SLIDE_SPEED = 30,
	SPEED_SHARE = 0.5,
	MULTIPLIER_ATTRIBUTE = "Multiplier", -- On the walls across the slide
	WALL_GROWTH = 0.1, -- Added to every wall's multiplier for each one the item's gone through
	-- A wall with SideToSide on glides across the slide and back, from MoveLeft studs left of where
	-- it was built to MoveRight studs right of it, as seen looking down the slide
	SIDE_TO_SIDE_ATTRIBUTE = "SideToSide",
	MOVE_LEFT_ATTRIBUTE = "MoveLeft",
	MOVE_RIGHT_ATTRIBUTE = "MoveRight",
	-- Studs per second it averages over a trip. A wall's own MoveSpeed attribute, if it has one, is
	-- used instead
	MOVE_SPEED_ATTRIBUTE = "MoveSpeed",
	MOVE_SPEED = 20,
}

-- A multiplier wall, by how far down the slide it is
export type Wall = {
	Along: number, -- Studs
	Multiplier: number, -- Before WALL_GROWTH for the walls the item went through first
}

function Drops.IsWall(instance: Instance): boolean
	return instance:IsA("BasePart") and typeof(instance:GetAttribute(Drops.MULTIPLIER_ATTRIBUTE)) == "number"
end

-- A number attribute on the wall, no less than 0, and 0 without one
local function getPositive(wall: BasePart, name: string): number
	local value = wall:GetAttribute(name)
	return if typeof(value) == "number" then math.max(value, 0) else 0
end

-- Studs to the right of where it was built, looking down the slide, that a wall is at this time
-- (workspace:GetServerTimeNow()). It's set by the server's clock, so every client sees it in the
-- same spot, and the server can work out where it was too. 0 for a wall that stays still
function Drops.GetWallSide(wall: BasePart, time: number): number
	if wall:GetAttribute(Drops.SIDE_TO_SIDE_ATTRIBUTE) ~= true then
		return 0
	end
	local left = getPositive(wall, Drops.MOVE_LEFT_ATTRIBUTE)
	local span = left + getPositive(wall, Drops.MOVE_RIGHT_ATTRIBUTE)
	local speed = getPositive(wall, Drops.MOVE_SPEED_ATTRIBUTE)
	if speed == 0 then
		speed = Drops.MOVE_SPEED
	end
	if span == 0 then
		return 0
	end
	-- Across and back is one turn. How far it is from its left end follows the cosine of the turn, so
	-- it slows into each end, and the turn is counted from where it was built
	local period = 2 * span / speed
	local turn = math.acos(1 - 2 * left / span) + time % period / period * 2 * math.pi
	return span * (1 - math.cos(turn)) / 2 - left
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

-- Rounded to hundredths, so a multiplier shows as "1.4x", not "1.4000000000000001x"
local function round(multiplier: number): number
	return math.round(multiplier * 100) / 100
end

-- What a multiplier wall pays for a player, its Multiplier attribute plus what their Slide upgrade
-- (see SignUpgrades) has gone up by: at Slide 1.3x a 1.1x wall pays 1.4x. Plus WALL_GROWTH for each
-- of the walls (hits) the item went through before it
function Drops.GetMultiplier(wall: BasePart, slide: number, hits: number): number
	local multiplier = wall:GetAttribute(Drops.MULTIPLIER_ATTRIBUTE) :: number
	return round(multiplier + slide - 1 + hits * Drops.WALL_GROWTH)
end

-- Adds the part to walls if it's a multiplier wall down the slide from start, keeping them nearest
-- first, as Measure needs them. Slide is the owner's Slide upgrade
function Drops.AddWall(walls: { Wall }, part: BasePart, start: Vector3, direction: Vector3, slide: number)
	local along = (part.Position - start):Dot(direction)
	if not Drops.IsWall(part) or along <= 0 then
		return
	end
	local index = #walls + 1
	while index > 1 and walls[index - 1].Along > along do
		index -= 1
	end
	table.insert(walls, index, { Along = along, Multiplier = Drops.GetMultiplier(part, slide, 0) })
end

-- A run that got distance studs down the slide, as studs at 1x: each stud counts as many times as
-- the last of the walls before it multiplies. Walls are the ones the item touched, and only count
-- once it's got as far as them. Each multiplies by WALL_GROWTH more for every one of them before it.
-- Also the multiplier it ended at, and how many of the walls it passed multiply at all
function Drops.Measure(walls: { Wall }, distance: number): (number, number, number)
	local paid, from, multiplier, passed = 0, 0, 1, 0
	for index, wall in walls do
		if wall.Along > distance then
			break
		end
		paid += (wall.Along - from) * multiplier
		from, multiplier = wall.Along, round(wall.Multiplier + (index - 1) * Drops.WALL_GROWTH)
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
