local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local OfflineEarnings = require(ReplicatedStorage.Shared.OfflineEarnings)

local OfflineEarningsService = require(script.Parent.OfflineEarningsService)
local PlayerDataService = require(script.Parent.PlayerDataService)

-- Developer product id -> gives it to the player, saying whether it could. Roblox only lets one script
-- hear about purchases, so every product goes here
local GRANTS: { [number]: (player: Player) -> boolean } = {
	[OfflineEarnings.PRODUCT_ID] = OfflineEarningsService.Multiply,
}

local ProductService = {}

-- Anything but PurchaseGranted leaves the purchase unfinished, and Roblox sends it again the next time
-- the player joins
local function processReceipt(receipt: any): Enum.ProductPurchaseDecision
	local player = Players:GetPlayerByUserId(receipt.PlayerId)
	local grant = GRANTS[receipt.ProductId]
	if not grant then
		warn(`Nothing gives out developer product {receipt.ProductId}`)
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	-- One left unfinished last time comes in as they join, maybe before their data has
	while player and player.Parent == Players and not PlayerDataService.Get(player) do
		task.wait()
	end
	if not (player and player.Parent == Players) then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	local granted = PlayerDataService.GrantPurchaseAsync(player, receipt.PurchaseId, function()
		return grant(player)
	end)
	return if granted then Enum.ProductPurchaseDecision.PurchaseGranted else Enum.ProductPurchaseDecision.NotProcessedYet
end

function ProductService.Start()
	MarketplaceService.ProcessReceipt = processReceipt
end

return ProductService
