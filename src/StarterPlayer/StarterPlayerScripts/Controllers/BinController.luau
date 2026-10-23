local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local LocalHide = require(ReplicatedStorage.Shared.LocalHide)
local Places = require(ReplicatedStorage.Shared.Places)

local InventoryController = require(script.Parent.InventoryController)
local PromptController = require(script.Parent.PromptController)

local LocalPlayer = Players.LocalPlayer

-- A bin is a Model with this name. One in a place is only seen by its owner: on everyone else's
-- screen it's hidden. Bins outside any place are for everyone
local BIN_NAME = "Bin"

local binPrompts: { [ProximityPrompt]: true } = {}

local BinController = {}

local function getBin(instance: Instance): Model?
	local bin = instance:FindFirstAncestor(BIN_NAME)
	return if bin and bin:IsA("Model") then bin else nil
end

local function isOwner(place: Folder): boolean
	return place:GetAttribute("OwnerUserId") == LocalPlayer.UserId
end

-- Only up while the player holds something to throw away. A bin in a place stays the owner's alone
local function update(prompt: ProximityPrompt)
	PromptController.SetHidden(Places.Find(prompt), prompt, InventoryController.GetEquippedItem() == nil)
end

-- Bins can be anywhere, and their parts stream in and out, so prompts are picked up as they arrive
local function onDescendantAdded(descendant: Instance)
	if not (descendant:IsA("ProximityPrompt") and getBin(descendant)) then
		return
	end

	binPrompts[descendant] = true
	descendant.AncestryChanged:Connect(function()
		if not descendant:IsDescendantOf(workspace) then
			binPrompts[descendant] = nil
		end
	end)
	update(descendant)
end

local function refreshHidden(place: Folder, instance: Instance)
	if getBin(instance) then
		LocalHide.Set(instance, not isOwner(place))
	end
end

function BinController.Start()
	for _, descendant in workspace:GetDescendants() do
		onDescendantAdded(descendant)
	end
	workspace.DescendantAdded:Connect(onDescendantAdded)

	for _, place in Places.GetAll() do
		for _, descendant in place:GetDescendants() do
			refreshHidden(place, descendant)
		end
		place.DescendantAdded:Connect(function(descendant)
			refreshHidden(place, descendant)
		end)
		place:GetAttributeChangedSignal("OwnerUserId"):Connect(function()
			for _, descendant in place:GetDescendants() do
				refreshHidden(place, descendant)
			end
		end)
	end

	LocalPlayer:GetAttributeChangedSignal("EquippedItem"):Connect(function()
		for prompt in binPrompts do
			update(prompt)
		end
	end)
end

return BinController
