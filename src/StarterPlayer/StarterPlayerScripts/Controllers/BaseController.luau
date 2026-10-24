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
-- each on its own beat so the two don't move in step. Everything else in a kill part's own folder or
-- model, like the water's surface laid over it, floats along with it as one piece; a kill part right
-- in Workspace or in a place floats alone. Done on each client, so it's smooth, and touches are
-- checked against where the player sees it
local ROCK_ANGLE = math.rad(1)
local ROCK_PERIOD = 5 -- Seconds to rock there and back
local BOB_HEIGHT = 2 -- Studs above and below where it was built
local BOB_PERIOD = 3.5 -- Seconds to bob up and back down

-- On the way back to the base, or to the market, FadeGui's Fade covers the screen, the character
-- moves to the spawn there while it's covered, and it fades away again
local FADE_GUI_NAME = "FadeGui"
local FADE_FRAME_NAME = "Fade"
local FADE_IN_INFO = TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local FADE_OUT_INFO = TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
local FADE_DISPLAY_ORDER = 100 -- Over every other gui, which are all lower
-- The market's spawn is on Workspace.Market as SpawnCFrame (see PlaceService)
local MARKET_NAME = "Market"

-- The top bar's Next and Back buttons step the player up and down their base's floors, going round
-- from the top floor to the bottom and back, so with two floors each goes to the other one. They
-- move straight there, without a fade. Floor 1 is the base's spawn, and each floor above has a
-- Floor<N>Spawn part (see Floors.GetSpawnName)
local SPAWN_OFFSET = Vector3.new(0, 3, 0) -- Above a floor's spawn, as PlaceService puts new characters

type Float = {
	Center: CFrame, -- Where the kill part was built, which everything floating with it rocks about
	Parts: { [BasePart]: CFrame }, -- The kill part and everything floating with it -> where each was built
	Connection: RBXScriptConnection?, -- Picks up parts of its folder that stream in later
}

local travelling = false
local floats: { [BasePart]: Float } = {} -- Each kill part -> what floats with it

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

-- How many floors the place has for its owner, counting the first (see FloorService)
local function getFloorCount(place: Folder): number
	local count = place:GetAttribute("Floors")
	return if typeof(count) == "number" then count else 1
end

local function checkOutside()
	local place = getOwnPlace()
	local root = getRoot()
	HudController.SetOutsideBase(place ~= nil and root ~= nil and not isInBase(place, root.Position))
	HudController.SetFloorsUnlocked(place ~= nil and getFloorCount(place) > 1)
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

-- What's around the spawn is asked for as the screen fades, in case it's streamed out
local function travelTo(target: unknown)
	if travelling or typeof(target) ~= "CFrame" or not getRoot() then
		return
	end
	travelling = true
	task.spawn(pcall, LocalPlayer.RequestStreamAroundAsync, LocalPlayer, target.Position)
	fade(0, FADE_IN_INFO)
	-- Looked up again inside, since the character may have respawned while the screen faded
	moveTo(target)

	fade(1, FADE_OUT_INFO)
	travelling = false
end

local function goHome()
	local place = getOwnPlace()
	travelTo(place and place:GetAttribute("SpawnCFrame"))
end

local function goToMarket()
	local market = workspace:FindFirstChild(MARKET_NAME)
	travelTo(market and market:GetAttribute("SpawnCFrame"))
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
	if travelling or not (place and root) then
		return
	end
	local count = getFloorCount(place)
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

	local float: Float = { Center = instance.CFrame, Parts = { [instance] = instance.CFrame } }
	-- Another kill part in the same folder floats on its own
	local function ride(descendant: Instance)
		if descendant:IsA("BasePart") and descendant.Name ~= KILL_PART_NAME and not float.Parts[descendant] then
			float.Parts[descendant] = descendant.CFrame
		end
	end
	local group = instance.Parent
	if group and group ~= workspace and not Places.Find(instance) then
		for _, descendant in group:GetDescendants() do
			ride(descendant)
		end
		float.Connection = group.DescendantAdded:Connect(ride)
	end
	floats[instance] = float
end

local function floatKillParts()
	local now = os.clock()
	local lift = Vector3.yAxis * math.sin(now * 2 * math.pi / BOB_PERIOD) * BOB_HEIGHT
	local tilt = CFrame.Angles(math.sin(now * 2 * math.pi / ROCK_PERIOD) * ROCK_ANGLE, 0, 0)
	for killPart, float in floats do
		if not killPart.Parent then
			if float.Connection then
				float.Connection:Disconnect()
			end
			floats[killPart] = nil
			continue
		end
		-- Moves everything the way the kill part moves from where it was built
		local move = (float.Center + lift) * tilt * float.Center:Inverse()
		for part, rest in float.Parts do
			if part.Parent then
				part.CFrame = move * rest
			else
				float.Parts[part] = nil
			end
		end
	end
end

function BaseController.Start()
	HudController.HomeRequested:Connect(function()
		task.spawn(goHome)
	end)
	HudController.MarketRequested:Connect(function()
		task.spawn(goToMarket)
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
