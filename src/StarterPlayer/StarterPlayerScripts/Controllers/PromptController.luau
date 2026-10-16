local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Places = require(ReplicatedStorage.Shared.Places)

local LocalPlayer = Players.LocalPlayer

local hiddenPrompts: { [ProximityPrompt]: boolean } = {}

local PromptController = {}

local function isOwner(place: Folder): boolean
	return place:GetAttribute("OwnerUserId") == LocalPlayer.UserId
end

-- Enabled is only changed locally, so every player sees just their own place's prompts.
-- Prompts outside any place (no place given) are for everyone
local function apply(place: Folder?, prompt: ProximityPrompt)
	prompt.Enabled = (place == nil or isOwner(place)) and not hiddenPrompts[prompt]
end

local function refresh(place: Folder)
	for _, descendant in place:GetDescendants() do
		if descendant:IsA("ProximityPrompt") then
			apply(place, descendant)
		end
	end
end

-- Lets other controllers hide one of the owner's prompts for a while, like the roll prompt mid-spin
function PromptController.SetHidden(place: Folder?, prompt: ProximityPrompt, hidden: boolean)
	hiddenPrompts[prompt] = if hidden then true else nil
	apply(place, prompt)
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
				apply(place, descendant)
			end
		end)
	end
end

return PromptController
