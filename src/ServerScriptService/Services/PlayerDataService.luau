local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")

local ProfileStore = require(ServerScriptService.ServerPackages.ProfileStore)
local FormatMoney = require(ReplicatedStorage.Shared.FormatMoney)
local Items = require(ReplicatedStorage.Shared.Items)
local OfflineEarnings = require(ReplicatedStorage.Shared.OfflineEarnings)
local Tutorial = require(ReplicatedStorage.Shared.Tutorial)
local Volumes = require(ReplicatedStorage.Shared.Volumes)

-- On, playtests in Studio start as a brand new player on a throwaway profile, to go through the
-- tutorial without touching a real save. Does nothing outside Studio
local TEST_AS_NEW_PLAYER = true

local PURCHASE_IDS_KEPT = 100 -- Developer product purchases remembered, newest kept
local PURCHASE_SAVE_RETRY_DELAY = 10 -- Seconds before trying again to save a purchase that didn't get saved

local PROFILE_TEMPLATE = {
	Money = 1000, -- Starting money
	Gems = 0,
	MoneyPerSecond = 0, -- What their slots earn, before any cash pass; see Gems.GetFind
	CashMultiplier = 1, -- What their best cash pass multiplies their earnings by; see CashPasses
	Inventory = {} :: { Items.OwnedItem }, -- In the order the items were bought
	Slots = {} :: { [string]: string }, -- Slot key (see Places.GetSlotKey) -> Uid of the inventory item placed in it
	-- Hotbar position (as text, 1 to Hotbar.SIZE) -> Uid of the item kept there. The rest of the items
	-- out of slots wait in the backpack
	Hotbar = {} :: { [string]: string },
	BoughtSlots = {} :: { [string]: boolean }, -- Slot key -> true for every slot bought from the sign
	Floors = 1, -- How many floors the place has for them, counting the first; see Floors
	UpgradeLevels = {} :: { [string]: number }, -- Sign upgrade name (see SignUpgrades) -> level, 1 if missing
	-- The luck their rolls are at, set with the settings menu's slider; see SignUpgrades.GetLuck.
	-- Missing while it's all the way up, so it follows the Luck upgrade up as more is bought
	Luck = nil :: number?,
	-- Stand number (as text) -> Item Id of its last roll if it wasn't bought, put back on the stand on join
	LastRolls = {} :: { [string]: string },
	CollectCash = 0, -- Earned by drops, waiting on the place's collect pad to be picked up
	CollectItems = {} :: { string }, -- Item Ids of the latest finished drops, piled on the collect pad
	-- Volume name (see Volumes) -> how loud it plays for them, 0 to 1 of how loud it's mixed, 1 if
	-- missing; set with the settings menu's sliders
	Volumes = {} :: { [string]: number },
	FastMode = false, -- Set with the settings menu's Fast Mode button
	-- The step of the tutorial they're on; see Tutorial. New saves start at the first, and saves from
	-- before there was a tutorial skip it (see onPlayerAdded)
	TutorialStep = 1,
	-- When their data was last saved, which their time away is counted from. Missing until it first is
	LastOnline = nil :: number?,
	OfflineCash = 0, -- Earned while they were away and not taken yet, before any cash pass; see OfflineEarnings
	-- The latest developer product purchases they've been given, so one Roblox sends again isn't given twice
	PurchaseIds = {} :: { string },
}

export type Data = typeof(PROFILE_TEMPLATE)

local PlayerStore = ProfileStore.New("PlayerStore", PROFILE_TEMPLATE)
if TEST_AS_NEW_PLAYER and RunService:IsStudio() then
	PlayerStore = PlayerStore.Mock
end

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
	-- Only a brand new save has a step before it's reconciled, as those are copied from the template.
	-- A save without one is from before there was a tutorial, and that player already knows the game
	local data = profile.Data :: any
	if data.TutorialStep == nil then
		data.TutorialStep = Tutorial.DONE
	end
	profile:Reconcile() -- Fill in missing template keys
	-- Floor 1's first slot used to come free, so saves from then don't have it down as bought, and would
	-- lose it. Anyone past the tutorial owns it: they bought it there, or had it from before
	if data.TutorialStep == Tutorial.DONE then
		data.BoughtSlots["1"] = true
	end
	-- Saves from before there were several roll stands kept one roll, which was the first stand's
	if data.LastRoll then
		data.LastRolls["1"] = data.LastRolls["1"] or data.LastRoll
		data.LastRoll = nil
	end
	-- Worked out here, from what they earned as they left, before anything can change it or a purchase
	-- can come in to multiply it
	if data.LastOnline and data.TutorialStep == Tutorial.DONE then
		data.OfflineCash += OfflineEarnings.GetEarned(os.time() - data.LastOnline, data.MoneyPerSecond)
	end
	-- Saved as they leave and every few minutes before, so a crash doesn't lose them much time away
	profile.OnSave:Connect(function()
		data.LastOnline = os.time()
	end)

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
		player:SetAttribute("CashMultiplier", profile.Data.CashMultiplier)
		for name in Volumes do
			player:SetAttribute(`{name}Volume`, profile.Data.Volumes[name] or 1)
		end
		player:SetAttribute("FastMode", profile.Data.FastMode)
		player:SetAttribute(Tutorial.ATTRIBUTE, profile.Data.TutorialStep)
		player:SetAttribute(OfflineEarnings.ATTRIBUTE, profile.Data.OfflineCash)
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

-- They've bought a cash pass. It only goes up, so whatever they paid for, they never lose a better one.
-- Returns whether it could be given
function PlayerDataService.RaiseCashMultiplier(player: Player, multiplier: number): boolean
	local data = PlayerDataService.Get(player)
	if not data then
		return false
	end

	data.CashMultiplier = math.max(data.CashMultiplier, multiplier)
	player:SetAttribute("CashMultiplier", data.CashMultiplier)
	return true
end

-- Gives out a developer product purchase and waits for it to be saved, so it's only finished with
-- Roblox once a crash can't lose it. The purchase is saved along with what it gave, so if Roblox sends
-- it again it's not given twice. Grant says whether it could be given; if not, nothing's kept. Returns
-- whether it's been given and saved
function PlayerDataService.GrantPurchaseAsync(player: Player, purchaseId: string, grant: () -> boolean): boolean
	local profile = Profiles[player]
	if not (profile and profile:IsActive()) then
		return false
	end

	local purchaseIds = profile.Data.PurchaseIds
	if not table.find(purchaseIds, purchaseId) then
		if not grant() then
			return false
		end
		while #purchaseIds >= PURCHASE_IDS_KEPT do
			table.remove(purchaseIds, 1)
		end
		table.insert(purchaseIds, purchaseId)
	end

	local function isSaved(): boolean
		-- Saves from before there were purchases don't have the list until their next save
		return table.find(profile.LastSavedData.PurchaseIds or {}, purchaseId) ~= nil
	end
	while not isSaved() and profile:IsActive() do
		local lastSaved = profile.LastSavedData
		profile:Save()
		if profile.LastSavedData == lastSaved then
			profile.OnAfterSave:Wait()
		end
		if not isSaved() and profile:IsActive() then
			task.wait(PURCHASE_SAVE_RETRY_DELAY)
		end
	end
	return isSaved()
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
