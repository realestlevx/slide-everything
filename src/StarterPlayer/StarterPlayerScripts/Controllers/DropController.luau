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

local CollectController = require(script.Parent.CollectController)
local HudController = require(script.Parent.HudController)
local PromptController = require(script.Parent.PromptController)
local SlotController = require(script.Parent.SlotController)

local DropResult = ReplicatedStorage.Remotes.DropResult
local LocalPlayer = Players.LocalPlayer

local DROP_BUTTON_NAME = "Drop_Button" -- Model in a place holding the prompt that drops its items
-- The floor under a place's slots, and under each built floor's slots, which opens for the items to fall through
local DROP_FLOOR_NAME = "DropPart"
-- Invisible part across the funnel. Items can be steered once they're below it, whether or not they
-- went through it: some slide down past its end
local STEER_ZONE_NAME = "SteerEnable"
local MULTIPLIER_ATTRIBUTE = "Multiplier" -- On the walls across the slide. The last one is the end of it
local SLOT_ITEM_NAME = "SlotItem"

-- Dropped items barely grip, and their grip outweighs the slide's, so they slide down even the
-- gentlest ramp. SLIDE_SPEED then keeps them from going faster than that down the slide;
-- falling isn't slowed. The Sliding Speed upgrade raises it by SPEED_SHARE of its own rise, so 3x
-- pays 3x but slides at 2x, and there's still time to steer
local ITEM_PHYSICS = PhysicalProperties.new(0.7, 0.05, 0.2, 100, 1)
local SLIDE_SPEED = 30 -- Studs per second, before any Sliding Speed upgrade
local SPEED_SHARE = 0.5
local STEER_SPEED = 15 -- Studs per second sideways while the player steers
-- Past the steering zone, items grip sideways like sleds: they slide where they're steered and stop
-- drifting once let go, instead of skidding off. How quickly they take up a new sideways speed;
-- higher is tighter
local SIDE_GRIP = 8
-- They're drawn in toward the middle of the pack, so they slide down together and steer as one
local PACK_RADIUS = 3 -- Studs either side of the middle where nothing pulls
local PACK_PULL = 2 -- Studs per second of pull for every stud further out than that
local MAX_PACK_PULL = 8 -- Studs per second
-- Items stay the way up they were dropped instead of tumbling, tilted to lie along the ground under them
local TILT_RESPONSIVENESS = 25
local GROUND_PROBE = 8 -- Studs below an item that the ground it lies along is looked for
local STOPPED_SPEED = 2 -- Studs per second. An item slower than this for STOP_TIME has come to rest
local STOP_TIME = 1
local FALL_LIMIT = 150 -- Studs below where it was dropped from; an item lower than this went off the slide
local END_PAUSE = 0.75 -- Seconds the camera stays on where the items ended up
local ITEM_FADE_INFO = TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

-- The camera chases the items from straight behind, looking down the slide, raised by FOLLOW_PITCH.
-- It follows them down the slide and up and down, but stays over the slide's middle and only turns a
-- little toward them, so steering moves the items across the screen instead of swinging the view.
-- High and far enough back to keep items steered out to the sides in sight
local FOLLOW_DISTANCE = 36 -- Studs
local FOLLOW_PITCH = math.rad(50)
-- Share of the way across to the items that the camera looks, from the slide's middle. 0 looks
-- straight down the slide; 1 looks right at them
local SIDE_LOOK = 0.2
local WALL_GAP = 1 -- Studs the camera keeps in front of a wall between it and the items
-- How quickly the camera catches up with where it should be; higher is snappier. The view turns
-- faster than the camera moves, so the items stay in frame while it glides after them
local MOVE_SHARPNESS = 4
local LOOK_SHARPNESS = 10
local RETURN_SHARPNESS = 6
local RETURNED_DISTANCE = 0.05 -- Studs. Once back this close to where it was, the camera is handed back
local CAMERA_STEP_NAME = "DropCamera"
local STREAM_INTERVAL = 0.5 -- Seconds between asks for the slide around the items to be loaded

type DroppedItem = {
	Item: Items.Item,
	Level: number,
	SlotKey: string, -- The slot it was dropped from, which the server pays it out by
	Pay: number, -- What it's earned so far, shown while it drops. Fixed once it's done
	Part: BasePart, -- The item's mesh, which the rest of it is welded to
	Parts: { BasePart },
	Rotation: CFrame, -- The way up it was dropped, which it keeps
	Align: AlignOrientation, -- Holds it that way up, tilted along the ground
	StillFor: number, -- Seconds it has been slower than STOPPED_SPEED
	Steerable: boolean, -- Has gone below the steering zone
	Multiplier: number, -- Of the last wall it passed
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
	StartY: number,
	Start: Vector3, -- Where the way down the slide is measured from
	Direction: Vector3, -- Which way the slide runs, across the ground
	EndWall: BasePart?, -- The last multiplier wall, at the end of the slide
	Length: number, -- Studs from Start to EndWall, along Direction
	SteerZone: BasePart?, -- Without one, items can be steered from the start
	Ending: boolean,
	Distance: number, -- Studs down the slide that the furthest item has got, shown while it drops
	Speed: number, -- The owner's Sliding Speed upgrade, which multiplies the pay
	SlideSpeed: number, -- Studs per second items are held to down the slide
	-- Finds the walls between the camera and the items and the ground under the items, but not the items
	WorldRay: RaycastParams,
}

local drop: Drop? = nil
local lastDropAt = -math.huge
local walls: { [BasePart]: boolean } = {} -- Every multiplier wall seen so far; they stream in and out

-- The camera eases from where it is and looks toward its goals every frame, so it never jumps
local cameraHeld = false -- Following the items, or still gliding back afterwards
local cameraPosition = Vector3.zero
local cameraLookAt = Vector3.zero
local goalPosition = Vector3.zero
local goalLookAt = Vector3.zero
local returnCFrame = CFrame.identity -- Where the camera was before the drop
local returnLookAt = Vector3.zero
local lastStreamRequest = 0

local DropController = {}

-- A point straight ahead of the camera, as far away as its focus
local function getLookAt(cframe: CFrame, focus: Vector3): Vector3
	return cframe.Position + cframe.LookVector * (focus - cframe.Position).Magnitude
end

local function flatten(vector: Vector3): Vector3
	return Vector3.new(vector.X, 0, vector.Z)
end

-- The share of the slide the item has covered, 0 to 1. With no end wall loaded, it counts as all of it
local function getProgress(current: Drop, position: Vector3): number
	if not current.EndWall or current.Length <= 0 then
		return 1
	end
	return math.clamp((position - current.Start):Dot(current.Direction) / current.Length, 0, 1)
end

-- What the drop has made so far and how far it's got, on screen. Each item still on the slide counts
-- what it would earn if it stopped where it is. The server works out the real pay the same way
local function showStats(current: Drop)
	local cash = 0
	for _, dropped in current.Items do
		if not dropped.Done then
			local position = dropped.Part.Position
			local progress = getProgress(current, position)
			dropped.Pay = Drops.GetPay(dropped.Item, dropped.Level, progress, dropped.Multiplier, current.Speed)
			current.Distance = math.max(current.Distance, (position - current.Start):Dot(current.Direction))
		end
		cash += dropped.Pay
	end
	HudController.SetDropStats(cash, current.Distance)
end

-- The item's run is over: it leaves the slide for the pile on the collect pad, and the server hears
-- how far it got and which wall it passed last, which it pays out
local function finishItem(current: Drop, dropped: DroppedItem, progress: number)
	if dropped.Done then
		return
	end
	dropped.Pay = Drops.GetPay(dropped.Item, dropped.Level, progress, dropped.Multiplier, current.Speed)
	dropped.Done = true
	DropResult:FireServer(dropped.SlotKey, progress, dropped.Multiplier)
	CollectController.AddToPile(current.Place, dropped.Item)

	for _, part in dropped.Parts do
		TweenService:Create(part, ITEM_FADE_INFO, { LocalTransparencyModifier = 1 }):Play()
	end
	task.delay(ITEM_FADE_INFO.Time, dropped.Part.Destroy, dropped.Part)
end

local function onItemTouched(current: Drop, dropped: DroppedItem, hit: BasePart)
	if dropped.Done or drop ~= current then
		return
	end
	local multiplier = hit:GetAttribute(MULTIPLIER_ATTRIBUTE)
	if typeof(multiplier) == "number" then
		dropped.Multiplier = multiplier
		if hit == current.EndWall then
			finishItem(current, dropped, 1)
		end
	end
end

-- A physical copy of the item where its display floats in the slot. Made on this client only, so
-- the server doesn't simulate anyone's drop
local function spawnCopy(current: Drop, item: Items.Item, level: number, slotKey: string, cframe: CFrame)
	local copy, parts = PhysicalItem.Create(item, cframe, ITEM_PHYSICS)
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
		Pay = 0,
		Part = copy,
		Parts = parts,
		Rotation = cframe.Rotation,
		Align = align,
		StillFor = 0,
		Steerable = false,
		Multiplier = 1,
		Done = false,
	}
	for _, part in parts do
		part.Touched:Connect(function(hit)
			onItemTouched(current, dropped, hit)
		end)
	end
	copy.Parent = workspace
	table.insert(current.Items, dropped)
end

-- The character stands still through the drop, so the steering keys don't walk it off
local function setFrozen(frozen: boolean)
	local character = LocalPlayer.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		root.Anchored = frozen
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
		finishItem(current, dropped, getProgress(current, dropped.Part.Position))
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

-- Items that come to rest or go off the slide finish where they are. The rest are held to
-- the slide speed down the slide, lie along the ground and, past the steering zone, go where they're
-- steered as a pack. The camera aims at them, and once none are left, the drop ends after a moment
local function followItems(current: Drop, dt: number)
	local active: { DroppedItem } = {}
	for _, dropped in current.Items do
		if dropped.Done then
			continue
		end
		local part = dropped.Part
		if not part.Parent or part.Position.Y < current.StartY - FALL_LIMIT then
			finishItem(current, dropped, getProgress(current, part.Position))
			continue
		end
		local still = part.AssemblyLinearVelocity.Magnitude < STOPPED_SPEED
		dropped.StillFor = if still then dropped.StillFor + dt else 0
		if dropped.StillFor >= STOP_TIME then
			finishItem(current, dropped, getProgress(current, part.Position))
		else
			table.insert(active, dropped)
		end
	end
	showStats(current)

	if #active == 0 or os.clock() - current.StartedAt > Drops.MAX_TIME then
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

	local center = Vector3.zero
	for _, dropped in active do
		center += dropped.Part.Position
	end
	center /= #active

	local steer = HudController.GetSteer()
	local right = current.Direction:Cross(Vector3.yAxis)
	local grip = 1 - math.exp(-SIDE_GRIP * dt)
	for _, dropped in active do
		local part = dropped.Part
		local itemVelocity = part.AssemblyLinearVelocity
		local across = flatten(itemVelocity)
		local sideways = across:Dot(right)
		local forward = across - right * sideways
		if forward.Magnitude > current.SlideSpeed then
			forward = forward.Unit * current.SlideSpeed
		end
		local zone = current.SteerZone
		if not dropped.Steerable and (not zone or zone.CFrame:PointToObjectSpace(part.Position).Y < 0) then
			dropped.Steerable = true
		end
		if dropped.Steerable then
			local apart = (center - part.Position):Dot(right)
			local outside = math.max(math.abs(apart) - PACK_RADIUS, 0) * math.sign(apart)
			local pull = math.clamp(outside * PACK_PULL, -MAX_PACK_PULL, MAX_PACK_PULL)
			sideways += (steer * STEER_SPEED + pull - sideways) * grip
		end
		itemVelocity = forward + right * sideways + Vector3.yAxis * itemVelocity.Y
		part.AssemblyLinearVelocity = itemVelocity

		local ground = workspace:Raycast(part.Position, -Vector3.yAxis * GROUND_PROBE, current.WorldRay)
		dropped.Align.CFrame = if ground
			then CFrame.fromRotationBetweenVectors(Vector3.yAxis, ground.Normal) * dropped.Rotation
			else dropped.Rotation
	end

	-- The pack's middle, moved across onto the line down the middle of the slide from Start
	local packSide = (center - current.Start):Dot(right)
	local focus = center - right * packSide

	local behind = -current.Direction
	local offset = (behind * math.cos(FOLLOW_PITCH) + Vector3.yAxis * math.sin(FOLLOW_PITCH)) * FOLLOW_DISTANCE
	-- In front of any wall that would come between, like the funnel's
	local hit = workspace:Raycast(focus, offset, current.WorldRay)
	local distance = if hit then math.max(hit.Distance - WALL_GAP, WALL_GAP) else FOLLOW_DISTANCE
	goalPosition = focus + offset.Unit * distance
	goalLookAt = focus + right * packSide * SIDE_LOOK

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
	cameraPosition = cameraPosition:Lerp(goalPosition, 1 - math.exp(-moveSharpness * dt))
	cameraLookAt = cameraLookAt:Lerp(goalLookAt, 1 - math.exp(-lookSharpness * dt))

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

-- The wall furthest down the slide, and how far along the slide it is
local function findEndWall(start: Vector3, direction: Vector3): (BasePart?, number)
	local endWall, length = nil, 0
	for wall in walls do
		local along = (wall.Position - start):Dot(direction)
		if wall:IsDescendantOf(workspace) and along > length then
			endWall, length = wall, along
		end
	end
	return endWall, length
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
	local start = if floor then floor.Position else toDrop[1].CFrame.Position
	-- The slide runs toward the floor's -X side
	local direction = flatten(if floor then -floor.CFrame.RightVector else -Vector3.xAxis).Unit
	local endWall, length = findEndWall(start, direction)
	local zone = place:FindFirstChild(STEER_ZONE_NAME, true)

	local worldRay = RaycastParams.new()
	worldRay.FilterType = Enum.RaycastFilterType.Exclude
	worldRay.RespectCanCollide = true

	-- The server keeps the level on the place for everyone, and pays by the same one
	local speedLevel = place:GetAttribute("SlideSpeedLevel")
	local speed = SignUpgrades.GetValue("SlideSpeed", if typeof(speedLevel) == "number" then speedLevel else 1)

	local current: Drop = {
		Place = place,
		Prompt = prompt,
		Floor = floor,
		Openings = openings,
		Items = {},
		StartedAt = os.clock(),
		StartY = startY,
		Start = start,
		Direction = direction,
		EndWall = endWall,
		Length = length,
		SteerZone = if zone and zone:IsA("BasePart") then zone else nil,
		Ending = false,
		Distance = 0,
		Speed = speed,
		SlideSpeed = SLIDE_SPEED * (1 + (speed - 1) * SPEED_SHARE),
		WorldRay = worldRay,
	}
	drop = current
	lastDropAt = current.StartedAt

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

local function watchWall(instance: Instance)
	if instance:IsA("BasePart") and typeof(instance:GetAttribute(MULTIPLIER_ATTRIBUTE)) == "number" then
		walls[instance] = true
	end
end

function DropController.Start()
	for _, descendant in workspace:GetDescendants() do
		watchWall(descendant)
	end
	workspace.DescendantAdded:Connect(watchWall)
	workspace.DescendantRemoving:Connect(function(descendant)
		walls[descendant :: any] = nil
	end)

	ProximityPromptService.PromptTriggered:Connect(function(prompt)
		local place = Places.Find(prompt)
		if place and prompt:FindFirstAncestor(DROP_BUTTON_NAME) then
			startDrop(place, prompt)
		end
	end)
	HudController.ExitRequested:Connect(endDrop)
end

return DropController
