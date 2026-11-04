local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")

local LocalPlayer = Players.LocalPlayer

-- A scroll bar for any ScrollingFrame, in a ScreenGui or on a SurfaceGui, built in Studio: a GuiObject
-- named ScrollBar under the same parent as the frame, so it doesn't scroll along with what's in it,
-- with a GuiObject named Thumb inside. The frame's own bar is turned off with ScrollBarThickness 0.
-- The thumb is as long as the share of the frame's contents in view and moves along the bar as the
-- frame scrolls, and dragging it or pressing the bar scrolls the frame. A bar taller than it's wide
-- scrolls up and down, otherwise side to side. The bar hides while everything fits
local BAR_NAME = "ScrollBar"
local THUMB_NAME = "Thumb"
local MIN_THUMB_LENGTH = 0.15 -- The shortest the thumb gets, as a share of the bar, so it can always be grabbed

type Bar = {
	Bar: GuiObject,
	Thumb: GuiObject,
	Frame: ScrollingFrame,
	Connections: { RBXScriptConnection },
}

local bars: { [Instance]: Bar } = {}
-- Each bar's own bar, thumb and frame -> the bar, so it's let go of when any of them leaves
local barsByPart: { [Instance]: Bar } = {}
local press: InputObject? = nil -- The click or touch dragging a thumb
local pressed: Bar? = nil -- The bar whose thumb it's dragging
local grab = 0 -- How far along the thumb it's held, in the gui's pixels

local ScrollBarController = {}

local function isPress(input: InputObject): boolean
	return input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch
end

-- A mouse's button is the same from press to let go, while each touch is its own
local function isSameInput(a: InputObject, b: InputObject): boolean
	return a == b or (a.UserInputType == b.UserInputType and a.UserInputType ~= Enum.UserInputType.Touch)
end

local function isVertical(bar: Bar): boolean
	local size = bar.Bar.AbsoluteSize
	return size.Y >= size.X
end

-- The part of a size or position along the way the bar scrolls
local function along(vector: Vector2, vertical: boolean): number
	return if vertical then vector.Y else vector.X
end

local function render(bar: Bar)
	local frame, thumb = bar.Frame, bar.Thumb
	local vertical = isVertical(bar)
	local window = along(frame.AbsoluteWindowSize, vertical)
	local canvas = along(frame.AbsoluteCanvasSize, vertical)
	local scrollable = canvas - window
	bar.Bar.Visible = scrollable >= 1
	if scrollable < 1 then
		return
	end

	local length = math.clamp(window / canvas, MIN_THUMB_LENGTH, 1)
	local start = (1 - length) * math.clamp(along(frame.CanvasPosition, vertical) / scrollable, 0, 1)
	if vertical then
		thumb.AnchorPoint = Vector2.new(thumb.AnchorPoint.X, 0)
		thumb.Size = UDim2.new(thumb.Size.X, UDim.new(length, 0))
		thumb.Position = UDim2.new(thumb.Position.X, UDim.new(start, 0))
	else
		thumb.AnchorPoint = Vector2.new(0, thumb.AnchorPoint.Y)
		thumb.Size = UDim2.new(UDim.new(length, 0), thumb.Size.Y)
		thumb.Position = UDim2.new(UDim.new(start, 0), thumb.Position.Y)
	end
end

-- Where a point on the screen is in a SurfaceGui's own pixels, like its GuiObjects' AbsolutePosition:
-- where the line from the camera through it meets the face the gui's on. Only on a side of its part,
-- where the gui's up is the part's up; nil on its top or bottom, or looking along the face
local function toSurface(gui: SurfaceGui, point: Vector2): Vector2?
	local part = gui.Adornee or gui.Parent
	if not (part and part:IsA("BasePart")) or gui.Face == Enum.NormalId.Top or gui.Face == Enum.NormalId.Bottom then
		return nil
	end
	local normal = Vector3.FromNormalId(gui.Face)
	local up = Vector3.yAxis
	local right = up:Cross(normal) -- As the face is seen from in front of it
	local size = part.Size

	-- In the part's own space, where the face is flat
	local ray = workspace.CurrentCamera:ScreenPointToRay(point.X, point.Y)
	local origin = part.CFrame:PointToObjectSpace(ray.Origin)
	local direction = part.CFrame:VectorToObjectSpace(ray.Direction)
	local facing = direction:Dot(normal)
	if math.abs(facing) < 1e-6 then
		return nil
	end
	local center = normal * size / 2
	local offset = origin + direction * ((center - origin):Dot(normal) / facing) - center

	local canvas = gui.AbsoluteSize
	return Vector2.new(
		(offset:Dot(right) / math.abs(size:Dot(right)) + 0.5) * canvas.X,
		(0.5 - offset:Dot(up) / size.Y) * canvas.Y
	)
end

-- Where a point on the screen is in the bar's gui's own pixels, or nil if it can't be told
local function getPointer(bar: Bar, point: Vector2): Vector2?
	local gui = bar.Bar:FindFirstAncestorWhichIsA("LayerCollector")
	if gui and gui:IsA("ScreenGui") then
		-- Input leaves out the top bar's inset, which a gui that ignores it counts from
		return if gui.IgnoreGuiInset then point + GuiService:GetGuiInset() else point
	elseif gui and gui:IsA("SurfaceGui") then
		return toSurface(gui, point)
	end
	return nil
end

-- Scrolls the frame so the thumb is where it's held, as near as it goes
local function dragTo(bar: Bar, point: Vector2)
	local pointer = getPointer(bar, point)
	if not pointer then
		return
	end
	local vertical = isVertical(bar)
	local frame = bar.Frame
	local room = along(bar.Bar.AbsoluteSize, vertical) - along(bar.Thumb.AbsoluteSize, vertical)
	local scrollable = along(frame.AbsoluteCanvasSize, vertical) - along(frame.AbsoluteWindowSize, vertical)
	if room <= 0 or scrollable <= 0 then
		return
	end
	local start = along(pointer, vertical) - grab - along(bar.Bar.AbsolutePosition, vertical)
	local scrolled = math.clamp(start / room, 0, 1) * scrollable
	local position = frame.CanvasPosition
	frame.CanvasPosition = if vertical then Vector2.new(position.X, scrolled) else Vector2.new(scrolled, position.Y)
end

-- Pressing the thumb drags it from where it's held; pressing anywhere else on the bar jumps the
-- thumb's middle there first
local function onPressed(bar: Bar, input: InputObject)
	if press or not isPress(input) then
		return
	end
	local point = Vector2.new(input.Position.X, input.Position.Y)
	local pointer = getPointer(bar, point)
	if not pointer then
		return
	end
	local vertical = isVertical(bar)
	local thumb = bar.Thumb
	local held = along(pointer, vertical) - along(thumb.AbsolutePosition, vertical)
	local length = along(thumb.AbsoluteSize, vertical)
	grab = if held >= 0 and held <= length then held else length / 2
	press = input
	pressed = bar
	dragTo(bar, point)
end

local function onPointerMoved(input: InputObject)
	local current, bar = press, pressed
	if not (current and bar) then
		return
	end
	local isMouse = current.UserInputType == Enum.UserInputType.MouseButton1
	if isMouse and input.UserInputType ~= Enum.UserInputType.MouseMovement then
		return
	elseif not isMouse and input ~= current then
		return
	end
	dragTo(bar, Vector2.new(input.Position.X, input.Position.Y))
end

local function onPointerReleased(input: InputObject)
	local current = press
	if current and isSameInput(current, input) then
		press = nil
		pressed = nil
	end
end

local function unbind(bar: Bar)
	for _, connection in bar.Connections do
		connection:Disconnect()
	end
	bars[bar.Bar] = nil
	for _, part in { bar.Bar, bar.Thumb, bar.Frame } do
		if barsByPart[part] == bar then
			barsByPart[part] = nil
		end
	end
	if pressed == bar then
		press = nil
		pressed = nil
	end
end

-- Once the bar, its thumb and its frame are all in
local function tryBind(instance: Instance)
	if bars[instance] or not instance:IsA("GuiObject") then
		return
	end
	local object = instance :: GuiObject
	local thumb = object:FindFirstChild(THUMB_NAME)
	local parent = object.Parent
	local frame = parent and parent:FindFirstChildWhichIsA("ScrollingFrame")
	if not (thumb and thumb:IsA("GuiObject") and frame) then
		return
	end

	local bar: Bar = { Bar = object, Thumb = thumb :: GuiObject, Frame = frame, Connections = {} }
	bars[object] = bar
	for _, part in { object, thumb, frame } do
		barsByPart[part] = bar
	end

	-- So a touch dragging the thumb doesn't turn the camera as well
	object.Active = true
	thumb.Active = true
	local function rerender()
		render(bar)
	end
	for _, signal in {
		frame:GetPropertyChangedSignal("CanvasPosition"),
		frame:GetPropertyChangedSignal("AbsoluteCanvasSize"),
		frame:GetPropertyChangedSignal("AbsoluteWindowSize"),
		object:GetPropertyChangedSignal("AbsoluteSize"),
	} do
		table.insert(bar.Connections, signal:Connect(rerender))
	end
	for _, gui in { object, thumb } do
		table.insert(
			bar.Connections,
			gui.InputBegan:Connect(function(input)
				onPressed(bar, input)
			end)
		)
	end
	render(bar)
end

-- A bar can come in before or after its thumb and frame
local function onAdded(instance: Instance)
	local parent = instance.Parent
	if instance.Name == BAR_NAME then
		tryBind(instance)
	elseif parent and instance.Name == THUMB_NAME and parent.Name == BAR_NAME then
		tryBind(parent)
	elseif parent and instance:IsA("ScrollingFrame") then
		local bar = parent:FindFirstChild(BAR_NAME)
		if bar then
			tryBind(bar)
		end
	end
end

local function onRemoving(instance: Instance)
	local bar = barsByPart[instance]
	if bar then
		unbind(bar)
	end
end

function ScrollBarController.Start()
	-- Signs stream in and out, and guis are made again on every respawn
	for _, root in { workspace, LocalPlayer:WaitForChild("PlayerGui") } do
		for _, descendant in root:GetDescendants() do
			onAdded(descendant)
		end
		root.DescendantAdded:Connect(onAdded)
		root.DescendantRemoving:Connect(onRemoving)
	end

	UserInputService.InputChanged:Connect(onPointerMoved)
	-- Listened for everywhere, since the thumb can be let go off the bar
	UserInputService.InputEnded:Connect(onPointerReleased)
end

return ScrollBarController
