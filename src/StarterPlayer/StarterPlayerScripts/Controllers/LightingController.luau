local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local LocalPlayer = Players.LocalPlayer

-- The lighting changes with the stage under what the camera's following: the items through a drop,
-- the player otherwise. Stages are the folders in Workspace.Stages, and a stage's look is picked by its
-- Name attribute ("Forest"), so every stage with the same name looks the same. Anywhere else, and on
-- stages without a look below, it's the Lighting as it's set in Studio
local STAGES_FOLDER = "Stages"
local STAGE_NAME_ATTRIBUTE = "Name"
local BLEND_TIME = 1 -- Seconds to ease from one look into the next
local CHECK_INTERVAL = 0.2 -- Seconds between looks at which stage is underneath
-- The stage is the one with the first part straight down from a little above what's followed
local RAY_LIFT = 20 -- Studs
local RAY_LENGTH = 3000 -- Studs
local CORRECTION_NAME = "StageColorCorrection"

-- What a look can change: properties of Lighting, and of this client's own color correction, which
-- does nothing until a look changes it. Ones a look leaves out stay as they're set in Studio
local PROPERTIES = {
	Lighting = {
		"Brightness",
		"Ambient",
		"OutdoorAmbient",
		"ColorShift_Top",
		"ColorShift_Bottom",
		"FogColor",
		"FogStart",
		"FogEnd",
		"ExposureCompensation",
	},
	Correction = { "Brightness", "Contrast", "Saturation", "TintColor" },
}

type Values = { [string]: { [string]: any } } -- Property values by the group they're in

local LOOKS: { [string]: Values } = {
	-- In the shade of the trees: dimmer, with green shadows, warm sunlight coming through and a green
	-- haze closing in. Still daytime
	Forest = {
		Lighting = {
			Brightness = 1.5,
			Ambient = Color3.fromRGB(20, 28, 20),
			OutdoorAmbient = Color3.fromRGB(115, 132, 110),
			ColorShift_Top = Color3.fromRGB(255, 225, 170),
			ColorShift_Bottom = Color3.fromRGB(10, 20, 12),
			FogColor = Color3.fromRGB(105, 125, 100),
			FogStart = 150,
			FogEnd = 850,
			ExposureCompensation = -0.1,
		},
		Correction = {
			Brightness = -0.01,
			Contrast = 0.06,
			Saturation = 0.08,
			TintColor = Color3.fromRGB(242, 250, 238),
		},
	},
	-- Murky and overcast: dim, washed-out sunlight through a thick olive haze that closes in, with
	-- muddy shadows
	Swamp = {
		Lighting = {
			Brightness = 1.2,
			Ambient = Color3.fromRGB(24, 26, 16),
			OutdoorAmbient = Color3.fromRGB(105, 110, 85),
			ColorShift_Top = Color3.fromRGB(205, 210, 160),
			ColorShift_Bottom = Color3.fromRGB(18, 20, 8),
			FogColor = Color3.fromRGB(95, 102, 74),
			FogStart = 60,
			FogEnd = 600,
			ExposureCompensation = -0.15,
		},
		Correction = {
			Brightness = -0.02,
			Contrast = 0.08,
			Saturation = -0.12,
			TintColor = Color3.fromRGB(236, 242, 220),
		},
	},
	-- Hot and bright: a strong warm sun, shadows lit orange by the sand and a pale heat haze far off
	Dunes = {
		Lighting = {
			Brightness = 2.6,
			Ambient = Color3.fromRGB(40, 28, 14),
			OutdoorAmbient = Color3.fromRGB(175, 150, 115),
			ColorShift_Top = Color3.fromRGB(255, 215, 150),
			ColorShift_Bottom = Color3.fromRGB(45, 25, 8),
			FogColor = Color3.fromRGB(235, 212, 165),
			FogStart = 250,
			FogEnd = 1300,
			ExposureCompensation = 0.05,
		},
		Correction = {
			Brightness = 0.01,
			Contrast = 0.1,
			Saturation = 0.06,
			TintColor = Color3.fromRGB(255, 244, 226),
		},
	},
}

local correction: ColorCorrectionEffect
local instances: { [string]: Instance } = {} -- What each group of properties is set on
local defaults: Values = {} -- As set in Studio
local current: Values = {}
local fromValues: Values = {}
local toValues: Values = {}
local lookName: string? = nil -- The look it's going to. Nil for Studio's
local progress = 1 -- From fromValues to toValues
local sinceCheck = math.huge
local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Include

local LightingController = {}

local function copy(values: Values): Values
	local copied = {}
	for group, properties in values do
		copied[group] = table.clone(properties)
	end
	return copied
end

-- Every property's value in a look, Studio's where it leaves one out
local function getValues(name: string?): Values
	local values = copy(defaults)
	local look = if name then LOOKS[name] else nil
	if look then
		for group, properties in look do
			for property, value in properties do
				values[group][property] = value
			end
		end
	end
	return values
end

local function lerp(from: any, to: any, alpha: number): any
	return if typeof(from) == "Color3" then from:Lerp(to, alpha) else from + (to - from) * alpha
end

-- Where the camera's looking: at the items through a drop, while DropController holds the camera and
-- keeps its focus on them, and at the character otherwise
local function getFollowed(): Vector3
	local camera = workspace.CurrentCamera
	local character = LocalPlayer.Character
	local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
	if camera.CameraType ~= Enum.CameraType.Scriptable and root and root:IsA("BasePart") then
		return root.Position
	end
	return camera.Focus.Position
end

-- The look for the stage underneath, or nil if there's no stage there or no look for it
local function findLook(position: Vector3): string?
	local stages = workspace:FindFirstChild(STAGES_FOLDER)
	if not stages then
		return nil
	end
	rayParams.FilterDescendantsInstances = { stages }
	local hit = workspace:Raycast(position + Vector3.yAxis * RAY_LIFT, -Vector3.yAxis * RAY_LENGTH, rayParams)
	local stage = if hit then hit.Instance else nil
	while stage and stage.Parent ~= stages do
		stage = stage.Parent
	end
	local name = if stage then stage:GetAttribute(STAGE_NAME_ATTRIBUTE) else nil
	return if typeof(name) == "string" and LOOKS[name] then name else nil
end

-- Eases on from wherever it's got to, so changing look partway through never jumps
local function setLook(name: string?)
	if name == lookName then
		return
	end
	lookName = name
	fromValues = copy(current)
	toValues = getValues(name)
	progress = 0
	correction.Enabled = true
end

local function onHeartbeat(dt: number)
	sinceCheck += dt
	if sinceCheck >= CHECK_INTERVAL then
		sinceCheck = 0
		setLook(findLook(getFollowed()))
	end
	if progress >= 1 then
		return
	end
	progress = math.min(progress + dt / BLEND_TIME, 1)
	local alpha = progress * progress * (3 - 2 * progress) -- Eased in and out
	for group, properties in PROPERTIES do
		local instance = instances[group] :: any
		for _, property in properties do
			local value = lerp(fromValues[group][property], toValues[group][property], alpha)
			current[group][property] = value
			instance[property] = value
		end
	end
	-- Back on Studio's look the color correction does nothing, so it's turned off
	if progress >= 1 and not lookName then
		correction.Enabled = false
	end
end

function LightingController.Start()
	correction = Instance.new("ColorCorrectionEffect")
	correction.Name = CORRECTION_NAME
	correction.Enabled = false
	correction.Parent = Lighting
	instances = { Lighting = Lighting, Correction = correction }
	for group, properties in PROPERTIES do
		defaults[group] = {}
		for _, property in properties do
			defaults[group][property] = (instances[group] :: any)[property]
		end
	end
	current = copy(defaults)
	RunService.Heartbeat:Connect(onHeartbeat)
end

return LightingController
