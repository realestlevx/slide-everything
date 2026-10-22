local UserGameSettings = UserSettings():GetService("UserGameSettings")

-- Roblox thins out what an emitter's Rate sends out on lower graphics: the renderer runs at a level
-- from 1 to 21, and the emitter sends out Rate times that level / 21 (Emit bursts are left alone).
-- On a graphics setting above 5, every emitter's Rate is raised to make up for it, so it looks the
-- way it does on max graphics. Lower settings, and Automatic (whose level scripts can't read), keep
-- the thinning. The Rate an emitter was designed with is kept as its BaseRate attribute, which
-- copies of it carry along
local BASE_RATE_ATTRIBUTE = "BaseRate"
local MIN_BOOSTED_SETTING = 6 -- Lowest graphics setting (1 to 10) that gets max graphics particles
local MAX_RENDER_LEVEL = 21

local emitters: { [ParticleEmitter]: boolean } = {}
local multiplier = 1

local ParticleQualityController = {}

-- The settings menu runs graphics setting N at render level N * 2.1, rounded down (10 runs at 21)
local function getMultiplier(): number
	local setting = UserGameSettings.SavedQualityLevel.Value -- 0 is Automatic
	if setting < MIN_BOOSTED_SETTING then
		return 1
	end
	return MAX_RENDER_LEVEL / math.floor(setting * MAX_RENDER_LEVEL / 10)
end

local function apply(emitter: ParticleEmitter)
	local base = emitter:GetAttribute(BASE_RATE_ATTRIBUTE)
	if typeof(base) ~= "number" then
		if multiplier == 1 then
			return -- Never raised, so it's still at the Rate it was designed with
		end
		base = emitter.Rate
		emitter:SetAttribute(BASE_RATE_ATTRIBUTE, base)
	end
	emitter.Rate = (base :: number) * multiplier
end

local function track(instance: Instance)
	if instance:IsA("ParticleEmitter") then
		emitters[instance] = true
		apply(instance)
	end
end

local function update()
	multiplier = getMultiplier()
	for emitter in emitters do
		apply(emitter)
	end
end

function ParticleQualityController.Start()
	multiplier = getMultiplier()
	for _, descendant in workspace:GetDescendants() do
		track(descendant)
	end
	workspace.DescendantAdded:Connect(track)
	workspace.DescendantRemoving:Connect(function(instance)
		emitters[instance :: any] = nil
	end)

	UserGameSettings:GetPropertyChangedSignal("SavedQualityLevel"):Connect(update)
end

return ParticleQualityController
