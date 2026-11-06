local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GamePasses = require(ReplicatedStorage.Shared.GamePasses)

local CHECK_ATTEMPTS = 3 -- Tries at asking Roblox whether a player has a pass
local CHECK_RETRY_DELAY = 2 -- Seconds between those tries
-- Seconds before asking again about cash passes Roblox didn't answer for. Someone who paid for one
-- would otherwise earn less until they rejoined
local CASH_RECHECK_DELAY = 30

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

-- A multiplier only goes up, so an answer that comes back late can't undo a purchase
local function raiseCashMultiplier(player: Player, multiplier: number)
	if multiplier > GamePasses.GetCashMultiplier(player) then
		player:SetAttribute("CashMultiplier", multiplier)
	end
end

-- Finds the best cash pass the player has, from the top down, as nothing below that one matters
local function checkCashPasses(player: Player)
	while player.Parent == Players do
		local unanswered = false
		for index = #GamePasses.CashTiers, 1, -1 do
			local tier = GamePasses.CashTiers[index]
			if tier.Multiplier <= GamePasses.GetCashMultiplier(player) then
				break
			end
			local owns = PassService.AskOwns(player, tier.Id)
			if owns then
				raiseCashMultiplier(player, tier.Multiplier)
				break
			elseif owns == nil then
				unanswered = true
			end
		end
		if not unanswered then
			return
		end
		task.wait(CASH_RECHECK_DELAY)
	end
end

-- The prompt can close without a sale and the pass still be theirs, as with the paid slots pass (see
-- SlotService), so it's asked again
local function onPromptFinished(player: Player, passId: number, purchased: boolean)
	for _, tier in GamePasses.CashTiers do
		if tier.Id == passId then
			if purchased or PassService.AskOwns(player, passId) then
				raiseCashMultiplier(player, tier.Multiplier)
			end
			return
		end
	end
end

function PassService.Start()
	for _, player in Players:GetPlayers() do
		task.spawn(checkCashPasses, player)
	end
	Players.PlayerAdded:Connect(checkCashPasses)
	MarketplaceService.PromptGamePassPurchaseFinished:Connect(onPromptFinished)
end

return PassService
