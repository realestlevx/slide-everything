local Players = game:GetService("Players")
local ServerScriptService = game:GetService("ServerScriptService")

local ProfileStore = require(ServerScriptService.ServerPackages.ProfileStore)

local PROFILE_TEMPLATE = {
	Money = 0,
}

export type Data = typeof(PROFILE_TEMPLATE)

local PlayerStore = ProfileStore.New("PlayerStore", PROFILE_TEMPLATE)

local Profiles: { [Player]: typeof(PlayerStore:StartSessionAsync("")) } = {}

local PlayerData = {}

local MONEY_SUFFIXES = { "K", "M", "B", "T", "Qa", "Qi" }

-- 950 -> "$950", 1250 -> "$1.2K", 3000000 -> "$3M"
local function formatMoney(amount: number): string
	local sign = if amount < 0 then "-" else ""
	amount = math.floor(math.abs(amount))

	local suffixIndex = math.min(math.floor(math.log10(math.max(amount, 1)) / 3), #MONEY_SUFFIXES)
	if suffixIndex == 0 then
		return `{sign}${amount}`
	end

	-- Truncate to one decimal so 999999 shows as 999.9K rather than rounding up to 1000K
	local tenths = math.floor(amount * 10 / 1000 ^ suffixIndex)
	local short = if tenths % 10 == 0 then `{tenths // 10}` else string.format("%.1f", tenths / 10)

	return `{sign}${short}{MONEY_SUFFIXES[suffixIndex]}`
end

local function createLeaderstats(player: Player, data: Data)
	local leaderstats = Instance.new("Folder")
	leaderstats.Name = "leaderstats"

	local money = Instance.new("StringValue")
	money.Name = "Money"
	money.Value = formatMoney(data.Money)
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
	else
		profile:EndSession()
	end
end

function PlayerData.Get(player: Player): Data?
	local profile = Profiles[player]
	return profile and profile.Data
end

function PlayerData.SetMoney(player: Player, amount: number)
	local data = PlayerData.Get(player)
	if not data then
		return
	end

	data.Money = amount
	updateLeaderstat(player, "Money", formatMoney(amount))
end

function PlayerData.AddMoney(player: Player, amount: number)
	local data = PlayerData.Get(player)
	if not data then
		return
	end

	PlayerData.SetMoney(player, data.Money + amount)
end

function PlayerData.Start()
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

return PlayerData
