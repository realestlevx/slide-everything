local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

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

-- On the way back FadeGui's Fade covers the screen, the character moves to the base's spawn while
-- it's covered, and it fades away again
local FADE_GUI_NAME = "FadeGui"
local FADE_FRAME_NAME = "Fade"
local FADE_IN_INFO = TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local FADE_OUT_INFO = TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
local FADE_DISPLAY_ORDER = 100 -- Over every other gui, which are all lower

local goingHome = false

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

	-- Looked up again, since the character may have respawned while the screen faded
	local character = LocalPlayer.Character
	local root = getRoot()
	if character and root then
		character:PivotTo(home)
		root.AssemblyLinearVelocity = Vector3.zero
		root.AssemblyAngularVelocity = Vector3.zero
	end
	checkOutside()

	fade(1, FADE_OUT_INFO)
	goingHome = false
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
end

function BaseController.Start()
	HudController.HomeRequested:Connect(function()
		task.spawn(goHome)
	end)

	-- Kill parts may stream in and out, and come back as new parts
	for _, descendant in workspace:GetDescendants() do
		watchKillPart(descendant)
	end
	workspace.DescendantAdded:Connect(watchKillPart)

	task.spawn(function()
		while true do
			checkOutside()
			task.wait(CHECK_INTERVAL)
		end
	end)
end

return BaseController
