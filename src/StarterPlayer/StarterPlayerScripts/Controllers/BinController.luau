local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Places = require(ReplicatedStorage.Shared.Places)

local InventoryController = require(script.Parent.InventoryController)
local PromptController = require(script.Parent.PromptController)

local LocalPlayer = Players.LocalPlayer

local binPrompts: { [ProximityPrompt]: true } = {}

local BinController = {}

-- Only up while the player holds something to throw away. A bin in a place stays the owner's alone
local function update(prompt: ProximityPrompt)
	PromptController.SetHidden(Places.Find(prompt), prompt, InventoryController.GetEquippedItem() == nil)
end

-- Bins can be anywhere, and their parts stream in and out, so prompts are picked up as they arrive
local function onDescendantAdded(descendant: Instance)
	if not descendant:IsA("ProximityPrompt") then
		return
	end
	local bin = descendant:FindFirstAncestor("Bin")
	if not (bin and bin:IsA("Model")) then
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

function BinController.Start()
	for _, descendant in workspace:GetDescendants() do
		onDescendantAdded(descendant)
	end
	workspace.DescendantAdded:Connect(onDescendantAdded)

	LocalPlayer:GetAttributeChangedSignal("EquippedItem"):Connect(function()
		for prompt in binPrompts do
			update(prompt)
		end
	end)
end

return BinController
