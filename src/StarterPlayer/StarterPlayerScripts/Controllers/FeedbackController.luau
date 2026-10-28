local AvatarEditorService = game:GetService("AvatarEditorService")
local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SocialService = game:GetService("SocialService")

local LocalHide = require(ReplicatedStorage.Shared.LocalHide)
local Places = require(ReplicatedStorage.Shared.Places)

local LocalPlayer = Players.LocalPlayer

-- Each place has its own favorite goal sign and mailbox in this folder, seen only by its owner: on
-- everyone else's screen they're hidden, and their prompts are the owner's alone (see PromptController)
local FOLDER_NAME = "Favorites/Feedback"

-- The prompts open Roblox popups, picked by an attribute on the prompt's part:
-- - Feedback (the mailbox) opens the feedback form. What players send shows up in the Creator
--   Dashboard. The form only opens in the public game, and not for the game's owner
-- - Favorite (the favorite goal sign) asks to favorite the game
local FEEDBACK_ATTRIBUTE = "Feedback"
local FAVORITE_ATTRIBUTE = "Favorite"

local FeedbackController = {}

local function isOwner(place: Folder): boolean
	return place:GetAttribute("OwnerUserId") == LocalPlayer.UserId
end

local function refreshHidden(place: Folder, instance: Instance)
	if instance:FindFirstAncestor(FOLDER_NAME) then
		LocalHide.Set(instance, not isOwner(place))
	end
end

function FeedbackController.Start()
	-- The sign and mailbox stream in and out, so their parts are hidden as they arrive
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

	ProximityPromptService.PromptTriggered:Connect(function(prompt: ProximityPrompt)
		local part = prompt.Parent
		if not part then
			return
		end

		if part:GetAttribute(FEEDBACK_ATTRIBUTE) then
			local opened, err = pcall(SocialService.PromptFeedbackSubmissionAsync, SocialService)
			if not opened then
				warn("[FeedbackController] Couldn't open the feedback form:", err)
			end
		elseif part:GetAttribute(FAVORITE_ATTRIBUTE) then
			-- A place is an asset, so the game is favorited through its place id
			local opened, err = pcall(
				AvatarEditorService.PromptSetFavorite,
				AvatarEditorService,
				game.PlaceId,
				Enum.AvatarItemType.Asset,
				true
			)
			if not opened then
				warn("[FeedbackController] Couldn't open the favorite popup:", err)
			end
		end
	end)
end

return FeedbackController
