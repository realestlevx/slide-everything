local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local ProfileStore = require(ServerScriptService.ServerPackages.ProfileStore)
local FormatMoney = require(ReplicatedStorage.Shared.FormatMoney)
local Items = require(ReplicatedStorage.Shared.Items)

local PROFILE_TEMPLATE = {
	Money = 0,
	MoneyPerSecond = 0,
	Inventory = {} :: { Items.OwnedItem }, -- In the order the items were bought
}

export type Data = typeof(PROFILE_TEMPLATE)

local PlayerStore = ProfileStore.New("PlayerStore", PROFILE_TEMPLATE)

local Profiles: { [Player]: typeof(PlayerStore:StartSessionAsync("")) } = {}

local loaded = Instance.new("BindableEvent")

local PlayerDataService = {
	-- Fires with the player once their data is ready to use
	Loaded = loaded.Event,
}

local function createLeaderstats(player: Player, data: Data)
	local leaderstats = Instance.new("Folder")
	leaderstats.Name = "leaderstats"

	local money = Instance.new("StringValue")
	money.Name = "Money"
	money.Value = FormatMoney(data.Money)
	money.Parent = leaderstats

	leaderstats.Parent = player
end

local function updateLeaderstat(player: Player, name: string, value: string)
	local leaderstats = player:FindFirstChild("leaderstats")
	local stat = leaderstats and leaderstats:FindFirstChild(name)
	if stat then
		(stat :: StringValue).Value = value
	end
end

local function onPlayerAdded(player: Player)
	local profile = PlayerStore:StartSessionAsync(`{player.UserId}`, {
		Cancel = function()
			return player.Parent ~= Players
		end,
	})

	if profile == nil then
		player:Kick("Failed to load your data. Please rejoin.")
		return
	end

	profile:AddUserId(player.UserId) -- GDPR compliance
	profile:Reconcile() -- Fill in missing template keys

	profile.OnSessionEnd:Connect(function()
		Profiles[player] = nil
		player:Kick("Your data session ended. Please rejoin.")
	end)

	if player.Parent == Players then
		Profiles[player] = profile
		createLeaderstats(player, profile.Data)
		-- Not a leaderstat; exposed as an attribute so other services and clients can read it
		player:SetAttribute("MoneyPerSecond", profile.Data.MoneyPerSecond)
		loaded:Fire(player)
	else
		profile:EndSession()
	end
end

function PlayerDataService.Get(player: Player): Data?
	local profile = Profiles[player]
	return profile and profile.Data
end

function PlayerDataService.SetMoney(player: Player, amount: number)
	local data = PlayerDataService.Get(player)
	if not data then
		return
	end

	data.Money = amount
	updateLeaderstat(player, "Money", FormatMoney(amount))
end

function PlayerDataService.AddMoney(player: Player, amount: number)
	local data = PlayerDataService.Get(player)
	if not data then
		return
	end

	PlayerDataService.SetMoney(player, data.Money + amount)
end

function PlayerDataService.SetMoneyPerSecond(player: Player, amount: number)
	local data = PlayerDataService.Get(player)
	if not data then
		return
	end

	data.MoneyPerSecond = amount
	player:SetAttribute("MoneyPerSecond", amount)
end

function PlayerDataService.Start()
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayerAdded, player)
	end
	Players.PlayerAdded:Connect(onPlayerAdded)

	Players.PlayerRemoving:Connect(function(player)
		local profile = Profiles[player]
		if profile then
			profile:EndSession()
		end
	end)
end

return PlayerDataService
