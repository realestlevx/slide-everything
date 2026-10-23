local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Drops = require(ReplicatedStorage.Shared.Drops)

-- The multiplier walls across the slide. Each one's text shows its Multiplier attribute, so it can't
-- say something different from what the wall pays. They're tall and wide enough to fill the view as
-- the camera nears them, so they fade out as it closes in, text and all, and back in once it's gone by
local VALUE_LABEL_NAME = "Value" -- The TextLabel on a wall that shows its multiplier
-- Studs from the camera to the nearest point of a wall
local FADE_START = 100 -- Where it starts fading
local FADE_END = 50 -- Where it's gone
local STEP_NAME = "MultiplierWallFade"

type Wall = {
	Fade: number, -- 0 as it was built; 1 gone
	-- Each of its labels' and strokes' own transparency, which they fade from
	Labels: { [TextLabel]: number },
	Strokes: { [UIStroke]: number },
	Connections: { RBXScriptConnection },
}

local walls: { [BasePart]: Wall } = {} -- Every multiplier wall loaded now; they stream in and out

local MultiplierWallController = {}

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

-- Written the way the drop HUD shows the multiplier
local function showMultiplier(part: BasePart, wall: Wall)
	local multiplier = part:GetAttribute(Drops.MULTIPLIER_ATTRIBUTE)
	if typeof(multiplier) ~= "number" then
		return
	end
	for label in wall.Labels do
		if label.Name == VALUE_LABEL_NAME then
			label.Text = `{multiplier}x`
		end
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
	wall.Fade = 0
	applyFade(instance :: BasePart, wall)
end

local function onRenderStep()
	local from = workspace.CurrentCamera.CFrame.Position
	for part, wall in walls do
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
	-- After the drop camera has moved for the frame
	RunService:BindToRenderStep(STEP_NAME, Enum.RenderPriority.Camera.Value + 2, onRenderStep)
end

return MultiplierWallController
