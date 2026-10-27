local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local ProfileStore = require(ServerScriptService.ServerPackages.ProfileStore)
local FormatMoney = require(ReplicatedStorage.Shared.FormatMoney)
local Items = require(ReplicatedStorage.Shared.Items)

local PROFILE_TEMPLATE = {
	Money = 1000, -- Starting money
	Gems = 0,
	MoneyPerSecond = 0,
	Inventory = {} :: { Items.OwnedItem }, -- In the order the items were bought
	Slots = {} :: { [string]: string }, -- Slot key (see Places.GetSlotKey) -> Uid of the inventory item placed in it
	-- Hotbar position (as text, 1 to Hotbar.SIZE) -> Uid of the item kept there. The rest of the items
	-- out of slots wait in the backpack
	Hotbar = {} :: { [string]: string },
	BoughtSlots = {} :: { [string]: boolean }, -- Slot key -> true for every slot bought from the sign
	Floors = 1, -- How many floors the place has for them, counting the first; see Floors
	UpgradeLevels = {} :: { [string]: number }, -- Sign upgrade name (see SignUpgrades) -> level, 1 if missing
	-- Stand number (as text) -> Item Id of its last roll if it wasn't bought, put back on the stand on join
	LastRolls = {} :: { [string]: string },
	CollectCash = 0, -- Earned by drops, waiting on the place's collect pad to be picked up
	CollectItems = {} :: { string }, -- Item Ids of the latest finished drops, piled on the collect pad
	-- How loud sound effects play for them, 0 to 1 of how loud they're mixed; set in the settings menu
	SfxVolume = 1,
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
	-- Saves from before there were several roll stands kept one roll, which was the first stand's
	local data = profile.Data :: any
	if data.LastRoll then
		data.LastRolls["1"] = data.LastRolls["1"] or data.LastRoll
		data.LastRoll = nil
	end

	profile.OnSessionEnd:Connect(function()
		Profiles[player] = nil
		player:Kick("Your data session ended. Please rejoin.")
	end)

	if player.Parent == Players then
		Profiles[player] = profile
		createLeaderstats(player, profile.Data)
		-- Exposed as attributes so other services and clients can read them: the leaderstat only has
		-- money as text, and the rest aren't leaderstats at all
		player:SetAttribute("Money", profile.Data.Money)
		player:SetAttribute("Gems", profile.Data.Gems)
		player:SetAttribute("MoneyPerSecond", profile.Data.MoneyPerSecond)
		player:SetAttribute("SfxVolume", profile.Data.SfxVolume)
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
	player:SetAttribute("Money", amount)
end

function PlayerDataService.AddGems(player: Player, amount: number)
	local data = PlayerDataService.Get(player)
	if not data then
		return
	end

	data.Gems += amount
	player:SetAttribute("Gems", data.Gems)
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
