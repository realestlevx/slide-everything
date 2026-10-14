local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Places = require(ReplicatedStorage.Shared.Places)

local LocalPlayer = Players.LocalPlayer

local PromptController = {}

local function isOwner(place: Folder): boolean
	return place:GetAttribute("OwnerUserId") == LocalPlayer.UserId
end

-- Enabled is only changed locally, so every player sees just their own place's prompts
local function refresh(place: Folder)
	local owned = isOwner(place)
	for _, descendant in place:GetDescendants() do
		if descendant:IsA("ProximityPrompt") then
			descendant.Enabled = owned
		end
	end
end

function PromptController.Start()
	for _, place in Places.GetAll() do
		refresh(place)
		place:GetAttributeChangedSignal("OwnerUserId"):Connect(function()
			refresh(place)
		end)

		-- Parts stream in and out, so catch prompts that arrive later
		place.DescendantAdded:Connect(function(descendant)
			if descendant:IsA("ProximityPrompt") then
				descendant.Enabled = isOwner(place)
			end
		end)
	end
end

return PromptController
