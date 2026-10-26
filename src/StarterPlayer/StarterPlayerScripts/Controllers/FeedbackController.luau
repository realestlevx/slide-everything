local AvatarEditorService = game:GetService("AvatarEditorService")
local ProximityPromptService = game:GetService("ProximityPromptService")
local SocialService = game:GetService("SocialService")

-- The prompts in Workspace["Favorites/Feedback"] open Roblox popups, picked by an attribute on the
-- prompt's part:
-- - Feedback (the mailbox) opens the feedback form. What players send shows up in the Creator
--   Dashboard. The form only opens in the public game, and not for the game's owner
-- - Favorite (the favorite goal sign) asks to favorite the game
local FEEDBACK_ATTRIBUTE = "Feedback"
local FAVORITE_ATTRIBUTE = "Favorite"

local FeedbackController = {}

function FeedbackController.Start()
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
