local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")

local Places = require(ReplicatedStorage.Shared.Places)
local SignUpgrades = require(ReplicatedStorage.Shared.SignUpgrades)

local BillboardRangeController = require(script.Parent.BillboardRangeController)

local BuyUpgradeResult = ReplicatedStorage.Remotes.BuyUpgradeResult
local LocalPlayer = Players.LocalPlayer

-- Every time the player buys a roll stand from the sign, the camera flies over to where it goes, the
-- stand grows up out of the floor, and the camera flies back. On their screen only. It all takes
-- about as long as the Roll Slots button's cooldown (see SignUpgrades), so buys don't pile up
local ROLL_SLOTS = "RollSlots"
local CAMERA_MOVE = TweenInfo.new(0.4, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)
local GROW = TweenInfo.new(0.5, Enum.EasingStyle.Back, Enum.EasingDirection.Out) -- Overshoots a little
local HOLD_TIME = 0.2 -- Seconds the camera stays on the grown stand before flying back
local VIEW_DISTANCE = 16 -- Studs from the stand the camera looks at it from, towards where it was
local VIEW_HEIGHT = 8
local START_SCALE = 0.01 -- Models can't be scaled to 0
local STAND_TIMEOUT = 3 -- Seconds to wait for the bought stand to stream in; it just appears if it's later
local MOVE_SOUND_NAME = "Woosh" -- Sound in SoundService.SFX, played as the camera flies over and as it flies back

local expected: { [Folder]: number } = {} -- The stand number each place's owner just bought, not here yet
local queue: { () -> () } = {}
local playing = false

local StandUnlockController = {}

local function getOwnPlace(): Folder?
	for _, place in Places.GetAll() do
		if place:GetAttribute("OwnerUserId") == LocalPlayer.UserId then
			return place
		end
	end
	return nil
end

-- One reveal at a time, in the order they were bought
local function enqueue(reveal: () -> ())
	table.insert(queue, reveal)
	if playing then
		return
	end
	playing = true
	while #queue > 0 do
		table.remove(queue, 1)()
	end
	playing = false
end

local function playMoveSound()
	local sfx = SoundService:FindFirstChild("SFX")
	local sound = sfx and sfx:FindFirstChild(MOVE_SOUND_NAME)
	if sound and sound:IsA("Sound") then
		sound:Play()
	end
end

local function tweenAndWait(instance: Instance, info: TweenInfo, goal: { [string]: any })
	local tween = TweenService:Create(instance, info, goal)
	tween:Play()
	tween.Completed:Wait()
end

-- Shrinks the stand to nothing straight away, and gives back what grows it again: its bottom stays
-- on the floor while it scales, and where the camera should look
local function shrink(stand: Model): ((number) -> (), Vector3)
	local pivot = stand:GetPivot()
	local boxCFrame, boxSize = stand:GetBoundingBox()
	local bottom = CFrame.new(boxCFrame.Position - pivot.UpVector * boxSize.Y / 2) * pivot.Rotation
	local offset = bottom:ToObjectSpace(pivot)

	local function setScale(scale: number)
		stand:ScaleTo(scale)
		stand:PivotTo(bottom * CFrame.new(offset.Position * scale) * offset.Rotation)
	end
	-- ScaleTo shrinks the stats billboard's MaxDistance along with the stand, and a range taken from
	-- that would keep it hidden for good
	for _, descendant in stand:GetDescendants() do
		BillboardRangeController.Track(descendant)
	end
	setScale(START_SCALE)
	return setScale, boxCFrame.Position
end

local function reveal(stand: Model, setScale: (number) -> (), center: Vector3)
	if not stand.Parent then
		setScale(1)
		return
	end

	-- Leaves the camera alone while something else has it, like a drop following its items
	local camera = workspace.CurrentCamera
	local moveCamera = camera.CameraType == Enum.CameraType.Custom
	local returnCFrame = camera.CFrame
	if moveCamera then
		local away = returnCFrame.Position - center
		away = Vector3.new(away.X, 0, away.Z)
		away = if away.Magnitude > 0.01 then away.Unit else Vector3.zAxis
		local viewPosition = center + away * VIEW_DISTANCE + Vector3.yAxis * VIEW_HEIGHT
		camera.CameraType = Enum.CameraType.Scriptable
		playMoveSound()
		tweenAndWait(camera, CAMERA_MOVE, { CFrame = CFrame.lookAt(viewPosition, center) })
	end

	local scale = Instance.new("NumberValue")
	scale.Value = START_SCALE
	scale.Changed:Connect(setScale)
	tweenAndWait(scale, GROW, { Value = 1 })
	scale:Destroy()
	setScale(1)

	if moveCamera then
		task.wait(HOLD_TIME)
		playMoveSound()
		tweenAndWait(camera, CAMERA_MOVE, { CFrame = returnCFrame })
		camera.CameraType = Enum.CameraType.Custom
	end
end

-- The bought stand has arrived: it's shrunk at once, before it's ever seen at full size, and grows
-- when its turn comes
local function onStandArrived(place: Folder, stand: Model)
	expected[place] = nil
	local setScale, center = shrink(stand)
	task.spawn(enqueue, function()
		reveal(stand, setScale, center)
	end)
end

-- The server sends this before the stand, so it's known to be this player's purchase when it lands
local function onBought(name: string, bought: boolean, level: number?)
	if name ~= ROLL_SLOTS or not bought or typeof(level) ~= "number" then
		return
	end
	local place = getOwnPlace()
	if not place then
		return
	end

	local number = SignUpgrades.GetValue(ROLL_SLOTS, level)
	local stand = place:FindFirstChild(Places.GetStandName(number))
	if stand and stand:IsA("Model") then
		onStandArrived(place, stand)
		return
	end

	expected[place] = number
	task.delay(STAND_TIMEOUT, function()
		if expected[place] == number then
			expected[place] = nil
		end
	end)
end

function StandUnlockController.Start()
	BuyUpgradeResult.OnClientEvent:Connect(onBought)
	for _, place in Places.GetAll() do
		place.ChildAdded:Connect(function(child)
			if expected[place] and Places.GetStandNumber(child) == expected[place] then
				onStandArrived(place, child :: Model)
			end
		end)
	end
end

return StandUnlockController
