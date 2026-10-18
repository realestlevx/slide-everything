local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Places = require(ReplicatedStorage.Shared.Places)
local SignUpgrades = require(ReplicatedStorage.Shared.SignUpgrades)

local InventoryService = require(script.Parent.InventoryService)
local PlaceService = require(script.Parent.PlaceService)
local PlayerDataService = require(script.Parent.PlayerDataService)

local BuyUpgrade = ReplicatedStorage.Remotes.BuyUpgrade
local BuyUpgradeResult = ReplicatedStorage.Remotes.BuyUpgradeResult

local SignUpgradeService = {}

local function getLevel(data: PlayerDataService.Data, name: string): number
	return data.UpgradeLevels[name] or 1
end

-- What the upgrade is worth for the player now, like their luck. Level 1's while their data loads
function SignUpgradeService.GetValue(player: Player, name: string): number
	local data = PlayerDataService.Get(player)
	return SignUpgrades.GetValue(name, if data then getLevel(data, name) else 1)
end

-- A place's signs show its owner's levels, from <Name>Level attributes on the place: the sign parts
-- are streamed, but the place's attributes reach every client
local function updatePlace(place: Folder)
	local ownerId = place:GetAttribute("OwnerUserId")
	local owner = if typeof(ownerId) == "number" then Players:GetPlayerByUserId(ownerId) else nil
	local data = if owner then PlayerDataService.Get(owner) else nil
	for name in SignUpgrades.Upgrades do
		place:SetAttribute(`{name}Level`, if data then getLevel(data, name) else 1)
	end
end

-- A sign panel's button: the next level of that upgrade, if the player can pay for it. Only at the
-- player's own place, whichever sign was clicked
local function onBuy(player: Player, place: any, name: any)
	local data = PlayerDataService.Get(player)
	if not (data and place ~= nil and place == PlaceService.GetPlace(player)) then
		return
	end
	if not (typeof(name) == "string" and SignUpgrades.Upgrades[name]) then
		return
	end

	local level = getLevel(data, name)
	local price = SignUpgrades.GetNextPrice(name, level)
	if not price then
		return
	end
	if data.Money < price then
		BuyUpgradeResult:FireClient(player, name, false)
		return
	end

	PlayerDataService.AddMoney(player, -price)
	data.UpgradeLevels[name] = level + 1
	place:SetAttribute(`{name}Level`, level + 1)
	-- Same as for slots, and more luck can also rule out the cheapest item
	InventoryService.EnsureCanStart(player)
	BuyUpgradeResult:FireClient(player, name, true)
end

function SignUpgradeService.Start()
	for _, place in Places.GetAll() do
		updatePlace(place)
		place:GetAttributeChangedSignal("OwnerUserId"):Connect(function()
			updatePlace(place)
		end)
	end

	PlayerDataService.Loaded:Connect(function(player)
		local place = PlaceService.GetPlace(player)
		if place then
			updatePlace(place)
		end
	end)

	BuyUpgrade.OnServerEvent:Connect(onBuy)
end

return SignUpgradeService
