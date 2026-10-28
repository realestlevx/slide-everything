local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ItemModel = require(ReplicatedStorage.Shared.ItemModel)
local Places = require(ReplicatedStorage.Shared.Places)

local CollectController = require(script.Parent.CollectController)
local FloatController = require(script.Parent.FloatController)
local ParticleQualityController = require(script.Parent.ParticleQualityController)
local SettingsController = require(script.Parent.SettingsController)

local LocalPlayer = Players.LocalPlayer

-- Fast Mode, from the Settings menu, trades looks for speed on this player's screen: shadows, textures,
-- particles and trails go, floating items move less often, and only the items in the place the
-- player's in show. Everything's put back as it was once it's off
local FLOAT_INTERVAL = 1 / 20 -- Seconds between floating items' moves, instead of every frame
-- A decal's or texture's image is kept in this attribute while it's gone, so it comes back with the
-- decal if it streams out and in meanwhile
local TEXTURE_ATTRIBUTE = "BaseTexture"
-- The items shown in a place: in its slots, and on its roll stands while rolling and after. Its
-- collect pad's stack is CollectController's
local ITEM_NAMES = { "SlotItem", "RollPreview", "RolledItem" }
local CHECK_INTERVAL = 0.2 -- Seconds between checks of which place the player's in

local fastMode = false
local shadows = Lighting.GlobalShadows -- As the game has it, for when Fast Mode is off
local decals: { [Decal]: boolean } = {} -- Every decal and texture in Workspace
local trails: { [Trail]: boolean } = {} -- Every trail in Workspace
-- Trails Fast Mode has turned off -> the first attachment it took from each. Taken rather than turned
-- off with Enabled, which items' fades and other hiding already use. Kept when one streams out, so
-- it's put back if it comes back as it left
local taken: { [Trail]: Attachment } = {}
local items: { [BasePart]: Folder } = {} -- Every item shown in a place -> that place
local inPlaces: { [Folder]: boolean } = {} -- The places the player's in

local FastModeController = {}

local function isShown(place: Folder): boolean
	return not fastMode or inPlaces[place] == true
end

local function applyTexture(decal: Decal)
	local base = decal:GetAttribute(TEXTURE_ATTRIBUTE)
	if fastMode then
		if typeof(base) ~= "string" then
			decal:SetAttribute(TEXTURE_ATTRIBUTE, decal.Texture)
		end
		decal.Texture = ""
	elseif typeof(base) == "string" then
		decal.Texture = base
		decal:SetAttribute(TEXTURE_ATTRIBUTE, nil)
	end
end

local function takeTrail(trail: Trail)
	local attachment = trail.Attachment0
	if not attachment then
		return
	end
	taken[trail] = attachment
	trail.Attachment0 = nil
	trail.Destroying:Once(function()
		taken[trail] = nil
	end)
end

-- Only what's changed, so an item that's shown isn't touched while it's faded for something else
local function applyItem(item: BasePart, place: Folder)
	local hidden = not isShown(place)
	if ItemModel.IsHidden(item) ~= hidden then
		ItemModel.SetHidden(item, hidden)
	end
end

local function applyPlaces()
	for item, place in items do
		applyItem(item, place)
	end
	for _, place in Places.GetAll() do
		CollectController.SetHidden(place, not isShown(place))
	end
end

local function getRoot(): BasePart?
	local character = LocalPlayer.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	return if root and root:IsA("BasePart") then root else nil
end

local function checkPlaces()
	local root = getRoot()
	local changed = false
	for _, place in Places.GetAll() do
		local inside = root ~= nil and Places.IsInBase(place, root.Position)
		if (inPlaces[place] == true) ~= inside then
			inPlaces[place] = if inside then true else nil
			changed = true
		end
	end
	if changed and fastMode then
		applyPlaces()
	end
end

local function setFastMode(on: boolean)
	fastMode = on
	Lighting.GlobalShadows = shadows and not on
	for decal in decals do
		applyTexture(decal)
	end
	if on then
		for trail in trails do
			takeTrail(trail)
		end
	else
		for trail, attachment in taken do
			trail.Attachment0 = attachment
		end
		table.clear(taken)
	end
	ParticleQualityController.SetOff(on)
	FloatController.SetInterval(if on then FLOAT_INTERVAL else 0)
	applyPlaces()
end

local function track(instance: Instance)
	if instance:IsA("Decal") then -- Textures too
		decals[instance] = true
		applyTexture(instance)
	elseif instance:IsA("Trail") then
		trails[instance] = true
		if fastMode then
			takeTrail(instance)
		end
	elseif instance:IsA("BasePart") and table.find(ITEM_NAMES, instance.Name) then
		local place = Places.Find(instance)
		if place then
			items[instance] = place
			-- After whatever else sets it up as it arrives, like how faded it is. Hidden again even if
			-- it already was, since one that streams back in may not be as it was when it left
			task.defer(function()
				local hidden = not isShown(place)
				if items[instance] == place and (hidden or ItemModel.IsHidden(instance)) then
					ItemModel.SetHidden(instance, hidden)
				end
			end)
		end
	end
end

function FastModeController.Start()
	for _, descendant in workspace:GetDescendants() do
		track(descendant)
	end
	workspace.DescendantAdded:Connect(track)
	workspace.DescendantRemoving:Connect(function(instance)
		decals[instance :: any] = nil
		trails[instance :: any] = nil
		items[instance :: any] = nil
	end)

	setFastMode(SettingsController.IsFastMode())
	SettingsController.FastModeChanged:Connect(setFastMode)

	task.spawn(function()
		while true do
			checkPlaces()
			task.wait(CHECK_INTERVAL)
		end
	end)
end

return FastModeController
