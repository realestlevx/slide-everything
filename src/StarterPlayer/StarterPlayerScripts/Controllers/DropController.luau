local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
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
local SLOT_ITEM_NAME = "SlotItem"

-- Dropped items barely grip, and their grip outweighs the slide's, so they slide down even the
-- gentlest ramp. The slide speed (see Drops.GetSlideSpeed) then keeps them from going faster than
-- that down the slide; falling isn't slowed
local ITEM_PHYSICS = PhysicalProperties.new(0.7, 0.05, 0.2, 100, 1)
-- Studs per second sideways while the player steers, at the slide speed before any Sliding Speed
-- upgrade. Steering grows faster than the slide speed, by its rise to the power of STEER_GROWTH, so a
-- faster pack cuts across more sharply and still makes the gates that come at it sooner: at 2x slide
-- speed it steers 2.8x as fast, and at 3x 5.2x. The pack's pull grows just with the slide speed, so
-- it holds together just as tightly however fast it slides
local STEER_SPEED = 15
local STEER_GROWTH = 1.5
-- On the slide, items grip sideways like sleds: they slide where they're steered and stop
-- drifting once let go, instead of skidding off. How quickly they take up a new sideways speed at the
-- slide speed before any upgrade; higher is tighter. It grows with the slide speed, so they take it up
-- over the same stretch of slide however fast they go, instead of running on straight for longer
local SIDE_GRIP = 8
-- They're drawn in toward the middle of the pack, so they slide down together and steer as one
local PACK_RADIUS = 3 -- Studs either side of the middle where nothing pulls
local PACK_PULL = 2 -- Studs per second of pull for every stud further out than that
local MAX_PACK_PULL = 8 -- Studs per second
-- Items can't be steered up ground that slopes across the slide, like the funnel's sides, and nothing
-- holds them up there, so they slide back down. How far the ground's normal leans across, as the
-- sine of its tilt: up to FLAT_TILT it steers as normal, and from STEEP_TILT not uphill at all
local FLAT_TILT = 0.15
local STEEP_TILT = 0.35
-- Items behind the front one, like those dropped from a higher floor that land later or ones held up
-- by something they hit, slide faster until they've caught up with it. The further back, the faster:
-- each one goes fast enough to close its gap in about CATCH_UP_TIME, so one twice as far back goes
-- twice as much faster. Near the pack that's only a little, so they drift back into it instead of
-- shooting forward, and they slow down as the gap closes
local CATCH_UP_TIME = 1.5 -- Seconds
local MAX_CATCH_UP = 1.5 -- Share of the slide speed, so up to 2.5x as fast
local CATCH_UP_EASE = 2 -- How quickly an item takes up a faster speed; higher is sooner
-- Seconds of sliding at the slide speed. An item on the slide this far behind the front one, like one
-- held up for a long while, is too far gone to catch up, so it finishes where it is. It keeps what it
-- made up to there and makes nothing more
local LEFT_BEHIND = 4
-- Items stay the way up they were dropped instead of tumbling, tilted to lie along the ground under them
local TILT_RESPONSIVENESS = 25
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
local END_PAUSE = 0.75 -- Seconds the camera stays on where the items ended up
local ITEM_FADE_INFO = TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

-- The camera chases the items from straight behind, looking down the slide, raised by FOLLOW_PITCH.
-- It follows them down the slide, up and down, and across as they're steered, sliding sideways with
-- them instead of turning toward them, so it always looks straight down the slide
local FOLLOW_DISTANCE = 36 -- Studs
local FOLLOW_PITCH = math.rad(40)
-- Studs down the slide past the items that the camera looks, so it looks along the slide ahead of
-- them instead of down on them
local LOOK_AHEAD = 6
-- How quickly the camera slides across after the items; higher is snappier. It trails them a little,
-- so steering still moves them across the screen for a moment before the camera catches up
local SIDE_SHARPNESS = 4
local WALL_GAP = 1 -- Studs the camera keeps in front of a wall between it and the items
-- Trailing behind where it should be, the camera can cut into the ground, like the slide behind the
-- items. Ground that comes between it and the items keeps it in front, so it never ends up underneath.
-- Anything facing up more than this, as the up part of the way it faces, counts as ground
local GROUND_FACING = 0.5
-- How quickly the camera catches up with where it should be; higher is snappier. The view turns
-- faster than the camera moves, so the items stay in frame while it glides after them
local MOVE_SHARPNESS = 4
local LOOK_SHARPNESS = 10
local RETURN_SHARPNESS = 6
-- Gliding back up to the player after a drop, the camera climbs faster than it comes across, so it
-- rises off the slide before it reaches the ground at the top instead of cutting through its edge
local RISE_SHARPNESS = 12
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
	Rotation: CFrame, -- The way up it was dropped, which it keeps
	Align: AlignOrientation, -- Holds it that way up, tilted along the ground
	StillFor: number, -- Seconds it has been at rest (see STOPPED_SPEED)
	Probe: number, -- Studs below it that the ground is looked for (see GROUND_PROBE)
	GroundY: number, -- Height of the last ground it was over, which FALL_LIMIT is measured from
	-- Height of the slide where it was last over it. The camera doesn't follow it any lower, so it
	-- stays up on the slide when an item goes off it. -inf until it reaches the slide
	SlideY: number,
	Steerable: boolean, -- Has reached the slide
	Done: boolean, -- Its run is over and it's gone to the collect pad; the camera stops following it
}

type Drop = {
	Place: Folder,
	Prompt: ProximityPrompt,
	Floor: BasePart?, -- The place's own, on floor 1
	-- Every floor the items fall through, the built floors' above as well, and each one's own CanCollide,
	-- for when it closes again
	Openings: { [BasePart]: boolean },
	Items: { DroppedItem },
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
	-- Finds the walls between the camera and the items and the ground under the items, but not the items
	WorldRay: RaycastParams,
}

local drop: Drop? = nil
local lastDropAt = -math.huge

-- The camera eases from where it is and looks toward its goals every frame, so it never jumps
local cameraHeld = false -- Following the items, or still gliding back afterwards
local cameraPosition = Vector3.zero
local cameraLookAt = Vector3.zero
local goalPosition = Vector3.zero
local goalLookAt = Vector3.zero
local returnCFrame = CFrame.identity -- Where the camera was before the drop
local returnLookAt = Vector3.zero
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

-- What the drop has made so far, how far it's got, the best multiplier it's reached and the time it
-- has left, on screen
local function showStats(current: Drop)
	local cash, distance, multiplier, passed = 0, 0, 1, 0
	for _, dropped in current.Items do
		if not dropped.Done then
			measure(current, dropped)
		end
		cash += dropped.Pay
		distance = math.max(distance, dropped.Reached)
		multiplier = math.max(multiplier, dropped.Multiplier)
		passed = math.max(passed, dropped.Passed)
	end
	HudController.SetDropStats(cash, distance)
	HudController.SetDropMultiplier(multiplier, passed)
	HudController.SetDropTime(math.max(current.EndsAt - os.clock(), 0))
end

-- The item's run is over: it fades off the slide for the pile on the collect pad, and the server
-- hears how far it got and which walls it touched, by how far down the slide they are, which it pays
-- out. A wall far behind may have streamed out by now, so it isn't sent itself
local function finishItem(current: Drop, dropped: DroppedItem)
	if dropped.Done then
		return
	end
	measure(current, dropped)
	dropped.Done = true
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

-- A physical copy of the item where its display floats in the slot, as big as it shows there at its
-- level. Made on this client only, so the server doesn't simulate anyone's drop
local function spawnCopy(current: Drop, item: Items.Item, level: number, slotKey: string, cframe: CFrame)
	local size = Upgrades.GetSize(level)
	local copy, parts = PhysicalItem.Create(item, cframe, ITEM_PHYSICS, size)
	local attachment = Instance.new("Attachment")
	attachment.Parent = copy
	local align = Instance.new("AlignOrientation")
	align.Mode = Enum.OrientationAlignmentMode.OneAttachment
	align.Attachment0 = attachment
	align.CFrame = cframe.Rotation
	align.MaxTorque = math.huge
	align.Responsiveness = TILT_RESPONSIVENESS
	align.Parent = copy

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
		Rotation = cframe.Rotation,
		Align = align,
		StillFor = 0,
		Probe = GROUND_PROBE * size,
		GroundY = current.StartY,
		SlideY = -math.huge,
		Steerable = false,
		Done = false,
	}
	-- Walls are touched where this client shows them, as they glide across the slide
	for _, part in parts do
		part.Touched:Connect(function(hit)
			if not dropped.Done and not dropped.TouchedWalls[hit] and Drops.IsWall(hit) then
				dropped.TouchedWalls[hit] = true
				Drops.AddWall(dropped.Gates, hit, current.Start, current.Direction, current.Slide)
			end
		end)
	end
	copy.Parent = workspace
	table.insert(current.Items, dropped)
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
		finishItem(current, dropped)
	end
	showStats(current)
	drop = nil

	for opening, canCollide in current.Openings do
		opening.CanCollide = canCollide
	end
	task.delay(math.max(Drops.COOLDOWN - (os.clock() - current.StartedAt), 0), function()
		if drop == nil then
			PromptController.SetHidden(current.Place, current.Prompt, false)
		end
	end)
	SlotController.SetFaded(current.Place, false)
	setFrozen(false)
	HudController.SetDropView(false)
	-- The camera glides back on its own from here
end

-- Once the drop's time is up, every item finishes where it is. Before that, items that come to rest,
-- go off the slide or are left far behind finish where they are, and the rest are held to the slide
-- speed down the slide, lie along the ground and, once on the slide, go where they're steered as a
-- pack. The camera aims at them, and once none are left, the drop ends after a moment
local function followItems(current: Drop, dt: number)
	local timeUp = os.clock() >= current.EndsAt
	local active: { DroppedItem } = {}
	for _, dropped in current.Items do
		if dropped.Done then
			continue
		end
		local part = dropped.Part
		if timeUp or not part.Parent or part.Position.Y < dropped.GroundY - FALL_LIMIT then
			finishItem(current, dropped)
			continue
		end
		local velocity = part.AssemblyLinearVelocity
		local still = velocity:Dot(current.Direction) < STOPPED_SPEED and math.abs(velocity.Y) < STOPPED_SPEED
		dropped.StillFor = if still then dropped.StillFor + dt else 0
		if dropped.StillFor >= STOP_TIME then
			finishItem(current, dropped)
		else
			table.insert(active, dropped)
		end
	end
	showStats(current)

	if #active == 0 then
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
	-- Items left too far behind the front one finish where they are. The front one never is, so some
	-- are always left. The pack's middle counts one that's gone off the slide as still up on it
	local center = Vector3.zero
	for index = #active, 1, -1 do
		local dropped = active[index]
		local position = dropped.Part.Position
		local behind = lead - (position - current.Start):Dot(current.Direction)
		if dropped.Steerable and behind > current.SlideSpeed * LEFT_BEHIND then
			finishItem(current, dropped)
			table.remove(active, index)
		else
			center += Vector3.new(position.X, math.max(position.Y, dropped.SlideY), position.Z)
		end
	end
	center /= #active
	if frozenRoot then
		frozenRoot.CFrame = frozenAt.Rotation + center + Vector3.yAxis * CHARACTER_HEIGHT
	end

	local steer = HudController.GetSteer()
	local right = current.Direction:Cross(Vector3.yAxis)
	local sideScale = current.SlideSpeed / Drops.SLIDE_SPEED
	local grip = 1 - math.exp(-SIDE_GRIP * sideScale * dt)
	local steerSpeed = STEER_SPEED * sideScale ^ STEER_GROWTH
	local ease = 1 - math.exp(-CATCH_UP_EASE * dt)
	for _, dropped in active do
		local part = dropped.Part
		local itemVelocity = part.AssemblyLinearVelocity
		local across = flatten(itemVelocity)
		local sideways = across:Dot(right)
		local forward = across - right * sideways
		local catchUp = 0
		if dropped.Steerable then
			local behind = lead - (part.Position - current.Start):Dot(current.Direction)
			catchUp = math.clamp((behind - PACK_RADIUS) / CATCH_UP_TIME, 0, current.SlideSpeed * MAX_CATCH_UP)
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
		itemVelocity = forward + right * sideways + Vector3.yAxis * itemVelocity.Y
		part.AssemblyLinearVelocity = itemVelocity

		dropped.Align.CFrame = if ground
			then CFrame.fromRotationBetweenVectors(Vector3.yAxis, ground.Normal) * dropped.Rotation
			else dropped.Rotation
		if ground then
			dropped.GroundY = ground.Position.Y
			if ground.Instance.Name == SLIDE_NAME then
				dropped.SlideY = ground.Position.Y
			end
		end
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

	local behind = -current.Direction
	local offset = (behind * math.cos(FOLLOW_PITCH) + Vector3.yAxis * math.sin(FOLLOW_PITCH)) * FOLLOW_DISTANCE
	-- In front of any wall that would come between, like the funnel's
	local hit = workspace:Raycast(followed, offset, current.WorldRay)
	local distance = if hit then math.max(hit.Distance - WALL_GAP, WALL_GAP) else FOLLOW_DISTANCE
	goalPosition = followed + offset.Unit * distance
	goalLookAt = followed + current.Direction * LOOK_AHEAD

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
		camera.CameraType = Enum.CameraType.Custom
		return
	end

	camera.CFrame = CFrame.lookAt(cameraPosition, cameraLookAt)
	camera.Focus = CFrame.new(cameraLookAt)
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
	cameraPosition = returnCFrame.Position
	cameraLookAt = returnLookAt
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
	worldRay.FilterDescendantsInstances = ignored

	-- Opened on this client only, so nothing else falls through
	for opening in openings do
		opening.CanCollide = false
	end
	PromptController.SetHidden(place, prompt, true)
	SlotController.SetFaded(place, true)
	setFrozen(true)
	HudController.SetDropView(true)
	holdCamera()
end

function DropController.Start()
	ProximityPromptService.PromptTriggered:Connect(function(prompt)
		local place = Places.Find(prompt)
		if place and prompt:FindFirstAncestor(DROP_BUTTON_NAME) then
			startDrop(place, prompt)
		end
	end)
	HudController.ExitRequested:Connect(endDrop)
end

return DropController
