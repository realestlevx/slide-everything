local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Floors = require(ReplicatedStorage.Shared.Floors)
local Places = require(ReplicatedStorage.Shared.Places)

local HudController = require(script.Parent.HudController)

local LocalPlayer = Players.LocalPlayer
local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")

-- The player has left their base once they're past the edge of its ground (BaseMin and BaseMax, see
-- PlaceService), or have fallen this far below the top of it
local EDGE_MARGIN = 2 -- Studs past the edge they can be, on a lip or a ledge, and still count as in it
local FALL_DEPTH = 12 -- Studs
local CHECK_INTERVAL = 0.2 -- Seconds between checks

-- Touching a part with this name anywhere in Workspace sends the player back to their base
local KILL_PART_NAME = "KillPart"
-- Kill parts float: they rock about their own X axis, ROCK_ANGLE either way, and bob up and down,
-- each on its own beat so the two don't move in step. Done on each client, so it's smooth, and
-- touches are checked against where the player sees it
local ROCK_ANGLE = math.rad(1)
local ROCK_PERIOD = 5 -- Seconds to rock there and back
local BOB_HEIGHT = 2 -- Studs above and below where it was built
local BOB_PERIOD = 3.5 -- Seconds to bob up and back down

-- On the way back FadeGui's Fade covers the screen, the character moves to the base's spawn while
-- it's covered, and it fades away again
local FADE_GUI_NAME = "FadeGui"
local FADE_FRAME_NAME = "Fade"
local FADE_IN_INFO = TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local FADE_OUT_INFO = TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
local FADE_DISPLAY_ORDER = 100 -- Over every other gui, which are all lower

-- The top bar's Next and Back buttons step the player up and down their base's floors, going round
-- from the top floor to the bottom and back, so with two floors each goes to the other one. They
-- move straight there, without a fade. Floor 1 is the base's spawn, and each floor above has a
-- Floor<N>Spawn part (see Floors.GetSpawnName)
local SPAWN_OFFSET = Vector3.new(0, 3, 0) -- Above a floor's spawn, as PlaceService puts new characters

local goingHome = false
local killParts: { [BasePart]: CFrame } = {} -- Each kill part -> where it was built

local BaseController = {}

local function getOwnPlace(): Folder?
	for _, place in Places.GetAll() do
		if place:GetAttribute("OwnerUserId") == LocalPlayer.UserId then
			return place
		end
	end
	return nil
end

local function getRoot(): BasePart?
	local character = LocalPlayer.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	return if root and root:IsA("BasePart") then root else nil
end

-- Without its box the base can't be measured, so the player counts as in it
local function isInBase(place: Folder, position: Vector3): boolean
	local low, high = place:GetAttribute("BaseMin"), place:GetAttribute("BaseMax")
	if typeof(low) ~= "Vector3" or typeof(high) ~= "Vector3" then
		return true
	end
	return position.X >= low.X - EDGE_MARGIN
		and position.X <= high.X + EDGE_MARGIN
		and position.Z >= low.Z - EDGE_MARGIN
		and position.Z <= high.Z + EDGE_MARGIN
		and position.Y >= high.Y - FALL_DEPTH
end

local function checkOutside()
	local place = getOwnPlace()
	local root = getRoot()
	HudController.SetOutsideBase(place ~= nil and root ~= nil and not isInBase(place, root.Position))
end

-- Fades the screen to the given transparency and waits for it. Made again on every respawn
local function fade(transparency: number, info: TweenInfo)
	local gui = PlayerGui:FindFirstChild(FADE_GUI_NAME)
	local frame = gui and gui:FindFirstChild(FADE_FRAME_NAME)
	if not (gui and gui:IsA("ScreenGui") and frame and frame:IsA("GuiObject")) then
		return
	end
	gui.DisplayOrder = math.max(gui.DisplayOrder, FADE_DISPLAY_ORDER)
	frame.Visible = true
	local tween = TweenService:Create(frame, info, { BackgroundTransparency = transparency })
	tween:Play()
	tween.Completed:Wait()
end

local function moveTo(cframe: CFrame)
	local character = LocalPlayer.Character
	local root = getRoot()
	if character and root then
		character:PivotTo(cframe)
		root.AssemblyLinearVelocity = Vector3.zero
		root.AssemblyAngularVelocity = Vector3.zero
	end
	checkOutside()
end

-- The base around the spawn is asked for as the screen fades, in case it's streamed out
local function goHome()
	local place = getOwnPlace()
	local home = place and place:GetAttribute("SpawnCFrame")
	if goingHome or typeof(home) ~= "CFrame" or not getRoot() then
		return
	end
	goingHome = true
	task.spawn(pcall, LocalPlayer.RequestStreamAroundAsync, LocalPlayer, home.Position)
	fade(0, FADE_IN_INFO)
	-- Looked up again inside, since the character may have respawned while the screen faded
	moveTo(home)

	fade(1, FADE_OUT_INFO)
	goingHome = false
end

-- Where the player goes on the floor, or nil if it isn't built or its spawn hasn't streamed in
local function getFloorSpawn(place: Folder, number: number): CFrame?
	if number == 1 then
		local home = place:GetAttribute("SpawnCFrame")
		return if typeof(home) == "CFrame" then home else nil
	end
	local floor = place:FindFirstChild(Floors.GetName(number))
	local spawn = floor and floor:FindFirstChild(Floors.GetSpawnName(number))
	return if spawn and spawn:IsA("BasePart") then spawn.CFrame + SPAWN_OFFSET else nil
end

-- The floor the player's on is the one whose spawn is nearest their height
local function stepFloor(step: number)
	local place = getOwnPlace()
	local root = getRoot()
	if goingHome or not (place and root) then
		return
	end
	local count = place:GetAttribute("Floors")
	count = if typeof(count) == "number" then count else 1
	local current, nearest = 1, math.huge
	for number = 1, count do
		local spawn = getFloorSpawn(place, number)
		local gap = if spawn then math.abs(spawn.Y - root.Position.Y) else math.huge
		if gap < nearest then
			current, nearest = number, gap
		end
	end
	local target = getFloorSpawn(place, (current - 1 + step) % count + 1)
	if target then
		moveTo(target)
	end
end

local function watchKillPart(instance: Instance)
	if not (instance:IsA("BasePart") and instance.Name == KILL_PART_NAME) then
		return
	end
	instance.Touched:Connect(function(hit)
		local character = LocalPlayer.Character
		if character and hit:IsDescendantOf(character) then
			task.spawn(goHome)
		end
	end)
	killParts[instance] = instance.CFrame
end

local function floatKillParts()
	local now = os.clock()
	local lift = Vector3.yAxis * math.sin(now * 2 * math.pi / BOB_PERIOD) * BOB_HEIGHT
	local tilt = CFrame.Angles(math.sin(now * 2 * math.pi / ROCK_PERIOD) * ROCK_ANGLE, 0, 0)
	for part, rest in killParts do
		if part.Parent then
			part.CFrame = (rest + lift) * tilt
		else
			killParts[part] = nil
		end
	end
end

function BaseController.Start()
	HudController.HomeRequested:Connect(function()
		task.spawn(goHome)
	end)
	HudController.FloorRequested:Connect(stepFloor)

	-- Kill parts may stream in and out, and come back as new parts
	for _, descendant in workspace:GetDescendants() do
		watchKillPart(descendant)
	end
	workspace.DescendantAdded:Connect(watchKillPart)
	RunService.Heartbeat:Connect(floatKillParts)

	task.spawn(function()
		while true do
			checkOutside()
			task.wait(CHECK_INTERVAL)
		end
	end)
end

return BaseController
