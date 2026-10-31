local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")

local Drops = require(ReplicatedStorage.Shared.Drops)
local Floors = require(ReplicatedStorage.Shared.Floors)
local Items = require(ReplicatedStorage.Shared.Items)
local PhysicalItem = require(ReplicatedStorage.Shared.PhysicalItem)
local Places = require(ReplicatedStorage.Shared.Places)
local SignUpgrades = require(ReplicatedStorage.Shared.SignUpgrades)
local Upgrades = require(ReplicatedStorage.Shared.Upgrades)

local CollectController = require(script.Parent.CollectController)
local HudController = require(script.Parent.HudController)
local MultiplierWallController = require(script.Parent.MultiplierWallController)
local PromptController = require(script.Parent.PromptController)
local SlotController = require(script.Parent.SlotController)

local DropResult = ReplicatedStorage.Remotes.DropResult
local LocalPlayer = Players.LocalPlayer

local DROP_BUTTON_NAME = "Drop_Button" -- Model in a place holding the prompt that drops its items
-- The floor under a place's slots, and under each built floor's slots, which opens for the items to fall through
local DROP_FLOOR_NAME = "DropPart"
-- The parts the slide's made of, below the funnel. Items can be steered, and are pulled into the pack,
-- once they're over one; until then they just fall
local SLIDE_NAME = "Ground_Slide"
-- Walls the items slide along without losing any speed down the slide, like the ones that funnel the
-- outer places' items in toward the middle. Blocks, at any angle
local BARRIER_NAME = "Slippery_Barrier"
-- Walls round each place's slots that keep its items in as they fall. Solid on this client through
-- its drop only: a part that can collide also blocks raycasts, like the prompts' line of sight, and
-- players walk among the slots in between
local ITEM_BARRIER_NAME = "Items_Barrier"
-- Parts across the end of the slide. An item that touches one finishes there, before its time's up
local FINISH_NAME = "Finish"
local SLOT_ITEM_NAME = "SlotItem"

-- Dropped items barely grip, and their grip outweighs the slide's, so they slide down even the
-- gentlest ramp. The slide speed (see Drops.GetSlideSpeed) then keeps them from going faster than
-- that down the slide; falling isn't slowed
local ITEM_PHYSICS = PhysicalProperties.new(0.7, 0.05, 0.2, 100, 1)
-- Studs per second sideways while the player steers, times their Sliding Speed upgrade and
-- STEER_MULTIPLIER, so a faster pack cuts across more sharply and still makes the gates that come at
-- it sooner: 22.5 at 1x, 67.5 at 3x and 112.5 at 5x. The pack's pull grows just with the slide speed,
-- so it holds together just as tightly however fast it slides
local STEER_SPEED = 15
local STEER_MULTIPLIER = 1.5
-- On the slide, items grip sideways like sleds: they slide where they're steered and stop
-- drifting once let go, instead of skidding off. How quickly they take up a new sideways speed at the
-- slide speed before any upgrade; higher is tighter. It grows with the slide speed, so they take it up
-- over the same stretch of slide however fast they go, instead of running on straight for longer
local SIDE_GRIP = 8
-- They're drawn in toward the middle of the pack, so they slide down together and steer as one, but
-- loosely: near the middle nothing pulls, so they keep the scatter they landed with
local PACK_RADIUS = 10 -- Studs either side of the middle where nothing pulls
local PACK_PULL = 1 -- Studs per second of pull for every stud further out than that
local MAX_PACK_PULL = 8 -- Studs per second
-- Items can't be steered up ground that slopes across the slide, like the funnel's sides, and nothing
-- holds them up there, so they slide back down. How far the ground's normal leans across, as the
-- sine of its tilt: up to FLAT_TILT it steers as normal, and from STEEP_TILT not uphill at all
local FLAT_TILT = 0.15
local STEEP_TILT = 0.35
-- Items behind the front one, like those dropped from a higher floor that land later or ones held up
-- by something they hit, slide faster until they're within PACK_LENGTH of it, so the pack strings out
-- a little down the slide instead of bunching up behind the front. The further back, the faster:
-- each one goes fast enough to close its gap in about CATCH_UP_TIME, so one twice as far back goes
-- twice as much faster. Near the pack that's only a little, so they drift back into it instead of
-- shooting forward, and they slow down as the gap closes
local PACK_LENGTH = 15 -- Studs behind the front one
local CATCH_UP_TIME = 1.5 -- Seconds
local MAX_CATCH_UP = 1.5 -- Share of the slide speed, so up to 2.5x as fast
local CATCH_UP_EASE = 2 -- How quickly an item takes up a faster speed; higher is sooner
-- Seconds of sliding at the slide speed. An item on the slide this far behind the front one, like one
-- held up for a long while, is too far gone to catch up, so it finishes where it is. It keeps what it
-- made up to there and makes nothing more. The first one over a finish counts as sliding on past it at
-- the slide speed, so the rest still can't fall this far behind it and hold the drop open with the
-- camera waiting at the finish; from then on, nor can those that never reached the slide
local LEFT_BEHIND = 4
-- Barriers push items off to the side instead of stopping them, so they keep their pace down the
-- slide. Within BARRIER_RANGE studs of one, an item can only close in on it so fast, slower the nearer
-- it gets: BARRIER_PUSH studs per second for every stud it's further from it than BARRIER_GAP. So it's
-- turned along it before it gets there, and any closer it's pushed away. That grows with the slide
-- speed like SIDE_GRIP, so it's turned over the same stretch of slide however fast it goes. One more
-- across the slide than MAX_BARRIER_ANGLE would need too much speed along it to keep up the pace down
-- the slide, so it stops items like any other wall
local BARRIER_RANGE = 6 -- Studs between the item's side and the barrier
local BARRIER_GAP = 1
local BARRIER_PUSH = 4
local MAX_BARRIER_ANGLE = math.rad(60)
-- Studs an item starts clear of the edge round each floor's opening that it falls through (see
-- fitThroughOpenings)
local EDGE_GAP = 0.5
-- Studs below an item at its own size that the ground it lies along is looked for. An upgraded item
-- looks as much further as it's bigger, since its middle is that much higher
local GROUND_PROBE = 8
-- Studs per second. An item going down the slide slower than this, and not falling, for STOP_TIME
-- has come to rest. Being steered from side to side against whatever stopped it doesn't count
local STOPPED_SPEED = 2
local STOP_TIME = 1
-- Studs below the last ground it was over (where it was dropped from, until it's over some); an item
-- lower than this went off the slide. The slide itself goes further down than this
local FALL_LIMIT = 150
-- An item that's been on screen and then goes further out of view than this, past the screen's edge
-- or behind the camera, is gone: it finishes where it is, lost. Until it's first come into view, like
-- one falling from a floor above the camera as the drop starts, it's left alone
local OFF_SCREEN_TOLERANCE = 50 -- Studs
local END_PAUSE = 0.75 -- Seconds the camera stays on where the items ended up
local ITEM_FADE_INFO = TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

-- The camera chases the items from straight behind, looking down the slide, raised by FOLLOW_PITCH
-- off the slide under them rather than off the flat, so it sits as high over a steep slide as over a
-- gentle one instead of skimming along it. It follows them down the slide, up and down, and across as
-- they're steered, sliding sideways with them instead of turning toward them, so it always looks
-- straight down the slide
local FOLLOW_DISTANCE = 60 -- Studs
local FOLLOW_PITCH = math.rad(31)
-- Studs down the slide past the items that the camera looks. The pack sits in the lower third of the
-- screen, with the slide ahead and the walls coming up on it above
local LOOK_AHEAD = 44
-- When the items spread out, the camera backs off along the same line, looking as much further ahead
-- so the view keeps its shape, until every one of them is in view with FRAME_MARGIN of the screen to
-- spare around them. Up to MAX_ZOOM times as far. How quickly it backs off, and comes back in once
-- they've closed up; higher is sooner. It comes back in slower, so it doesn't bob in and out as they
-- shuffle about
local FRAME_MARGIN = 0.15 -- Share of the way from the middle of the screen to its edge
local MAX_ZOOM = 2.5
local ZOOM_OUT_SHARPNESS = 3
local ZOOM_IN_SHARPNESS = 1
-- The slope's first measured this far down the slide from Start, before any item's on it, then
-- under the items as they go. How quickly the camera takes up a new slope; higher is sooner
local SLOPE_PROBE = 150 -- Studs
local SLOPE_SHARPNESS = 3
-- The view widens as the pack speeds up: SPEED_FOV degrees at the slide speed before any upgrade, as
-- much again for each time faster, up to MAX_SPEED_FOV. How quickly it takes up the pack's speed;
-- higher is sooner
local SPEED_FOV = 4 -- Degrees
local MAX_SPEED_FOV = 12 -- Degrees
local SPEED_SHARPNESS = 5
-- The camera leans into the way the player steers, by up to MAX_BANK. How quickly; higher is sooner
local MAX_BANK = math.rad(1)
local BANK_SHARPNESS = 5
-- How quickly the camera slides across after the items; higher is snappier. It trails them a little,
-- so steering still moves them across the screen for a moment before the camera catches up
local SIDE_SHARPNESS = 4
local WALL_GAP = 1 -- Studs the camera keeps in front of a wall between it and the items
-- Trailing behind where it should be, the camera can cut into the ground, like the slide behind the
-- items. Ground that comes between it and the items keeps it in front, so it never ends up underneath.
-- Anything facing up more than this, as the up part of the way it faces, counts as ground
local GROUND_FACING = 0.5
-- How quickly the camera catches up with where it should be; higher is snappier. The view turns
-- faster than the camera moves, so the items stay in frame while it glides after them. Its goals are
-- led by how far the pack goes in that time, so however fast it slides the camera keeps to the same
-- place behind it, falling back only while the pack speeds up
local MOVE_SHARPNESS = 4
local LOOK_SHARPNESS = 10
local RETURN_SHARPNESS = 6
-- Gliding back up to the player after a drop, the camera climbs faster than it comes across, so it
-- rises off the slide before it reaches the ground at the top instead of cutting through its edge
local RISE_SHARPNESS = 12
local RETURN_SOUND_NAME = "Woosh" -- Sound in SoundService.SFX, played as the camera sets off back to the player
-- When the items up front finish and the ones left are further back, the camera glides back to them
-- still looking down the slide, instead of turning round to look back at them
local BACK_SPEED = 12 -- Studs per second
local RETURNED_DISTANCE = 0.05 -- Studs. Once back this close to where it was, the camera is handed back
local CAMERA_STEP_NAME = "DropCamera"
local STREAM_INTERVAL = 0.5 -- Seconds between asks for the slide around the items to be loaded
-- Physics only runs within some distance of the character, so items far down the slide froze in
-- place while it stood at the base. Through the drop it's held this far over the pack's middle
-- instead, above the camera's view and anything the items could reach
local CHARACTER_HEIGHT = 150 -- Studs
-- This client streams out what's far from its character, and around 1600 studs down the slide that
-- was the whole base: it all came back at once as the drop ended, and the frame rate sank while it
-- did. So the character goes no further than HOME_REACH from where it stood, and waits there, up
-- over the way down, while the pack goes on. It follows on once the pack would get further than
-- PACK_REACH from it: physics runs within about 1000 studs of the character (the player's
-- SimulationRadius, which scripts can't read), less room for the items ahead of the pack's middle
local HOME_REACH = 1000 -- Studs
local PACK_REACH = 700 -- Studs

type DroppedItem = {
	Item: Items.Item,
	Level: number,
	SlotKey: string, -- The slot it was dropped from, which the server pays it out by
	-- How far down the slide it's got, the furthest so far, and what that's earned it. Shown while it
	-- drops, and fixed once it's done
	Reached: number,
	Pay: number,
	-- The multiplier walls it's touched, nearest first. Only these multiply what it makes, so a wall
	-- that's off to one side as it goes by doesn't count
	Gates: { Drops.Wall },
	TouchedWalls: { [BasePart]: boolean },
	Multiplier: number, -- Of the last wall it went through
	Passed: number, -- Walls it's gone through that multiply
	Part: BasePart, -- The item's mesh, which the rest of it is welded to
	Parts: { BasePart },
	StillFor: number, -- Seconds it has been at rest (see STOPPED_SPEED)
	Probe: number, -- Studs below it that the ground is looked for (see GROUND_PROBE)
	GroundY: number, -- Height of the last ground it was over, which FALL_LIMIT is measured from
	-- Height of the slide where it was last over it. The camera doesn't follow it any lower, so it
	-- stays up on the slide when an item goes off it. -inf until it reaches the slide
	SlideY: number,
	Steerable: boolean, -- Has reached the slide
	Seen: boolean, -- Has been on screen (see OFF_SCREEN_TOLERANCE)
	Done: boolean, -- Its run is over and it's gone to the collect pad; the camera stops following it
	-- Its run ended early: it came to rest, went off the slide or was left behind, rather than
	-- reaching a finish or running out of time. The player has lost it
	Lost: boolean,
}

type Drop = {
	Place: Folder,
	Prompt: ProximityPrompt,
	Floor: BasePart?, -- The place's own, on floor 1
	-- Every floor the items fall through, the built floors' above as well, and each one's own CanCollide,
	-- for when it closes again
	Openings: { [BasePart]: boolean },
	Items: { DroppedItem },
	ByPart: { [BasePart]: DroppedItem }, -- Every part of each item, for the walls it touches
	StartedAt: number,
	EndsAt: number, -- When its time's up, from the owner's Sliding Time upgrade
	StartY: number,
	Start: Vector3, -- Where the way down the slide is measured from
	Direction: Vector3, -- Which way the slide runs, across the ground
	Ending: boolean,
	Speed: number, -- The owner's Sliding Speed upgrade, which multiplies the pay
	SlideSpeed: number, -- Studs per second items are held to down the slide
	Slide: number, -- The owner's Slide upgrade, which raises every wall's multiplier
	Focus: Vector3?, -- What the camera's following, on the slide's middle line. Nil until the first frame
	Followed: Vector3?, -- Focus, slid across after the pack as the camera is. Nil until the first frame
	-- Studs across from that line that the camera's slid after the pack, to the right of the way down.
	-- Nil until the first frame
	Side: number?,
	Slope: number, -- Radians the slide falls away down the way down, eased in (see SLOPE_SHARPNESS)
	Zoom: number, -- Times as far back as usual that the camera's backed off, eased in (see MAX_ZOOM)
	-- Studs per second the pack goes down the slide, across the ground, eased in (see SPEED_SHARPNESS)
	PackSpeed: number,
	-- When the first item crossed a finish, and how far down the slide it had got (see LEFT_BEHIND).
	-- Nil until one has
	FinishedAt: number?,
	FinishReach: number,
	Barriers: { BasePart }, -- See BARRIER_NAME
	ItemBarriers: { BasePart }, -- See ITEM_BARRIER_NAME
	-- Finds the walls between the camera and the items and the ground under the items, but not the items
	-- or the item barriers
	WorldRay: RaycastParams,
}

local drop: Drop? = nil
local lastDropAt = -math.huge
-- Every barrier of each kind loaded now; they stream in and out. Kept as they come and go, since
-- looking through all of Workspace for them as a drop starts held up that frame
local loadedBarriers: { [BasePart]: boolean } = {}
local loadedItemBarriers: { [BasePart]: boolean } = {}
-- Every finish loaded now, with its touch listener. Listened to on the finish rather than on what
-- touches it, as with the multiplier walls
local loadedFinishes: { [BasePart]: RBXScriptConnection } = {}

-- The camera eases from where it is and looks toward its goals every frame, so it never jumps
local cameraHeld = false -- Following the items, or still gliding back afterwards
local cameraPosition = Vector3.zero
local cameraLookAt = Vector3.zero
local goalPosition = Vector3.zero
local goalLookAt = Vector3.zero
local cameraFov = 70
local cameraBank = 0 -- Radians it's rolled, leaning into the steering
local returnCFrame = CFrame.identity -- Where the camera was before the drop
local returnLookAt = Vector3.zero
local returnFov = 70
local lastStreamRequest = 0
local frozenRoot: BasePart? = nil -- The character's, while it's held through a drop
local frozenAt = CFrame.identity -- Where it stood as the drop started

local DropController = {}

-- A point straight ahead of the camera, as far away as its focus
local function getLookAt(cframe: CFrame, focus: Vector3): Vector3
	return cframe.Position + cframe.LookVector * (focus - cframe.Position).Magnitude
end

local function flatten(vector: Vector3): Vector3
	return Vector3.new(vector.X, 0, vector.Z)
end

-- The way out, across the ground, from a barrier within reach studs of the item's middle, if any,
-- and how far across the ground its middle is from it
local function getBarrierNormal(current: Drop, position: Vector3, reach: number): (Vector3?, number)
	for _, barrier in current.Barriers do
		if not barrier.Parent then
			continue
		end
		local half = barrier.Size / 2
		local offset = barrier.CFrame:PointToObjectSpace(position)
		local nearest = Vector3.new(
			math.clamp(offset.X, -half.X, half.X),
			math.clamp(offset.Y, -half.Y, half.Y),
			math.clamp(offset.Z, -half.Z, half.Z)
		)
		local away = barrier.CFrame:VectorToWorldSpace(offset - nearest)
		local across = flatten(away)
		-- Off its sides, not on top of it
		if away.Magnitude < reach and across.Magnitude > away.Magnitude / 2 then
			return across.Unit, across.Magnitude
		end
	end
	return nil, 0
end

-- How far the item's got, and what that's earned it, counting each stud at the multiplier of the
-- last wall it went through before it. The server works out the real pay the same way, from how far
-- it got and the walls it touched
local function measure(current: Drop, dropped: DroppedItem)
	local along = (dropped.Part.Position - current.Start):Dot(current.Direction)
	dropped.Reached = math.max(dropped.Reached, along)
	local paidDistance, multiplier, passed = Drops.Measure(dropped.Gates, dropped.Reached)
	dropped.Multiplier, dropped.Passed = multiplier, passed
	dropped.Pay = Drops.GetPay(dropped.Item, dropped.Level, paidDistance, current.Speed)
end

-- What the drop has made so far, how far it's got, the best multiplier it's reached, the time it has
-- left and how many items it hasn't lost, on screen
local function showStats(current: Drop)
	local cash, distance, multiplier, passed, kept = 0, 0, 1, 0, 0
	for _, dropped in current.Items do
		if not dropped.Done then
			measure(current, dropped)
		end
		cash += dropped.Pay
		distance = math.max(distance, dropped.Reached)
		multiplier = math.max(multiplier, dropped.Multiplier)
		passed = math.max(passed, dropped.Passed)
		if not dropped.Lost then
			kept += 1
		end
	end
	HudController.SetDropStats(cash, distance)
	HudController.SetDropMultiplier(multiplier, passed)
	HudController.SetDropTime(math.max(current.EndsAt - os.clock(), 0))
	HudController.SetDropItems(kept)
end

-- Every wall an item goes through raises the ones after it, for that item. The walls show them
-- raised by the most walls any item still sliding has gone through, so they're back as they were
-- once the drop's over
local function showHits(current: Drop)
	local hits = 0
	for _, dropped in current.Items do
		if not dropped.Done then
			hits = math.max(hits, #dropped.Gates)
		end
	end
	MultiplierWallController.SetHits(hits)
end

-- The item's run is over: it fades off the slide for the pile on the collect pad, and the server
-- hears how far it got and which walls it touched, by how far down the slide they are, which it pays
-- out. A wall far behind may have streamed out by now, so it isn't sent itself. Lost if its run ended
-- early (see DroppedItem.Lost)
local function finishItem(current: Drop, dropped: DroppedItem, lost: boolean)
	if dropped.Done then
		return
	end
	measure(current, dropped)
	dropped.Done = true
	dropped.Lost = lost
	showHits(current)
	local gates = {}
	for _, gate in dropped.Gates do
		table.insert(gates, gate.Along)
	end
	DropResult:FireServer(dropped.SlotKey, dropped.Reached, gates)
	CollectController.AddToPile(current.Place, dropped.Item)

	for _, part in dropped.Parts do
		TweenService:Create(part, ITEM_FADE_INFO, { LocalTransparencyModifier = 1 }):Play()
	end
	task.delay(ITEM_FADE_INFO.Time, dropped.Part.Destroy, dropped.Part)
end

-- Studs either way along the axis that a box this size, turned like this, reaches from its middle
local function getReach(cframe: CFrame, size: Vector3, axis: Vector3): number
	local half = size / 2
	return math.abs(cframe.RightVector:Dot(axis)) * half.X
		+ math.abs(cframe.UpVector:Dot(axis)) * half.Y
		+ math.abs(cframe.LookVector:Dot(axis)) * half.Z
end

-- Items turn as they float in their slots, so a long one dropped while it points at the side of the
-- opening starts out over the edge round it, and lands on it, and tips in late and spinning instead
-- of falling straight through. So it starts just far enough in to clear the edge of every opening
-- below it. An item wider than an opening starts in the middle of it
local function fitThroughOpenings(current: Drop, cframe: CFrame, size: Vector3): CFrame
	local position = cframe.Position
	for opening in current.Openings do
		if opening.Position.Y > position.Y then
			continue
		end
		-- Across it both ways, along its own sides
		for _, axis in { Vector3.xAxis, Vector3.zAxis } do
			local across = opening.CFrame:VectorToWorldSpace(axis)
			local room = math.max(opening.Size:Dot(axis) / 2 - getReach(cframe, size, across) - EDGE_GAP, 0)
			local offset = (position - opening.Position):Dot(across)
			position += across * (math.clamp(offset, -room, room) - offset)
		end
	end
	return cframe.Rotation + position
end

-- A physical copy of the item where its display floats in the slot, as big as it shows there at its
-- level, moved in to fall clear of the openings' edges. Made on this client only, so the server
-- doesn't simulate anyone's drop
local function spawnCopy(current: Drop, item: Items.Item, level: number, slotKey: string, cframe: CFrame)
	local size = Upgrades.GetSize(level)
	local _, fullSize = PhysicalItem.GetShape(item)
	cframe = fitThroughOpenings(current, cframe, fullSize * size)
	local copy, parts = PhysicalItem.Create(item, cframe, ITEM_PHYSICS, size)

	local dropped: DroppedItem = {
		Item = item,
		Level = level,
		SlotKey = slotKey,
		Reached = 0,
		Pay = 0,
		Gates = {},
		TouchedWalls = {},
		Multiplier = 1,
		Passed = 0,
		Part = copy,
		Parts = parts,
		StillFor = 0,
		Probe = GROUND_PROBE * size,
		GroundY = current.StartY,
		SlideY = -math.huge,
		Steerable = false,
		Seen = false,
		Done = false,
		Lost = false,
	}
	for _, part in parts do
		current.ByPart[part] = dropped
	end
	copy.Parent = workspace
	table.insert(current.Items, dropped)
end

-- Walls are touched where this client shows them, as they glide across the slide. The wall pops
-- before the rest go up, so its copy keeps what the item went through
local function onWallTouched(wall: BasePart, hit: BasePart)
	local current = drop
	if not current then
		return
	end
	local dropped = current.ByPart[hit]
	if not dropped or dropped.Done or dropped.TouchedWalls[wall] then
		return
	end
	dropped.TouchedWalls[wall] = true
	Drops.AddWall(dropped.Gates, wall, current.Start, current.Direction, current.Slide)
	MultiplierWallController.Pop(wall)
	showHits(current)
end

-- An item that reaches the end of the slide finishes there, keeping what it made on the way. The
-- first one still sets the pace for the rest (see LEFT_BEHIND)
local function onFinishTouched(hit: BasePart)
	local current = drop
	local dropped = current and current.ByPart[hit]
	if not current or not dropped or dropped.Done then
		return
	end
	finishItem(current, dropped, false)
	if not current.FinishedAt then
		current.FinishedAt, current.FinishReach = os.clock(), dropped.Reached
	end
end

-- The character is anchored through the drop, so the steering keys don't walk it off. Anchored on
-- this client only, it can follow the pack here while the server, and everyone else, still sees it
-- standing where it was. It's back there before it's let go. Up over the pack there's no floor under
-- it, and its animations play for everyone, so it isn't let fall: it would show falling at its base
local function setFrozen(frozen: boolean)
	if frozen then
		local character = LocalPlayer.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if root and root:IsA("BasePart") then
			frozenRoot, frozenAt = root, root.CFrame
			root.Anchored = true
			if humanoid then
				humanoid:SetStateEnabled(Enum.HumanoidStateType.Freefall, false)
			end
		end
	elseif frozenRoot then
		local character = frozenRoot.Parent
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		frozenRoot.CFrame = frozenAt
		frozenRoot.Anchored = false
		frozenRoot = nil
		if humanoid then
			humanoid:SetStateEnabled(Enum.HumanoidStateType.Freefall, true)
		end
	end
end

-- Whatever's still on the slide finishes where it is, and everything goes back the way it was.
-- The drop prompt comes back once the cooldown is up
local function endDrop()
	local current = drop
	if not current then
		return
	end
	for _, dropped in current.Items do
		finishItem(current, dropped, false)
	end
	showStats(current)
	drop = nil

	for opening, canCollide in current.Openings do
		opening.CanCollide = canCollide
	end
	for _, barrier in current.ItemBarriers do
		barrier.CanCollide = false
	end
	task.delay(math.max(Drops.COOLDOWN - (os.clock() - current.StartedAt), 0), function()
		if drop == nil then
			PromptController.SetHidden(current.Place, current.Prompt, false)
		end
	end)
	SlotController.SetFaded(current.Place, false)
	MultiplierWallController.SetFadeScale(1)
	setFrozen(false)
	HudController.SetDropView(false)
	-- The camera glides back on its own from here
	local sfx = SoundService:FindFirstChild("SFX")
	local sound = sfx and sfx:FindFirstChild(RETURN_SOUND_NAME)
	if sound and sound:IsA("Sound") then
		sound:Play()
	end
end

-- How many times as far back as usual the camera has to be to have every item in view, with
-- FRAME_MARGIN to spare. Away is where it usually is from what it follows, and ahead where it looks
-- from there. Backing off scales both, so it looks the same way however far back it is: an item stays
-- just as far across from it, and what it follows gets further ahead of it and further down the
-- screen, so each edge of the screen an item has to clear gives the zoom that takes
local function getZoom(active: { DroppedItem }, followed: Vector3, away: Vector3, ahead: Vector3): number
	local viewport = workspace.CurrentCamera.ViewportSize
	local tanUp = math.tan(math.rad(cameraFov) / 2) * (1 - FRAME_MARGIN)
	local tanAcross = tanUp * viewport.X / math.max(viewport.Y, 1)
	local forward = (ahead - away).Unit
	local right = forward:Cross(Vector3.yAxis).Unit
	local up = right:Cross(forward)
	-- What it follows, from the camera: how far ahead, and how far up the screen
	local depth, height = -away:Dot(forward), -away:Dot(up)
	local zoom = 1
	for _, dropped in active do
		local part = dropped.Part
		local position = part.Position
		-- Up on the slide when it's gone off it, as the camera stays
		local offset = Vector3.new(position.X, math.max(position.Y, dropped.SlideY), position.Z) - followed
		local reach = part.Size.Magnitude / 2
		local front, across, above = offset:Dot(forward), math.abs(offset:Dot(right)), offset:Dot(up)
		zoom = math.max(
			zoom,
			((across + reach) / tanAcross - front) / depth, -- The screen's sides
			(reach - above - tanUp * front) / (height + tanUp * depth), -- Its bottom
			(above + reach - tanUp * front) / (tanUp * depth - height) -- Its top
		)
	end
	return math.min(zoom, MAX_ZOOM)
end

-- Studs the whole item is out of the camera's view, as it was last frame: how far outside the nearest
-- side of the view, or behind the camera. 0 or less while any of it is on screen
local function getOutOfView(part: BasePart): number
	local camera = workspace.CurrentCamera
	local viewport = camera.ViewportSize
	local halfUp = math.rad(camera.FieldOfView) / 2
	local halfAcross = math.atan(math.tan(halfUp) * viewport.X / math.max(viewport.Y, 1))
	local offset = camera.CFrame:PointToObjectSpace(part.Position)
	local ahead = -offset.Z
	-- The view's sides all meet at the camera, each turned out from straight ahead by half the view
	local out = math.max(
		-ahead,
		math.abs(offset.X) * math.cos(halfAcross) - ahead * math.sin(halfAcross),
		math.abs(offset.Y) * math.cos(halfUp) - ahead * math.sin(halfUp)
	)
	return out - part.Size.Magnitude / 2
end

-- Once the drop's time is up, every item finishes where it is. Before that, items that come to rest,
-- go off the slide, go off screen (see OFF_SCREEN_TOLERANCE) or are left far behind are lost where
-- they are, and those that touch a finish finish there (see onFinishTouched). The rest are held to
-- the slide speed down the slide, lie along the ground and, once on the slide, go where they're
-- steered as a pack. The camera aims at them, and once none are left, the drop ends after a moment
local function followItems(current: Drop, dt: number)
	local timeUp = os.clock() >= current.EndsAt
	local active: { DroppedItem } = {}
	for _, dropped in current.Items do
		if dropped.Done then
			continue
		end
		local part = dropped.Part
		if timeUp or not part.Parent or part.Position.Y < dropped.GroundY - FALL_LIMIT then
			finishItem(current, dropped, not timeUp)
			continue
		end
		local outOfView = getOutOfView(part)
		if outOfView <= 0 then
			dropped.Seen = true
		elseif dropped.Seen and outOfView > OFF_SCREEN_TOLERANCE then
			finishItem(current, dropped, true)
			continue
		end
		local velocity = part.AssemblyLinearVelocity
		local still = velocity:Dot(current.Direction) < STOPPED_SPEED and math.abs(velocity.Y) < STOPPED_SPEED
		dropped.StillFor = if still then dropped.StillFor + dt else 0
		if dropped.StillFor >= STOP_TIME then
			finishItem(current, dropped, true)
		else
			table.insert(active, dropped)
		end
	end

	local lead = -math.huge -- Studs down the slide that the front item on it has got
	for _, dropped in active do
		local position = dropped.Part.Position
		if not dropped.Steerable then
			local ground = workspace:Raycast(position, -Vector3.yAxis * dropped.Probe, current.WorldRay)
			dropped.Steerable = ground ~= nil and ground.Instance.Name == SLIDE_NAME
		end
		if dropped.Steerable then
			lead = math.max(lead, (position - current.Start):Dot(current.Direction))
		end
	end
	-- The first one over a finish slides on past it (see LEFT_BEHIND)
	local finishedAt = current.FinishedAt
	if finishedAt then
		lead = math.max(lead, current.FinishReach + current.SlideSpeed * (os.clock() - finishedAt))
	end
	-- Items left too far behind the front one finish where they are. Until one's crossed a finish, the
	-- front one never is, so some are always left. The pack's middle counts one that's gone off the
	-- slide as still up on it
	local center = Vector3.zero
	for index = #active, 1, -1 do
		local dropped = active[index]
		local position = dropped.Part.Position
		local behind = lead - (position - current.Start):Dot(current.Direction)
		if (dropped.Steerable or finishedAt) and behind > current.SlideSpeed * LEFT_BEHIND then
			finishItem(current, dropped, true)
			table.remove(active, index)
		else
			center += Vector3.new(position.X, math.max(position.Y, dropped.SlideY), position.Z)
		end
	end
	showStats(current)

	if #active == 0 then
		current.PackSpeed *= math.exp(-SPEED_SHARPNESS * dt)
		if not current.Ending then
			current.Ending = true
			task.delay(END_PAUSE, function()
				if drop == current then
					endDrop()
				end
			end)
		end
		return
	end
	center /= #active
	if frozenRoot then
		local over = center + Vector3.yAxis * CHARACTER_HEIGHT
		local toHome = frozenAt.Position - over
		local back = math.clamp(toHome.Magnitude - HOME_REACH, 0, PACK_REACH)
		local position = if back > 0 then over + toHome.Unit * back else over
		frozenRoot.CFrame = frozenAt.Rotation + position
	end

	local steer = HudController.GetSteer()
	local right = current.Direction:Cross(Vector3.yAxis)
	local sideScale = current.SlideSpeed / Drops.SLIDE_SPEED
	local grip = 1 - math.exp(-SIDE_GRIP * sideScale * dt)
	local steerSpeed = STEER_SPEED * current.Speed * STEER_MULTIPLIER
	local ease = 1 - math.exp(-CATCH_UP_EASE * dt)
	local pace = 0 -- Of every item down the slide, across the ground, added up
	local slideNormal = Vector3.zero -- Of the slide under them, added up
	for _, dropped in active do
		local part = dropped.Part
		local itemVelocity = part.AssemblyLinearVelocity
		local across = flatten(itemVelocity)
		local sideways = across:Dot(right)
		local forward = across - right * sideways
		local catchUp = 0
		if dropped.Steerable then
			local behind = lead - (part.Position - current.Start):Dot(current.Direction)
			catchUp = math.clamp((behind - PACK_LENGTH) / CATCH_UP_TIME, 0, current.SlideSpeed * MAX_CATCH_UP)
		end
		local maxSpeed = current.SlideSpeed + catchUp
		if forward.Magnitude > maxSpeed then
			forward = forward.Unit * maxSpeed
		end
		if catchUp > 0 then
			forward += current.Direction * (maxSpeed - forward:Dot(current.Direction)) * ease
		end
		local ground = workspace:Raycast(part.Position, -Vector3.yAxis * dropped.Probe, current.WorldRay)
		if dropped.Steerable then
			local apart = (center - part.Position):Dot(right)
			local outside = math.max(math.abs(apart) - PACK_RADIUS, 0) * math.sign(apart)
			local pull = math.clamp(outside * PACK_PULL, -MAX_PACK_PULL, MAX_PACK_PULL)
			local target = steer * steerSpeed + pull * sideScale
			if ground then
				local tilt = ground.Normal:Dot(right) -- Above 0 where the ground falls away to the right
				local steepness = math.clamp((math.abs(tilt) - FLAT_TILT) / (STEEP_TILT - FLAT_TILT), 0, 1)
				local downhill = math.sign(tilt)
				if target * downhill < 0 then
					target *= 1 - steepness
				end
				if sideways * downhill > target * downhill then
					target += (sideways - target) * steepness
				end
			end
			sideways += (target - sideways) * grip
		end
		local flat = forward + right * sideways
		-- Near a barrier, it's pushed off to the side, keeping its pace down the slide (see BARRIER_RANGE)
		local away, distance = getBarrierNormal(current, part.Position, part.Size.Magnitude / 2 + BARRIER_RANGE)
		local onward = forward:Dot(current.Direction)
		if away and onward > 0 then
			local outward = right:Dot(away) -- Studs further off the barrier for every stud to the right
			if math.abs(outward) > math.cos(MAX_BARRIER_ANGLE) then
				local clearance = distance - getReach(part.CFrame, part.Size, away)
				-- The least it has to be moving away from it, so below 0 while it may still close in
				local leastAway = (BARRIER_GAP - clearance) * BARRIER_PUSH * sideScale
				local awaySpeed = flat:Dot(away)
				if awaySpeed < leastAway then
					sideways += (leastAway - awaySpeed) / outward
					flat = forward + right * sideways
				end
			end
		end
		itemVelocity = flat + Vector3.yAxis * itemVelocity.Y
		part.AssemblyLinearVelocity = itemVelocity
		pace += onward

		if ground then
			dropped.GroundY = ground.Position.Y
			if ground.Instance.Name == SLIDE_NAME then
				dropped.SlideY = ground.Position.Y
				slideNormal += ground.Normal
			end
		end
	end
	local speed = math.clamp(pace / #active, 0, current.SlideSpeed)
	current.PackSpeed += (speed - current.PackSpeed) * (1 - math.exp(-SPEED_SHARPNESS * dt))
	if slideNormal ~= Vector3.zero then
		local slope = math.atan2(slideNormal:Dot(current.Direction), slideNormal.Y)
		current.Slope += (slope - current.Slope) * (1 - math.exp(-SLOPE_SHARPNESS * dt))
	end

	-- The pack's middle, moved across onto the line down the middle of the slide from Start
	local packSide = (center - current.Start):Dot(right)
	local focus = center - right * packSide
	-- Straight there, but no faster than BACK_SPEED back up the slide
	local last = current.Focus
	if last then
		local back = (last - focus):Dot(current.Direction)
		if back > 0 then
			focus = focus:Lerp(last, math.max(back - BACK_SPEED * dt, 0) / back)
		end
	end
	current.Focus = focus

	-- Across after the pack. Both the camera and where it looks move across by the same amount, so it
	-- slides sideways instead of turning, however differently fast the two catch up with their goals
	local lastSide = current.Side or packSide
	local side = lastSide + (packSide - lastSide) * (1 - math.exp(-SIDE_SHARPNESS * dt))
	current.Side = side
	local shift = right * (side - lastSide)
	cameraPosition += shift
	cameraLookAt += shift
	local followed = focus + right * side
	current.Followed = followed

	-- Down along the slide, and straight up off it
	local slope = current.Slope
	local downSlide = current.Direction * math.cos(slope) - Vector3.yAxis * math.sin(slope)
	local upSlide = current.Direction * math.sin(slope) + Vector3.yAxis * math.cos(slope)
	local offset = (upSlide * math.sin(FOLLOW_PITCH) - downSlide * math.cos(FOLLOW_PITCH)) * FOLLOW_DISTANCE
	local ahead = downSlide * LOOK_AHEAD
	-- Backed off far enough to have them all in view (see MAX_ZOOM)
	local zoom = getZoom(active, followed, offset, ahead)
	local zoomSharpness = if zoom > current.Zoom then ZOOM_OUT_SHARPNESS else ZOOM_IN_SHARPNESS
	current.Zoom += (zoom - current.Zoom) * (1 - math.exp(-zoomSharpness * dt))
	MultiplierWallController.SetFadeScale(current.Zoom)
	offset *= current.Zoom
	-- In front of any wall that would come between, like the funnel's
	local hit = workspace:Raycast(followed, offset, current.WorldRay)
	local distance = if hit then math.max(hit.Distance - WALL_GAP, WALL_GAP) else offset.Magnitude
	-- Led by how far the pack goes while each catches up (see MOVE_SHARPNESS)
	local velocity = (current.Direction - Vector3.yAxis * math.tan(slope)) * current.PackSpeed
	goalPosition = followed + offset.Unit * distance + velocity / MOVE_SHARPNESS
	goalLookAt = followed + ahead * current.Zoom + velocity / LOOK_SHARPNESS

	-- With streaming, parts of the slide far from the character may not be loaded on this client yet
	if os.clock() - lastStreamRequest > STREAM_INTERVAL then
		lastStreamRequest = os.clock()
		task.spawn(pcall, LocalPlayer.RequestStreamAroundAsync, LocalPlayer, center)
	end
end

local function onRenderStep(dt: number)
	local camera = workspace.CurrentCamera
	local current = drop
	if current then
		followItems(current, dt)
	else
		goalPosition = returnCFrame.Position
		goalLookAt = returnLookAt
	end

	local moveSharpness = if current then MOVE_SHARPNESS else RETURN_SHARPNESS
	local lookSharpness = if current then LOOK_SHARPNESS else RETURN_SHARPNESS
	local lastPosition = cameraPosition
	cameraPosition = cameraPosition:Lerp(goalPosition, 1 - math.exp(-moveSharpness * dt))
	cameraLookAt = cameraLookAt:Lerp(goalLookAt, 1 - math.exp(-lookSharpness * dt))
	local fov = returnFov
	if current then
		fov += math.min(SPEED_FOV * current.PackSpeed / Drops.SLIDE_SPEED, MAX_SPEED_FOV)
	end
	cameraFov += (fov - cameraFov) * (1 - math.exp(-moveSharpness * dt))
	local bank = if current then -HudController.GetSteer() * MAX_BANK else 0
	cameraBank += (bank - cameraBank) * (1 - math.exp(-BANK_SHARPNESS * dt))
	HudController.SetDropSpeed(if current then current.PackSpeed / Drops.SLIDE_SPEED else 0)
	-- Gliding back up to the player, it climbs ahead of coming across (see RISE_SHARPNESS)
	if not current and goalPosition.Y > lastPosition.Y then
		local y = lastPosition.Y + (goalPosition.Y - lastPosition.Y) * (1 - math.exp(-RISE_SHARPNESS * dt))
		cameraPosition = Vector3.new(cameraPosition.X, y, cameraPosition.Z)
	end
	-- Never under the ground the items are on (see GROUND_FACING)
	if current and current.Followed then
		local followed = current.Followed
		local toCamera = cameraPosition - followed
		local hit = workspace:Raycast(followed, toCamera, current.WorldRay)
		if hit and hit.Normal.Y > GROUND_FACING then
			cameraPosition = followed + toCamera.Unit * math.max(hit.Distance - WALL_GAP, WALL_GAP)
		end
	end

	-- Back where it started: handed back to the normal camera, which carries on from there
	if
		not current
		and (cameraPosition - goalPosition).Magnitude < RETURNED_DISTANCE
		and (cameraLookAt - goalLookAt).Magnitude < RETURNED_DISTANCE
	then
		cameraHeld = false
		RunService:UnbindFromRenderStep(CAMERA_STEP_NAME)
		camera.CFrame = returnCFrame
		camera.FieldOfView = returnFov
		camera.CameraType = Enum.CameraType.Custom
		return
	end

	camera.CFrame = CFrame.lookAt(cameraPosition, cameraLookAt) * CFrame.Angles(0, 0, cameraBank)
	camera.Focus = CFrame.new(cameraLookAt)
	camera.FieldOfView = cameraFov
end

local function holdCamera()
	-- Still gliding back from the last drop: it just turns around and follows the new one
	if cameraHeld then
		return
	end
	cameraHeld = true

	local camera = workspace.CurrentCamera
	returnCFrame = camera.CFrame
	returnLookAt = getLookAt(camera.CFrame, camera.Focus.Position)
	returnFov = camera.FieldOfView
	cameraPosition = returnCFrame.Position
	cameraLookAt = returnLookAt
	cameraFov = returnFov
	cameraBank = 0
	goalPosition = cameraPosition
	goalLookAt = cameraLookAt
	camera.CameraType = Enum.CameraType.Scriptable
	RunService:BindToRenderStep(CAMERA_STEP_NAME, Enum.RenderPriority.Camera.Value + 1, onRenderStep)
end

-- The owner's value of a sign upgrade. The server keeps their level on the place for everyone, and
-- pays by the same one
local function getUpgrade(place: Folder, name: string): number
	local level = place:GetAttribute(`{name}Level`)
	return SignUpgrades.GetValue(name, if typeof(level) == "number" then level else 1)
end

-- Everything here happens on this client the moment the prompt fires: the slots fade, copies of
-- their items fall through the opened floor and the camera follows them down the slide. The server
-- makes the same checks, so it only pays for drops it would have allowed
local function startDrop(place: Folder, prompt: ProximityPrompt)
	if drop or place:GetAttribute("OwnerUserId") ~= LocalPlayer.UserId then
		return
	end
	if os.clock() - lastDropAt < Drops.COOLDOWN then
		return
	end

	local toDrop = {}
	local startY = math.huge
	for _, slot in Places.GetSlots(place) do
		local id = slot:GetAttribute("ItemId")
		local item = if typeof(id) == "string" then Items[id] else nil
		local display = slot:FindFirstChild(SLOT_ITEM_NAME)
		if item and display and display:IsA("BasePart") then
			local level = slot:GetAttribute("ItemLevel")
			table.insert(toDrop, {
				Item = item,
				Level = if typeof(level) == "number" then level else 1,
				SlotKey = Places.GetSlotKey(slot),
				CFrame = display.CFrame,
			})
			startY = math.min(startY, display.Position.Y)
		end
	end
	if #toDrop == 0 then
		return
	end

	local found = place:FindFirstChild(DROP_FLOOR_NAME)
	local floor = if found and found:IsA("BasePart") then found else nil
	local start, direction = toDrop[1].CFrame.Position, -Vector3.xAxis
	if floor then
		start, direction = Drops.GetSlideLine(floor)
	end

	local worldRay = RaycastParams.new()
	worldRay.FilterType = Enum.RaycastFilterType.Exclude
	worldRay.RespectCanCollide = true

	-- See SLOPE_PROBE
	local slope = 0
	local probe = workspace:Raycast(start + direction * SLOPE_PROBE, -Vector3.yAxis * FALL_LIMIT * 2, worldRay)
	if probe and probe.Instance.Name == SLIDE_NAME then
		slope = math.atan2(probe.Normal:Dot(direction), probe.Normal.Y)
	end
	local barriers: { BasePart } = {}
	local itemBarriers: { BasePart } = {}
	for barrier in loadedBarriers do
		table.insert(barriers, barrier)
	end
	for barrier in loadedItemBarriers do
		table.insert(itemBarriers, barrier)
	end

	local speed = getUpgrade(place, "SlideSpeed")
	local openings: { [BasePart]: boolean } = {}
	if floor then
		openings[floor] = floor.CanCollide
	end
	for number in Floors.Prices do
		local built = place:FindFirstChild(Floors.GetName(number))
		local opening = built and built:FindFirstChild(DROP_FLOOR_NAME)
		if opening and opening:IsA("BasePart") then
			openings[opening] = opening.CanCollide
		end
	end

	local now = os.clock()
	local current: Drop = {
		Place = place,
		Prompt = prompt,
		Floor = floor,
		Openings = openings,
		Items = {},
		ByPart = {},
		StartedAt = now,
		EndsAt = now + getUpgrade(place, "SlideTime"),
		StartY = startY,
		Start = start,
		Direction = direction,
		Ending = false,
		Speed = speed,
		SlideSpeed = Drops.GetSlideSpeed(speed),
		Slide = getUpgrade(place, "Slide"),
		Focus = nil,
		Followed = nil,
		Side = nil,
		Slope = slope,
		Zoom = 1,
		PackSpeed = 0,
		FinishedAt = nil,
		FinishReach = 0,
		Barriers = barriers,
		ItemBarriers = itemBarriers,
		WorldRay = worldRay,
	}
	drop = current
	lastDropAt = now

	for _, entry in toDrop do
		spawnCopy(current, entry.Item, entry.Level, entry.SlotKey, entry.CFrame)
	end
	showStats(current)
	local ignored: { Instance } = {}
	for _, dropped in current.Items do
		table.insert(ignored, dropped.Part)
	end
	if LocalPlayer.Character then
		table.insert(ignored, LocalPlayer.Character)
	end
	for _, barrier in itemBarriers do
		table.insert(ignored, barrier)
	end
	worldRay.FilterDescendantsInstances = ignored

	-- Opened on this client only, so nothing else falls through
	for opening in openings do
		opening.CanCollide = false
	end
	for _, barrier in itemBarriers do
		barrier.CanCollide = true
	end
	PromptController.SetHidden(place, prompt, true)
	SlotController.SetFaded(place, true)
	setFrozen(true)
	HudController.SetDropView(true)
	holdCamera()
end

local function trackPart(instance: Instance)
	if not instance:IsA("BasePart") then
		return
	end
	if instance.Name == BARRIER_NAME then
		loadedBarriers[instance] = true
	elseif instance.Name == ITEM_BARRIER_NAME then
		loadedItemBarriers[instance] = true
	elseif instance.Name == FINISH_NAME and not loadedFinishes[instance] then
		loadedFinishes[instance] = instance.Touched:Connect(onFinishTouched)
	end
end

local function untrackPart(instance: Instance)
	loadedBarriers[instance :: any] = nil
	loadedItemBarriers[instance :: any] = nil
	local touched = loadedFinishes[instance :: any]
	if touched then
		touched:Disconnect()
		loadedFinishes[instance :: any] = nil
	end
end

-- Whether a drop's going, and where its items are: the middle of the pack the camera follows, or nil
-- before its first frame. It's going until its items are all gone or the player exits it
function DropController.GetDrop(): (boolean, Vector3?)
	local current = drop
	return current ~= nil, if current then current.Followed else nil
end

function DropController.Start()
	for _, descendant in workspace:GetDescendants() do
		trackPart(descendant)
	end
	workspace.DescendantAdded:Connect(trackPart)
	workspace.DescendantRemoving:Connect(untrackPart)
	MultiplierWallController.Touched:Connect(onWallTouched)
	ProximityPromptService.PromptTriggered:Connect(function(prompt)
		local place = Places.Find(prompt)
		if place and prompt:FindFirstAncestor(DROP_BUTTON_NAME) then
			startDrop(place, prompt)
		end
	end)
	HudController.ExitRequested:Connect(endDrop)
end

return DropController
