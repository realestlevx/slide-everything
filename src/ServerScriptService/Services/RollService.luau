local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Items = require(ReplicatedStorage.Shared.Items)
local Places = require(ReplicatedStorage.Shared.Places)
local Rolling = require(ReplicatedStorage.Shared.Rolling)

local InventoryService = require(script.Parent.InventoryService)
local PlayerDataService = require(script.Parent.PlayerDataService)

local RollResult = ReplicatedStorage.Remotes.RollResult
local BuyResult = ReplicatedStorage.Remotes.BuyResult

local BUY_COOLDOWN = 0.1 -- Seconds between buy presses that count, so spamming the prompt does nothing

local rng = Random.new()
local rolling: { [Folder]: boolean } = {}
local rollTokens: { [Folder]: number } = {} -- Bumped to cancel a roll that's still spinning
local landed: { [Folder]: Items.Item } = {} -- What sits on each stand, up for sale
local lastBuyTimes: { [Folder]: number } = {}

local RollService = {}

local function clearStand(place: Folder)
	landed[place] = nil
	Rolling.ClearStand((place :: any).RollStand_1)
end

local function finishRoll(place: Folder, item: Items.Item)
	landed[place] = item
	local stand = (place :: any).RollStand_1
	-- No highlight here: only the owner's local copy gets one (they're costly and capped per client)
	local display = Rolling.CreateDisplay(item, stand.Roll_Place)
	display.Name = "RolledItem"
	display.Parent = stand
	Rolling.ShowStats(stand.Roll_Place.Stuff_StatsDisplay, item)
end

local function onRollTriggered(place: Folder, player: Player)
	-- Prompts are hidden for non-owners on the client, but never trust that
	if place:GetAttribute("OwnerUserId") ~= player.UserId or rolling[place] then
		return
	end

	local token = (rollTokens[place] or 0) + 1
	rollTokens[place] = token
	rolling[place] = true

	local item = Rolling.Pick(rng)
	clearStand(place)
	-- The owner's client is already spinning; it only needs the result for the last item.
	-- Everyone else just sees the result land
	RollResult:FireClient(player, place, item.Id)

	-- The owner started spinning before this request arrived, so everyone else sees the result
	-- land as the owner's spin ends
	task.delay(Rolling.SPIN_DURATION, function()
		if rollTokens[place] ~= token then
			return
		end
		rolling[place] = nil
		finishRoll(place, item)
	end)
end

-- The owner buys whatever landed on their stand, which empties it
local function onBuyTriggered(place: Folder, player: Player)
	local item = landed[place]
	local data = PlayerDataService.Get(player)
	if place:GetAttribute("OwnerUserId") ~= player.UserId or not (item and data) then
		return
	end

	local now = os.clock()
	if now - (lastBuyTimes[place] or -math.huge) < BUY_COOLDOWN then
		return
	end
	lastBuyTimes[place] = now

	if data.Money < item.Price then
		BuyResult:FireClient(player, place, false)
		return
	end

	PlayerDataService.AddMoney(player, -item.Price)
	InventoryService.Give(player, item.Id)
	clearStand(place)
	BuyResult:FireClient(player, place, true)
end

local function onOwnerChanged(place: Folder)
	rollTokens[place] = (rollTokens[place] or 0) + 1
	rolling[place] = nil
	clearStand(place)
end

function RollService.Start()
	for _, place in Places.GetAll() do
		clearStand(place)

		local prompt = (place :: any).RollTools_Model.Proximity_Holder.RollProximity
		prompt.Triggered:Connect(function(player)
			onRollTriggered(place, player)
		end)
		local buyPrompt = (place :: any).RollStand_1.Roll_Place.ProximityPrompt
		buyPrompt.Triggered:Connect(function(player)
			onBuyTriggered(place, player)
		end)
		place:GetAttributeChangedSignal("OwnerUserId"):Connect(function()
			onOwnerChanged(place)
		end)
	end
end

return RollService
