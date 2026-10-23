local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Drops = require(ReplicatedStorage.Shared.Drops)
local Places = require(ReplicatedStorage.Shared.Places)
local SignUpgrades = require(ReplicatedStorage.Shared.SignUpgrades)

local LocalPlayer = Players.LocalPlayer

-- The multiplier walls across the slide. Each one's text shows its Multiplier attribute plus this
-- player's Slide upgrade, so it can't say something different from what the wall pays them, and
-- everyone sees the walls at their own multipliers. They're tall and wide enough to fill the view as
-- the camera nears them, so they fade out as it closes in, text and all, and back in once it's gone by.
-- Walls with SideToSide on glide across the slide (see Drops.GetWallSide). Only this client moves
-- them; the server's copy stays where it was built
local VALUE_LABEL_NAME = "Value" -- The TextLabel on a wall that shows its multiplier
-- The floor in each place that the way down the slide is measured from (see Drops.GetSlideLine)
local DROP_FLOOR_NAME = "DropPart"
-- Studs from the camera to the nearest point of a wall. The drop camera trails the items by about 30
-- studs, so a wall in their way only starts fading once they've reached it: the player sees them go
-- through it, or miss it, before it fades for the camera to pass through
local FADE_START = 25 -- Where it starts fading
local FADE_END = 8 -- Where it's gone
local STEP_NAME = "MultiplierWallFade"

type Wall = {
	Home: CFrame, -- Where it was built
	Side: number, -- Studs right of there that it's been moved to
	Fade: number, -- 0 as it was built; 1 gone
	-- Each of its labels' and strokes' own transparency, which they fade from
	Labels: { [TextLabel]: number },
	Strokes: { [UIStroke]: number },
	Connections: { RBXScriptConnection },
}

local walls: { [BasePart]: Wall } = {} -- Every multiplier wall loaded now; they stream in and out
local slideRight: Vector3? = nil -- To the right looking down the slide, once a place's floor has loaded

local MultiplierWallController = {}

-- Every place drops onto the same slide, so any place's floor gives the way down it. Down -X until
-- one has loaded
local function getRight(): Vector3
	if slideRight then
		return slideRight
	end
	for _, place in Places.GetAll() do
		local floor = place:FindFirstChild(DROP_FLOOR_NAME)
		if floor and floor:IsA("BasePart") then
			local _, direction = Drops.GetSlideLine(floor)
			local right = direction:Cross(Vector3.yAxis)
			slideRight = right
			return right
		end
	end
	return -Vector3.xAxis:Cross(Vector3.yAxis)
end

local function fadeFrom(transparency: number, fade: number): number
	return transparency + (1 - transparency) * fade
end

local function applyFade(part: BasePart, wall: Wall)
	part.LocalTransparencyModifier = wall.Fade
	for label, transparency in wall.Labels do
		label.TextTransparency = fadeFrom(transparency, wall.Fade)
	end
	for stroke, transparency in wall.Strokes do
		stroke.Transparency = fadeFrom(transparency, wall.Fade)
	end
end

-- 0 while the camera's FADE_START or further from the wall, rising to 1 once it's within FADE_END
local function getFade(part: BasePart, from: Vector3): number
	local offset = part.CFrame:PointToObjectSpace(from)
	local half = part.Size / 2
	local distance = (offset - offset:Max(-half):Min(half)).Magnitude
	return math.clamp((FADE_START - distance) / (FADE_START - FADE_END), 0, 1)
end

-- This player's Slide upgrade, kept by the server on the place they own. 1x without a place
local function getSlide(): number
	for _, place in Places.GetAll() do
		if place:GetAttribute("OwnerUserId") == LocalPlayer.UserId then
			local level = place:GetAttribute("SlideLevel")
			return SignUpgrades.GetValue("Slide", if typeof(level) == "number" then level else 1)
		end
	end
	return 1
end

-- Written the way the drop HUD shows the multiplier
local function showMultiplier(part: BasePart, wall: Wall)
	if not Drops.IsWall(part) then
		return
	end
	local multiplier = Drops.GetMultiplier(part, getSlide())
	for label in wall.Labels do
		if label.Name == VALUE_LABEL_NAME then
			label.Text = `{multiplier}x`
		end
	end
end

local function showAll()
	for part, wall in walls do
		showMultiplier(part, wall)
	end
end

-- A label or stroke on the wall, which may arrive after the wall itself
local function trackPiece(part: BasePart, wall: Wall, instance: Instance)
	if instance:IsA("TextLabel") then
		wall.Labels[instance] = instance.TextTransparency
		instance.TextTransparency = fadeFrom(instance.TextTransparency, wall.Fade)
		showMultiplier(part, wall)
	elseif instance:IsA("UIStroke") then
		wall.Strokes[instance] = instance.Transparency
		instance.Transparency = fadeFrom(instance.Transparency, wall.Fade)
	end
end

local function track(instance: Instance)
	if walls[instance :: any] or not Drops.IsWall(instance) then
		return
	end
	local part = instance :: BasePart
	local wall: Wall = {
		Home = part.CFrame,
		Side = 0,
		Fade = 0,
		Labels = {},
		Strokes = {},
		Connections = {},
	}
	walls[part] = wall
	for _, descendant in part:GetDescendants() do
		trackPiece(part, wall, descendant)
	end
	table.insert(
		wall.Connections,
		part.DescendantAdded:Connect(function(descendant)
			trackPiece(part, wall, descendant)
		end)
	)
	table.insert(
		wall.Connections,
		part:GetAttributeChangedSignal(Drops.MULTIPLIER_ATTRIBUTE):Connect(function()
			showMultiplier(part, wall)
		end)
	)
end

-- Put back as it was built, in case the same wall streams back in
local function untrack(instance: Instance)
	local wall = walls[instance :: any]
	if not wall then
		return
	end
	walls[instance :: any] = nil
	for _, connection in wall.Connections do
		connection:Disconnect()
	end
	local part = instance :: BasePart
	if wall.Side ~= 0 then
		part.CFrame = wall.Home
	end
	wall.Fade = 0
	applyFade(part, wall)
end

local function onRenderStep()
	local from = workspace.CurrentCamera.CFrame.Position
	local time = workspace:GetServerTimeNow()
	local right = getRight()
	for part, wall in walls do
		local side = Drops.GetWallSide(part, time)
		if side ~= wall.Side then
			wall.Side = side
			part.CFrame = wall.Home + right * side
		end

		local fade = getFade(part, from)
		if fade ~= wall.Fade then
			wall.Fade = fade
			applyFade(part, wall)
		end
	end
end

function MultiplierWallController.Start()
	for _, descendant in workspace:GetDescendants() do
		track(descendant)
	end
	workspace.DescendantAdded:Connect(track)
	workspace.DescendantRemoving:Connect(untrack)
	-- The walls' text changes with this player's Slide upgrade, and when they claim or leave a place
	for _, place in Places.GetAll() do
		place:GetAttributeChangedSignal("OwnerUserId"):Connect(showAll)
		place:GetAttributeChangedSignal("SlideLevel"):Connect(showAll)
	end
	-- After the drop camera has moved for the frame, so walls fade by where it is now
	RunService:BindToRenderStep(STEP_NAME, Enum.RenderPriority.Camera.Value + 2, onRenderStep)
end

return MultiplierWallController
