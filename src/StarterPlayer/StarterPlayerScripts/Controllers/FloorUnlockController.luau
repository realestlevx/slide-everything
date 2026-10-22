local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Floors = require(ReplicatedStorage.Shared.Floors)
local Places = require(ReplicatedStorage.Shared.Places)

local BuySlotResult = ReplicatedStorage.Remotes.BuySlotResult
local LocalPlayer = Players.LocalPlayer

-- When the player buys a floor from the sign, it's built up in front of them: the camera flies over to
-- look at it, and its parts drop into place one after another, bottom first, fading in as they come,
-- while the view slowly zooms in. Then the zoom snaps back, the floor's slots fade in and the camera
-- flies back. On their screen only; everyone else just sees the floor appear
local BUILD_TIME = 3.5 -- Seconds from the first part setting off to the last one landing
local PART_TIME = 0.7 -- Seconds each part takes to drop into place
local PART_DROP = 12 -- Studs above where it goes that each part drops from
local PART_TILT = math.rad(25) -- The most a part starts turned from how it lands
local FADE_SHARE = 0.5 -- Share of its drop that a part takes to fade in
-- Left as they are: the see-through floor the items drop through keeps its own look, and invisible
-- parts, like barriers, stay invisible
local KEEP_NAMES = { DropPart = true }
local CAMERA_MOVE = TweenInfo.new(0.6, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)
local VIEW_PITCH = math.rad(30) -- How steeply the camera looks down at the floor
local VIEW_MARGIN = 1.1 -- Room around the floor once the view has zoomed in all the way
local FOV_ZOOM = 15 -- How far the field of view drops while the floor builds
local FOV_ZOOM_IN = TweenInfo.new(BUILD_TIME, Enum.EasingStyle.Sine, Enum.EasingDirection.In)
local FOV_SNAP_BACK = TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local HOLD_TIME = 0.6 -- Seconds the camera stays on the built floor before flying back
local SLOT_FADE = TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local FLOOR_TIMEOUT = 5 -- Seconds to wait for the bought floor to stream in; its slots just show if it's later

type Piece = {
	Part: BasePart,
	Decals: { Decal }, -- Its textures, which fade with it
	From: CFrame,
	To: CFrame,
	Start: number, -- Seconds into the build that it sets off
}

local expected: { [Folder]: number } = {} -- The floor each place's owner just bought, not here yet

local FloorUnlockController = {}

local function getOwnPlace(): Folder?
	for _, place in Places.GetAll() do
		if place:GetAttribute("OwnerUserId") == LocalPlayer.UserId then
			return place
		end
	end
	return nil
end

local function tweenAndWait(instance: Instance, info: TweenInfo, goal: { [string]: any })
	local tween = TweenService:Create(instance, info, goal)
	tween:Play()
	tween.Completed:Wait()
end

-- The floor's slots wait for the floor under them: hidden on this screen while it builds, then faded
-- in. LocalTransparencyModifier leaves the server's own transparencies (like a locked slot's) as they are
local function setSlotsHidden(place: Folder, number: number, hidden: boolean)
	for _, slot in Places.GetSlots(place) do
		if Places.GetSlotFloor(slot) ~= number then
			continue
		end
		for _, descendant in slot:GetDescendants() do
			if not (descendant:IsA("BasePart") or descendant:IsA("Decal")) then
				continue
			end
			if hidden then
				descendant.LocalTransparencyModifier = 1
			else
				TweenService:Create(descendant, SLOT_FADE, { LocalTransparencyModifier = 0 }):Play()
			end
		end
	end
end

local function setHidden(piece: Piece, hidden: number)
	piece.Part.LocalTransparencyModifier = hidden
	for _, decal in piece.Decals do
		decal.LocalTransparencyModifier = hidden
	end
end

-- How far a part reaches below its middle
local function getHalfHeight(part: BasePart): number
	local cframe, size = part.CFrame, part.Size
	return (math.abs(cframe.XVector.Y) * size.X + math.abs(cframe.YVector.Y) * size.Y + math.abs(cframe.ZVector.Y) * size.Z)
		/ 2
end

-- Takes the floor apart straight away, before it's ever seen built: every part that shows is hidden,
-- up above where it goes and turned a little. Gives back the parts in the order they go back, bottom
-- first, each setting off after the one before by a share of the build as big as that part, so rows
-- of little ones don't hold it up
local function takeApart(floor: Model): { Piece }
	local random = Random.new()
	local pieces: { Piece } = {}
	local bottoms: { [Piece]: number } = {}
	for _, part in floor:GetDescendants() do
		if not part:IsA("BasePart") or part.Transparency >= 1 or KEEP_NAMES[part.Name] then
			continue
		end
		local decals = {}
		for _, child in part:GetChildren() do
			if child:IsA("Decal") then -- Textures are Decals too
				table.insert(decals, child)
			end
		end
		local tilt = CFrame.fromAxisAngle(random:NextUnitVector(), random:NextNumber(0, PART_TILT))
		local piece: Piece = {
			Part = part,
			Decals = decals,
			From = (part.CFrame + Vector3.yAxis * PART_DROP) * tilt,
			To = part.CFrame,
			Start = 0,
		}
		-- To a tenth of a stud, so parts side by side count as level and go along their row
		bottoms[piece] = math.round((part.Position.Y - getHalfHeight(part)) * 10)
		table.insert(pieces, piece)
	end
	table.sort(pieces, function(a, b)
		if bottoms[a] ~= bottoms[b] then
			return bottoms[a] < bottoms[b]
		elseif a.To.Position.Z ~= b.To.Position.Z then
			return a.To.Position.Z < b.To.Position.Z
		end
		return a.To.Position.X < b.To.Position.X
	end)

	local total = 0
	for _, piece in pieces do
		total += piece.Part.Size.Magnitude
	end
	-- The last one sets off just in time to land as the build ends
	local beforeLast = total - (if #pieces > 0 then pieces[#pieces].Part.Size.Magnitude else 0)
	local before = 0
	for _, piece in pieces do
		piece.Start = if beforeLast > 0 then before / beforeLast * (BUILD_TIME - PART_TIME) else 0
		before += piece.Part.Size.Magnitude
		piece.Part.CFrame = piece.From
		setHidden(piece, 1)
	end
	return pieces
end

-- Where the piece is the given number of seconds into the build. It lands a little low and settles
-- back up, and is fully faded in partway down
local function move(piece: Piece, elapsed: number)
	local alpha = math.clamp((elapsed - piece.Start) / PART_TIME, 0, 1)
	local drop = TweenService:GetValue(alpha, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
	local turn = TweenService:GetValue(alpha, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	local shown = TweenService:GetValue(math.min(alpha / FADE_SHARE, 1), Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	piece.Part.CFrame = piece.From.Rotation:Lerp(piece.To.Rotation, turn) + piece.From.Position:Lerp(piece.To.Position, drop)
	setHidden(piece, 1 - shown)
end

-- Yields until every piece is back in place, BUILD_TIME from now
local function build(pieces: { Piece })
	local started = os.clock()
	while true do
		local elapsed = os.clock() - started
		for _, piece in pieces do
			move(piece, elapsed)
		end
		if elapsed >= BUILD_TIME then
			return
		end
		RunService.RenderStepped:Wait()
	end
end

-- Looking down at the middle of the box from the side the given point is on, just far enough back for
-- all of it to fit in view at the given field of view
local function getView(box: CFrame, size: Vector3, from: Vector3, fov: number): CFrame
	local away = from - box.Position
	away = Vector3.new(away.X, 0, away.Z)
	away = if away.Magnitude > 0.01 then away.Unit else Vector3.zAxis
	local back = away * math.cos(VIEW_PITCH) + Vector3.yAxis * math.sin(VIEW_PITCH)
	local look = -back
	local right = look:Cross(Vector3.yAxis).Unit
	local up = right:Cross(look)

	-- Half the box's size along the direction
	local function reach(direction: Vector3): number
		return (
			math.abs(box.XVector:Dot(direction)) * size.X
			+ math.abs(box.YVector:Dot(direction)) * size.Y
			+ math.abs(box.ZVector:Dot(direction)) * size.Z
		) / 2
	end

	local viewport = workspace.CurrentCamera.ViewportSize
	local aspect = if viewport.Y > 0 then viewport.X / viewport.Y else 16 / 9
	local tanUp = math.tan(math.rad(fov) / 2)
	local distance = math.max(reach(right) / (tanUp * aspect), reach(up) / tanUp) * VIEW_MARGIN + reach(look)
	return CFrame.lookAt(box.Position + back * distance, box.Position)
end

local function reveal(place: Folder, number: number, pieces: { Piece }, box: CFrame, size: Vector3)
	-- Leaves the camera alone while something else has it, like a drop following its items
	local camera = workspace.CurrentCamera
	local moveCamera = camera.CameraType == Enum.CameraType.Custom
	local returnCFrame = camera.CFrame
	local restingFov = camera.FieldOfView
	if moveCamera then
		camera.CameraType = Enum.CameraType.Scriptable
		-- Framed for the end of the zoom, so the whole floor is still in view once it's built
		local view = getView(box, size, returnCFrame.Position, restingFov - FOV_ZOOM)
		tweenAndWait(camera, CAMERA_MOVE, { CFrame = view })
		TweenService:Create(camera, FOV_ZOOM_IN, { FieldOfView = restingFov - FOV_ZOOM }):Play()
	end

	build(pieces)
	setSlotsHidden(place, number, false)

	if moveCamera then
		TweenService:Create(camera, FOV_SNAP_BACK, { FieldOfView = restingFov }):Play()
		task.wait(HOLD_TIME)
		tweenAndWait(camera, CAMERA_MOVE, { CFrame = returnCFrame })
		camera.CameraType = Enum.CameraType.Custom
	end
end

-- The bought floor has arrived: it's taken apart at once, before it's ever seen built, and built back
-- up in front of the player
local function onFloorArrived(place: Folder, number: number, floor: Model)
	expected[place] = nil
	local box, size = floor:GetBoundingBox()
	local pieces = takeApart(floor)
	task.spawn(reveal, place, number, pieces, box, size)
end

-- The server sends this before the floor, so it's known to be this player's purchase when it lands
local function onBought(bought: boolean, number: number?)
	if not bought or typeof(number) ~= "number" then
		return
	end
	local place = getOwnPlace()
	if not place then
		return
	end

	setSlotsHidden(place, number, true)
	local floor = place:FindFirstChild(Floors.GetName(number))
	if floor and floor:IsA("Model") then
		onFloorArrived(place, number, floor)
		return
	end

	expected[place] = number
	task.delay(FLOOR_TIMEOUT, function()
		if expected[place] == number then
			expected[place] = nil
			setSlotsHidden(place, number, false)
		end
	end)
end

function FloorUnlockController.Start()
	BuySlotResult.OnClientEvent:Connect(onBought)
	for _, place in Places.GetAll() do
		place.ChildAdded:Connect(function(child)
			local number = expected[place]
			if number and child.Name == Floors.GetName(number) and child:IsA("Model") then
				onFloorArrived(place, number, child)
			end
		end)
	end
end

return FloorUnlockController
