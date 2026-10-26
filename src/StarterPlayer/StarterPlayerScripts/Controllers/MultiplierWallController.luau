local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Drops = require(ReplicatedStorage.Shared.Drops)
local Places = require(ReplicatedStorage.Shared.Places)
local SignUpgrades = require(ReplicatedStorage.Shared.SignUpgrades)

local LocalPlayer = Players.LocalPlayer

-- The multiplier walls across the slide. Each one's text shows its Multiplier attribute plus this
-- player's Slide upgrade, and what the walls their drop's gone through have raised it by (see
-- SetHits), so it can't say something different from what the wall pays them, and everyone sees the
-- walls at their own multipliers. They're tall and wide enough to fill the view as
-- the camera nears them, so they fade out as it closes in, text and all, and back in once it's gone by.
-- Walls with SideToSide on glide across the slide (see Drops.GetWallSide). Only this client moves
-- them; the server's copy stays where it was built
local VALUE_LABEL_NAME = "Value" -- The TextLabel on a wall that shows its multiplier
-- The floor in each place that the way down the slide is measured from (see Drops.GetSlideLine)
local DROP_FLOOR_NAME = "DropPart"
-- Studs from the camera to the nearest point of a wall. The drop camera trails the items by about 30
-- studs, so a wall in their way only starts fading once they've reached it: the player sees them go
-- through it, or miss it, before it fades for the camera to pass through. Both go as much further as
-- the drop camera has backed off to keep a spread-out pack in view (see SetFadeScale)
local FADE_START = 25 -- Where it starts fading
local FADE_END = 8 -- Where it's gone
local STEP_NAME = "MultiplierWallFade"
-- When one of this player's items touches a wall, so its multiplier counts, the wall flashes white,
-- grows a little, then shrinks away down into the slide as it fades out. A copy of it does: the wall
-- itself is only hidden, so the items behind still touch it. It grows back up once they've gone by
local FLASH_COLOR = Color3.new(1, 1, 1)
local FLASH_TRANSPARENCY = 0.1 -- Of the wall, as it flashes; the text goes white
local FLASH_INFO = TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out) -- Back to its colors
local POP_SCALE = 1.2 -- Times its size that it grows to as it flashes
local POP_TIME = 0.1 -- Seconds growing
local SHRINK_TIME = 0.3 -- Seconds shrinking and fading out after that
local RETURN_DELAY = 2.5 -- Seconds after it's touched that it grows back
local RETURN_TIME = 0.35

-- The copy of a wall that flashes and shrinks while the wall's hidden
type Pop = {
	Copy: BasePart,
	Labels: { [TextLabel]: number },
	Strokes: { [UIStroke]: number },
	Size: Vector3, -- The wall's
	Started: number, -- os.clock() when it was touched
	Vanish: number, -- 0 shown; 1 faded out, as it shrinks away
}

type Wall = {
	Home: CFrame, -- Where it was built
	Side: number, -- Studs right of there that it's been moved to
	Fade: number, -- 0 as it was built; 1 gone
	-- Each of its labels' and strokes' own transparency, which they fade from
	Labels: { [TextLabel]: number },
	Strokes: { [UIStroke]: number },
	Connections: { RBXScriptConnection },
	Pop: Pop?, -- Since one of this player's items touched it, until it's grown back
}

local walls: { [BasePart]: Wall } = {} -- Every multiplier wall loaded now; they stream in and out
local slideRight: Vector3? = nil -- To the right looking down the slide, once a place's floor has loaded
local fadeScale = 1 -- Times FADE_START and FADE_END that walls fade at (see SetFadeScale)
local hits = 0 -- Walls this player's drop has gone through, which raise the rest (see SetHits)

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

-- Hidden while its copy shrinks away and grows back
local function getHidden(wall: Wall): number
	return if wall.Pop then 1 else wall.Fade
end

local function fadePieces(
	part: BasePart,
	labels: { [TextLabel]: number },
	strokes: { [UIStroke]: number },
	fade: number
)
	part.LocalTransparencyModifier = fade
	for label, transparency in labels do
		label.TextTransparency = fadeFrom(transparency, fade)
	end
	for stroke, transparency in strokes do
		stroke.Transparency = fadeFrom(transparency, fade)
	end
end

-- The copy fades with the wall as the camera nears, and as it shrinks away
local function fadeCopy(wall: Wall, pop: Pop)
	fadePieces(pop.Copy, pop.Labels, pop.Strokes, 1 - (1 - wall.Fade) * (1 - pop.Vanish))
end

local function applyFade(part: BasePart, wall: Wall)
	fadePieces(part, wall.Labels, wall.Strokes, getHidden(wall))
	if wall.Pop then
		fadeCopy(wall, wall.Pop)
	end
end

-- 0 while the camera's FADE_START or further from the wall, rising to 1 once it's within FADE_END
local function getFade(part: BasePart, from: Vector3): number
	local offset = part.CFrame:PointToObjectSpace(from)
	local half = part.Size / 2
	local distance = (offset - offset:Max(-half):Min(half)).Magnitude / fadeScale
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

-- Written the way the drop HUD shows the multiplier. A wall that's popping keeps the multiplier the
-- items went through on its copy
local function showMultiplier(part: BasePart, wall: Wall)
	if not Drops.IsWall(part) then
		return
	end
	local multiplier = Drops.GetMultiplier(part, getSlide(), hits)
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
		instance.TextTransparency = fadeFrom(instance.TextTransparency, getHidden(wall))
		showMultiplier(part, wall)
	elseif instance:IsA("UIStroke") then
		wall.Strokes[instance] = instance.Transparency
		instance.Transparency = fadeFrom(instance.Transparency, getHidden(wall))
	end
end

-- The wall's shown again in place of its copy
local function endPop(part: BasePart, wall: Wall)
	local pop = wall.Pop
	if not pop then
		return
	end
	wall.Pop = nil
	pop.Copy:Destroy()
	applyFade(part, wall)
end

-- A copy of the wall as it was built, unfaded, that nothing touches or hits and isn't taken for a wall
local function makePop(part: BasePart, wall: Wall): Pop
	local fade = wall.Fade
	wall.Fade = 0
	applyFade(part, wall)
	local copy = part:Clone()
	wall.Fade = fade

	for name in copy:GetAttributes() do
		copy:SetAttribute(name, nil)
	end
	for _, tag in copy:GetTags() do
		copy:RemoveTag(tag)
	end
	copy.CanCollide = false
	copy.CanTouch = false
	copy.CanQuery = false
	local pop: Pop = { Copy = copy, Labels = {}, Strokes = {}, Size = part.Size, Started = os.clock(), Vanish = 0 }
	for _, descendant in copy:GetDescendants() do
		if descendant:IsA("SurfaceGui") and descendant.SizingMode == Enum.SurfaceGuiSizingMode.PixelsPerStud then
			-- Stretched over its face however big that is, so the text shrinks with it
			local size = part.Size
			local face = Vector3.FromNormalId(descendant.Face):Abs()
			local width = if face.X > 0 then size.Z else size.X
			local height = if face.Y > 0 then size.Z else size.Y
			descendant.CanvasSize = Vector2.new(width, height) * descendant.PixelsPerStud
			descendant.SizingMode = Enum.SurfaceGuiSizingMode.FixedSize
		elseif descendant:IsA("TextLabel") then
			pop.Labels[descendant] = descendant.TextTransparency
		elseif descendant:IsA("UIStroke") then
			pop.Strokes[descendant] = descendant.Transparency
		end
	end
	return pop
end

-- Sizes and fades the copy for how far it's got, keeping its bottom where the wall's is, and shows the
-- wall again once it's grown back
local function stepPop(part: BasePart, wall: Wall, pop: Pop)
	local elapsed = os.clock() - pop.Started
	local scale, vanish = 0, 1
	if elapsed < POP_TIME then
		local alpha = TweenService:GetValue(elapsed / POP_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
		scale, vanish = 1 + (POP_SCALE - 1) * alpha, 0
	elseif elapsed < POP_TIME + SHRINK_TIME then
		local progress = (elapsed - POP_TIME) / SHRINK_TIME
		local alpha = TweenService:GetValue(progress, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		scale, vanish = POP_SCALE * (1 - alpha), progress
	elseif elapsed >= RETURN_DELAY + RETURN_TIME then
		endPop(part, wall)
		return
	elseif elapsed > RETURN_DELAY then
		local progress = (elapsed - RETURN_DELAY) / RETURN_TIME
		scale = TweenService:GetValue(progress, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
		vanish = 1 - progress
	end
	pop.Copy.Size = pop.Size * scale
	pop.Copy.CFrame = part.CFrame * CFrame.new(0, (scale - 1) * pop.Size.Y / 2, 0)
	pop.Vanish = vanish
	fadeCopy(wall, pop)
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
	endPop(part, wall)
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
		if wall.Pop then
			stepPop(part, wall, wall.Pop)
		end

		local fade = getFade(part, from)
		if fade ~= wall.Fade then
			wall.Fade = fade
			applyFade(part, wall)
		end
	end
end

-- One of this player's items has touched the wall, so it flashes white, pops and shrinks away, then
-- grows back (see stepPop). Touches while it's away don't start it again
function MultiplierWallController.Pop(part: BasePart)
	local wall = walls[part]
	if not wall or wall.Pop then
		return
	end
	local pop = makePop(part, wall)
	wall.Pop = pop
	applyFade(part, wall)
	local copy = pop.Copy

	local color, transparency = copy.Color, copy.Transparency
	copy.Color = FLASH_COLOR
	copy.Transparency = FLASH_TRANSPARENCY
	TweenService:Create(copy, FLASH_INFO, { Color = color, Transparency = transparency }):Play()
	for label in pop.Labels do
		local textColor = label.TextColor3
		label.TextColor3 = FLASH_COLOR
		TweenService:Create(label, FLASH_INFO, { TextColor3 = textColor }):Play()
	end
	copy.Parent = workspace
end

-- How many walls this player's drop has gone through: every wall shows WALL_GROWTH more for each.
-- The most any of its items still sliding have, since each item's own walls raise what it gets, and
-- 0 between drops
function MultiplierWallController.SetHits(count: number)
	if count ~= hits then
		hits = count
		showAll()
	end
end

-- The drop camera backs off from the items, by this many times its usual distance, to keep them all
-- in view, so walls fade as much further from it: the items still go through them, or miss them, on
-- screen before they fade. 1 once it's done
function MultiplierWallController.SetFadeScale(scale: number)
	fadeScale = math.max(scale, 1)
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
