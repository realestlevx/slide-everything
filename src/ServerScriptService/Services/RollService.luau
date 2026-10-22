local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local Items = require(ReplicatedStorage.Shared.Items)
local Places = require(ReplicatedStorage.Shared.Places)
local Rolling = require(ReplicatedStorage.Shared.Rolling)

local InventoryService = require(script.Parent.InventoryService)
local PlayerDataService = require(script.Parent.PlayerDataService)
local SignUpgradeService = require(script.Parent.SignUpgradeService)

local RollResult = ReplicatedStorage.Remotes.RollResult
local BuyResult = ReplicatedStorage.Remotes.BuyResult

local BUY_COOLDOWN = 0.1 -- Seconds between buy presses that count, so spamming the prompt does nothing
-- Place attribute StandItem<number> holds the Id of the item on that stand, so the owner's client can
-- offer it even when it wasn't rolled just now (put back from their last visit)
local STAND_ITEM_ATTRIBUTE = "StandItem"
local ROLL_SLOTS = "RollSlots" -- The sign upgrade for how many stands a roll fills
local STAND_TEMPLATE_NAME = "RollStand_1" -- Model in ServerStorage the extra stands are copied from
-- Invisible parts anywhere in a place marking where its extra stands go. Each stands in for its
-- stand's Roll_Place and carries the stand's StandNumber attribute: 2 and up, as stand 1 is built in
local STAND_POSITION_NAME = "RollSlot_Position"
local ROLL_PLACE_NAME = "Roll_Place"

local rng = Random.new()
local stands: { [Folder]: { [number]: Model } } = {} -- Every stand in each place by number, bought or not
local rolling: { [Folder]: boolean } = {}
local rollTokens: { [Folder]: number } = {} -- Bumped to cancel a roll that's still spinning
local landed: { [Model]: Items.Item } = {} -- What sits on each stand, up for sale
local lastBuyTimes: { [Model]: number } = {}

local RollService = {}

local function getOwner(place: Folder): Player?
	local ownerId = place:GetAttribute("OwnerUserId")
	return if typeof(ownerId) == "number" then Players:GetPlayerByUserId(ownerId) else nil
end

-- Puts a copy of the stand template on each of the place's RollSlot_Position parts. The part goes
-- once its stand is there
local function spawnStands(place: Folder)
	local placeStands = {}
	stands[place] = placeStands

	local builtIn = place:FindFirstChild(Places.GetStandName(1))
	if builtIn and builtIn:IsA("Model") then
		placeStands[1] = builtIn
	else
		warn(`{place:GetFullName()} needs a {Places.GetStandName(1)} model to roll on`)
	end

	local template = ServerStorage:FindFirstChild(STAND_TEMPLATE_NAME)
	local templateSpot = template and template:FindFirstChild(ROLL_PLACE_NAME)
	if not (template and template:IsA("Model") and templateSpot and templateSpot:IsA("BasePart")) then
		warn(`ServerStorage needs a {STAND_TEMPLATE_NAME} model with a {ROLL_PLACE_NAME} part for extra roll stands`)
		return
	end
	local pivotOffset = templateSpot.CFrame:ToObjectSpace(template:GetPivot())

	for _, marker in place:GetDescendants() do
		if not (marker:IsA("BasePart") and marker.Name == STAND_POSITION_NAME) then
			continue
		end
		local number = marker:GetAttribute("StandNumber")
		if typeof(number) ~= "number" or number < 2 or placeStands[number] then
			warn(`{marker:GetFullName()} needs a StandNumber attribute of 2 or more, unlike the place's other stands`)
			continue
		end

		local stand = template:Clone()
		stand.Name = Places.GetStandName(number)
		-- Streamed in whole, so a client gets every part of it at once, like for its grow when bought
		-- (see StandUnlockController)
		stand.ModelStreamingMode = Enum.ModelStreamingMode.Atomic
		stand:PivotTo(marker.CFrame * pivotOffset)
		placeStands[number] = stand
		marker:Destroy()
	end
end

-- The stands the owner's roll fills, in order: as many as their Roll Slots upgrade gives
local function getRollStands(place: Folder): { number }
	local owner = getOwner(place)
	local count = if owner then SignUpgradeService.GetValue(owner, ROLL_SLOTS) else 1
	local numbers = {}
	for number in stands[place] do
		if number <= count then
			table.insert(numbers, number)
		end
	end
	table.sort(numbers)
	return numbers
end

local function clearStand(place: Folder, number: number)
	local stand = stands[place][number]
	landed[stand] = nil
	place:SetAttribute(`{STAND_ITEM_ATTRIBUTE}{number}`, nil)
	Rolling.ClearStand(stand)
end

local function clearStands(place: Folder)
	for number in stands[place] do
		clearStand(place, number)
	end
end

-- Stands the owner hasn't bought aren't there at all, for anyone
local function updateShown(place: Folder)
	local shown = {}
	for _, number in getRollStands(place) do
		shown[number] = true
	end
	for number, stand in stands[place] do
		stand.Parent = if shown[number] then place else nil
	end
end

local function finishRoll(place: Folder, number: number, item: Items.Item)
	local stand = stands[place][number] :: any
	landed[stand] = item
	place:SetAttribute(`{STAND_ITEM_ATTRIBUTE}{number}`, item.Id)
	-- No highlight here: only the owner's local copy gets one (they're costly and capped per client)
	local display = Rolling.CreateDisplay(item, stand.Roll_Place)
	display.Name = "RolledItem"
	display.Parent = stand
	Rolling.ShowStats(stand.Roll_Place.Stuff_StatsDisplay, item)
end

-- One pull of the lever rolls every stand the owner has, each for an item of its own
local function onRollTriggered(place: Folder, player: Player)
	-- Prompts are hidden for non-owners on the client, but never trust that
	if place:GetAttribute("OwnerUserId") ~= player.UserId or rolling[place] then
		return
	end

	local token = (rollTokens[place] or 0) + 1
	rollTokens[place] = token
	rolling[place] = true

	local luck = SignUpgradeService.GetValue(player, "Luck")
	local picks: { [number]: Items.Item } = {}
	local pickIds: { [string]: string } = {} -- Text keys, so the remote and the save keep them
	for _, number in getRollStands(place) do
		local item = Rolling.Pick(rng, luck)
		picks[number] = item
		pickIds[tostring(number)] = item.Id
	end
	clearStands(place)
	-- Saved as soon as they're picked, so leaving mid-spin still keeps them
	local data = PlayerDataService.Get(player)
	if data then
		data.LastRolls = table.clone(pickIds)
	end
	-- The owner's client is already spinning; it only needs the results for the last items.
	-- Everyone else just sees the results land
	RollResult:FireClient(player, place, pickIds)

	-- The owner started spinning before this request arrived, so everyone else sees the results
	-- land as the owner's spin ends
	task.delay(Rolling.SPIN_DURATION, function()
		if rollTokens[place] ~= token then
			return
		end
		rolling[place] = nil
		for number, item in picks do
			finishRoll(place, number, item)
		end
	end)
end

-- The owner buys whatever landed on one of their stands, which empties that stand
local function onBuyTriggered(place: Folder, number: number, player: Player)
	local stand = stands[place][number]
	local item = landed[stand]
	local data = PlayerDataService.Get(player)
	if place:GetAttribute("OwnerUserId") ~= player.UserId or not (item and data) then
		return
	end

	local now = os.clock()
	if now - (lastBuyTimes[stand] or -math.huge) < BUY_COOLDOWN then
		return
	end
	lastBuyTimes[stand] = now

	if data.Money < item.Price then
		BuyResult:FireClient(player, place, number, false)
		return
	end

	PlayerDataService.AddMoney(player, -item.Price)
	InventoryService.Give(player, item.Id)
	data.LastRolls[tostring(number)] = nil
	clearStand(place, number)
	BuyResult:FireClient(player, place, number, true)
end

-- The owner's unbought rolls from last time go back on their stands. Needs both the place and the
-- owner's data, which can be ready in either order
local function restoreLastRolls(place: Folder)
	local owner = getOwner(place)
	local data = owner and PlayerDataService.Get(owner)
	if not data or rolling[place] then
		return
	end
	for _, number in getRollStands(place) do
		local id = data.LastRolls[tostring(number)]
		local item = id and Items[id]
		if item and not landed[stands[place][number]] then
			finishRoll(place, number, item)
		end
	end
end

local function onOwnerChanged(place: Folder)
	rollTokens[place] = (rollTokens[place] or 0) + 1
	rolling[place] = nil
	clearStands(place)
	updateShown(place)
	restoreLastRolls(place)
end

function RollService.Start()
	local places = Places.GetAll()
	PlayerDataService.Loaded:Connect(function(player)
		for _, place in places do
			if place:GetAttribute("OwnerUserId") == player.UserId then
				updateShown(place)
				restoreLastRolls(place)
			end
		end
	end)

	for _, place in places do
		spawnStands(place)
		for number, stand in stands[place] do
			clearStand(place, number)
			local rollPlace = stand:FindFirstChild(ROLL_PLACE_NAME)
			local buyPrompt = rollPlace and rollPlace:FindFirstChildOfClass("ProximityPrompt")
			if buyPrompt then
				buyPrompt.Triggered:Connect(function(player)
					onBuyTriggered(place, number, player)
				end)
			else
				warn(`{stand:GetFullName()} needs a {ROLL_PLACE_NAME} part with a ProximityPrompt to buy from`)
			end
		end
		updateShown(place)

		local prompt = (place :: any).RollTools_Model.Proximity_Holder.RollProximity
		prompt.Triggered:Connect(function(player)
			onRollTriggered(place, player)
		end)
		place:GetAttributeChangedSignal("OwnerUserId"):Connect(function()
			onOwnerChanged(place)
		end)
		-- A stand bought from the sign
		place:GetAttributeChangedSignal(`{ROLL_SLOTS}Level`):Connect(function()
			updateShown(place)
		end)
	end
end

return RollService
