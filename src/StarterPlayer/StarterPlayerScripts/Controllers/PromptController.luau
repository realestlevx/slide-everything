local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Places = require(ReplicatedStorage.Shared.Places)

local TopTextController = require(script.Parent.TopTextController)

local LocalPlayer = Players.LocalPlayer

local hiddenPrompts: { [ProximityPrompt]: boolean } = {}

local PromptController = {}

local function isOwner(place: Folder): boolean
	return place:GetAttribute("OwnerUserId") == LocalPlayer.UserId
end

-- What using the prompt counts as for the tutorial, which only lets through what its step has the
-- player do (see Tutorial.Allows). Any other prompt, like a bin's, waits until it's over
local function getAction(prompt: ProximityPrompt): string
	local parent = prompt.Parent
	local parentName = if parent then parent.Name else ""
	if prompt.Name == "RollProximity" then
		return "Roll"
	elseif parentName == "Roll_Place" then
		return "BuyItem"
	elseif parentName == Places.SLOT_PART then
		return "Place"
	elseif prompt:FindFirstAncestor("Drop_Button") then
		return "Drop"
	elseif prompt:FindFirstAncestor("Collect") then
		return "Collect"
	elseif prompt:FindFirstAncestor("Favorites/Feedback") then
		return "Feedback"
	end
	return "Other"
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

	-- Through the tutorial the prompts stay up, so a player trying the wrong one is told why it does
	-- nothing. What each one does checks the tutorial for itself, here and on the server
	ProximityPromptService.PromptTriggered:Connect(function(prompt)
		TopTextController.CheckTutorial(getAction(prompt))
	end)
end

return PromptController
