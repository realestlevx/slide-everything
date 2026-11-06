local ReplicatedStorage = game:GetService("ReplicatedStorage")

local OfflineEarnings = require(ReplicatedStorage.Shared.OfflineEarnings)

local PlayerDataService = require(script.Parent.PlayerDataService)

local OfflineCashTaken = ReplicatedStorage.Remotes.OfflineCashTaken
local TakeOfflineCash = ReplicatedStorage.Remotes.TakeOfflineCash

local OfflineEarningsService = {}

-- Everything waiting goes into the player's money, times this. Their client hears how much, to show
-- it flying in. Returns whether there was anything to pay
local function pay(player: Player, multiplier: number): boolean
	local data = PlayerDataService.Get(player)
	local waiting = OfflineEarnings.GetWaiting(player)
	if not data or waiting <= 0 then
		return false
	end

	local amount = waiting * multiplier
	PlayerDataService.AddMoney(player, amount)
	data.OfflineCash = 0
	player:SetAttribute(OfflineEarnings.ATTRIBUTE, 0)
	OfflineCashTaken:FireClient(player, amount)
	return true
end

-- The developer product was bought. With nothing waiting, like when it was taken as it is just before
-- the purchase went through, the purchase stays unfinished, and Roblox sends it again the next time
-- they join, for what they've earned by then (see ProductService)
function OfflineEarningsService.Multiply(player: Player): boolean
	return pay(player, OfflineEarnings.MULTIPLIER)
end

function OfflineEarningsService.Start()
	TakeOfflineCash.OnServerEvent:Connect(function(player)
		pay(player, 1)
	end)
end

return OfflineEarningsService
