local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Places = require(ReplicatedStorage.Shared.Places)

local LocalPlayer = Players.LocalPlayer

-- What's in a stage's obstacle and decoration folders is only there for the owner of the place whose
-- slide the stage is on (see StageService). Everyone else's client hides it and lets them walk through
-- it. Folders in a stage whose name has one of these in it
local HIDDEN_FOLDERS = { "Obstacles", "Decoration" }
local PLAYER_PLACE_ATTRIBUTE = "Place" -- The name of the player's place, from PlaceService

-- What's set to hide each kind of thing, in this order, and put back the other way round
type Change = { Property: string, Value: any }
local PART_HIDE: { Change } = {
	{ Property = "LocalTransparencyModifier", Value = 1 },
	{ Property = "CanCollide", Value = false },
	{ Property = "CanQuery", Value = false }, -- Only once it can't collide
}
local DECAL_HIDE: { Change } = { { Property = "LocalTransparencyModifier", Value = 1 } } -- Textures too
local EFFECT_HIDE: { Change } = { { Property = "Enabled", Value = false } }
local EFFECT_CLASSES =
	{ "ParticleEmitter", "Beam", "Trail", "Light", "Fire", "Smoke", "Sparkles", "SurfaceGui", "BillboardGui", "Highlight" }

type Hideable = {
	Stage: Model,
	Hide: { Change },
	Saved: { any }?, -- What it had before it was hidden. Nil while it shows
}

local hideables: { [Instance]: Hideable } = {}

local StageController = {}

local function getHide(instance: Instance): { Change }?
	if instance:IsA("BasePart") then
		return PART_HIDE
	elseif instance:IsA("Decal") then
		return DECAL_HIDE
	end
	for _, class in EFFECT_CLASSES do
		if instance:IsA(class) then
			return EFFECT_HIDE
		end
	end
	return nil
end

local function isHiddenFolder(instance: Instance): boolean
	if not instance:IsA("Folder") then
		return false
	end
	for _, name in HIDDEN_FOLDERS do
		if instance.Name:find(name, 1, true) then
			return true
		end
	end
	return false
end

-- The stage whose obstacle or decoration folder the instance is in, if it's in one
local function findStage(instance: Instance): Model?
	local current, parent = instance, instance.Parent
	while parent and parent ~= workspace do
		if Places.IsStage(parent) then
			return if current ~= instance and isHiddenFolder(current) then parent :: Model else nil
		end
		current, parent = parent, parent.Parent
	end
	return nil
end

local function isShown(stage: Model): boolean
	local place = stage:GetAttribute(Places.STAGE_PLACE_ATTRIBUTE)
	return typeof(place) == "string" and place == LocalPlayer:GetAttribute(PLAYER_PLACE_ATTRIBUTE)
end

local function show(instance: Instance, hideable: Hideable)
	local saved = hideable.Saved
	if not saved then
		return
	end
	hideable.Saved = nil
	for index = #hideable.Hide, 1, -1 do
		(instance :: any)[hideable.Hide[index].Property] = saved[index]
	end
end

local function hide(instance: Instance, hideable: Hideable)
	if hideable.Saved then
		return
	end
	local saved = {}
	for index, change in hideable.Hide do
		saved[index] = (instance :: any)[change.Property];
		(instance :: any)[change.Property] = change.Value
	end
	hideable.Saved = saved
end

local function update(instance: Instance, hideable: Hideable)
	if isShown(hideable.Stage) then
		show(instance, hideable)
	else
		hide(instance, hideable)
	end
end

local function updateAll()
	for instance, hideable in hideables do
		update(instance, hideable)
	end
end

local function track(instance: Instance)
	local hideWith = getHide(instance)
	local stage = if hideWith then findStage(instance) else nil
	if not (hideWith and stage) then
		return
	end
	local hideable: Hideable = { Stage = stage, Hide = hideWith, Saved = nil }
	hideables[instance] = hideable
	update(instance, hideable)
end

-- Put back as it was, in case the same instance streams back in
local function untrack(instance: Instance)
	local hideable = hideables[instance]
	if hideable then
		hideables[instance] = nil
		show(instance, hideable)
	end
end

local function watchStage(instance: Instance)
	if Places.IsStage(instance) then
		instance:GetAttributeChangedSignal(Places.STAGE_PLACE_ATTRIBUTE):Connect(updateAll)
	end
end

function StageController.Start()
	for _, child in workspace:GetChildren() do
		watchStage(child)
	end
	workspace.ChildAdded:Connect(watchStage)
	for _, descendant in workspace:GetDescendants() do
		track(descendant)
	end
	workspace.DescendantAdded:Connect(track)
	workspace.DescendantRemoving:Connect(untrack)
	LocalPlayer:GetAttributeChangedSignal(PLAYER_PLACE_ATTRIBUTE):Connect(updateAll)
end

return StageController
