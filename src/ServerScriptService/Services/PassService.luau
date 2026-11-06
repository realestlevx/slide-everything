local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")

local CHECK_ATTEMPTS = 3 -- Tries at asking Roblox whether a player has a pass
local CHECK_RETRY_DELAY = 2 -- Seconds between those tries

local PassService = {}

-- Asks Roblox whether the player has the pass, a few times over if it can't be reached. Nil if it
-- never answers. Nobody has a pass that isn't made yet
function PassService.AskOwns(player: Player, passId: number): boolean?
	if passId <= 0 then
		return false
	end
	local ok, result
	for attempt = 1, CHECK_ATTEMPTS do
		ok, result = pcall(MarketplaceService.UserOwnsGamePassAsync, MarketplaceService, player.UserId, passId)
		if ok or attempt == CHECK_ATTEMPTS or player.Parent ~= Players then
			break
		end
		task.wait(CHECK_RETRY_DELAY)
	end
	if not ok then
		warn(`Couldn't check whether {player.Name} has game pass {passId}: {result}`)
		return nil
	end
	return result == true
end

return PassService
