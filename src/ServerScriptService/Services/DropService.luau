local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Drops = require(ReplicatedStorage.Shared.Drops)
local Gems = require(ReplicatedStorage.Shared.Gems)
local Items = require(ReplicatedStorage.Shared.Items)
local Places = require(ReplicatedStorage.Shared.Places)
local Upgrades = require(ReplicatedStorage.Shared.Upgrades)

local InventoryService = require(script.Parent.InventoryService)
local PlaceService = require(script.Parent.PlaceService)
local PlayerDataService = require(script.Parent.PlayerDataService)
local SignUpgradeService = require(script.Parent.SignUpgradeService)

local DropResult = ReplicatedStorage.Remotes.DropResult
local GemsFound = ReplicatedStorage.Remotes.GemsFound

local DROP_BUTTON_NAME = "Drop_Button" -- Model in a place holding the prompt that drops its items
local COLLECT_NAME = "Collect" -- Model in a place with the collect pad and its prompt
-- The collect prompt sits on the pad's front edge, so the stack of items on the pad hid it from every
-- other side. It's seen through the stack, and reaches round to the back of the pad
local COLLECT_REACH = 20 -- Studs
local DROP_FLOOR_NAME = "DropPart" -- Under a place's slots; the way down its slide is measured from it
local COOLDOWN_SLACK = 0.5 -- Seconds. The client checks the cooldown on its own clock, a little ahead
local RESULT_SLACK = 5 -- Seconds past the drop's time that results may still arrive in, with lag
-- Items go no faster down the slide than the slide speed, plus a little to catch up with the pack.
-- A result can claim up to this many times as far as that speed goes in the drop's time
local SPEED_SLACK = 2
-- Studs. The client names the walls an item touched by how far down the slide they are, and each
-- names the wall here within this of it
local WALL_MATCH = 1

type DroppedItem = {
	Item: Items.Item,
	Level: number, -- As it was when dropped
	Paid: boolean,
}

type Drop = {
	StartedAt: number,
	-- The owner's Sliding Speed and Sliding Time when it started, so buying more mid-drop doesn't count
	Speed: number,
	Time: number,
	-- Down the place's slide, nearest first, at the owner's Slide upgrade when it started
	Walls: { Drops.Wall },
	Items: { [string]: DroppedItem }, -- Slot key -> what was in it
	FindsGems: boolean, -- Its items each get a chance of finding gems once collected (see onDrop)
}

local drops: { [Player]: Drop } = {} -- Each player's latest drop
local gemDrops: { [Player]: Drop } = {} -- Each player's latest drop whose items find gems
local gemChances: { [Player]: number } = {} -- Items on the collect pad that get a chance of finding gems
local walls: { [BasePart]: boolean } = {} -- Every multiplier wall
local rng = Random.new()

local DropService = {}

-- The collect pad shows its owner's uncollected cash, and their client piles up the items it came
-- from, both from attributes on the place: the pad is streamed, but the place's attributes reach
-- every client. Nil while nobody owns the place or the owner's data is still loading
local function updatePlace(place: Folder)
	local ownerId = place:GetAttribute("OwnerUserId")
	local owner = if typeof(ownerId) == "number" then Players:GetPlayerByUserId(ownerId) else nil
	local data = if owner then PlayerDataService.Get(owner) else nil
	place:SetAttribute("CollectCash", if data then data.CollectCash else nil)
	place:SetAttribute("CollectItems", if data then table.concat(data.CollectItems, ",") else nil)
end

-- The drop prompt starts a drop here too: what's in the slots right now can be paid for, once each.
-- The client runs the drop itself and reports how far each item got
local function onDrop(place: Folder, player: Player)
	local data = PlayerDataService.Get(player)
	if place:GetAttribute("OwnerUserId") ~= player.UserId or not data then
		return
	end
	local last = drops[player]
	if last and os.clock() - last.StartedAt < Drops.COOLDOWN - COOLDOWN_SLACK then
		return
	end

	local dropped: { [string]: DroppedItem } = {}
	for key, uid in data.Slots do
		local owned = InventoryService.Find(player, uid)
		local item = owned and Items[owned.Id]
		if owned and item then
			dropped[key] = { Item = item, Level = Upgrades.GetLevel(owned), Paid = false }
		end
	end
	if next(dropped) == nil then
		return
	end

	local slideWalls: { Drops.Wall } = {}
	local floor = place:FindFirstChild(DROP_FLOOR_NAME)
	if floor and floor:IsA("BasePart") then
		local start, direction = Drops.GetSlideLine(floor)
		local slide = SignUpgradeService.GetValue(player, "Slide")
		for wall in walls do
			Drops.AddWall(slideWalls, wall, start, direction, slide)
		end
	end
	-- A drop can be ended early, and starting the next one straight after would find gems far more
	-- often than drops that run their full time. So a drop's items find gems only once the last drop
	-- whose items did has had its full time. The client's clock runs a little ahead, as with the
	-- cooldown. Drops shorter than the cooldown always do, as none can come sooner anyway
	local lastGemDrop = gemDrops[player]
	local drop: Drop = {
		StartedAt = os.clock(),
		Speed = SignUpgradeService.GetValue(player, "SlideSpeed"),
		Time = SignUpgradeService.GetValue(player, "SlideTime"),
		Walls = slideWalls,
		Items = dropped,
		FindsGems = not lastGemDrop
			or os.clock() - lastGemDrop.StartedAt >= lastGemDrop.Time - COOLDOWN_SLACK,
	}
	drops[player] = drop
	if drop.FindsGems then
		gemDrops[player] = drop
	end
end

-- The walls down the slide that the client says an item touched, nearest first, each once. Only
-- walls known here count, at the multipliers they have here
local function getGates(drop: Drop, alongs: any): { Drops.Wall }
	local gates: { Drops.Wall } = {}
	if typeof(alongs) ~= "table" then
		return gates
	end
	-- An item can touch each wall only once, so a longer list is cut short
	local count = math.min(#alongs, #drop.Walls)
	for _, wall in drop.Walls do
		for index = 1, count do
			local along = alongs[index]
			if typeof(along) == "number" and math.abs(along - wall.Along) <= WALL_MATCH then
				table.insert(gates, wall)
				break
			end
		end
	end
	return gates
end

-- One item's finished run: how many studs down the slide it got and which walls it touched, which
-- come from the client, so the distance is held to what the slide speed allows. Only the walls it
-- touched multiply. The money waits on the collect pad, and the item joins the pile there
local function onResult(player: Player, slotKey: any, distance: any, alongs: any)
	local drop = drops[player]
	local data = PlayerDataService.Get(player)
	if not (drop and data and typeof(slotKey) == "string") then
		return
	end
	-- NaN fails every comparison, so it's turned away with anything else out of range
	if not (typeof(distance) == "number" and distance >= 0) then
		return
	end
	if os.clock() - drop.StartedAt > drop.Time + RESULT_SLACK then
		return
	end
	local dropped = drop.Items[slotKey]
	if not dropped or dropped.Paid then
		return
	end
	dropped.Paid = true

	local reached = math.min(distance, Drops.GetSlideSpeed(drop.Speed) * SPEED_SLACK * drop.Time)
	local paidDistance = Drops.Measure(getGates(drop, alongs), reached)
	local pay = Drops.GetPay(dropped.Item, dropped.Level, paidDistance, drop.Speed)
	data.CollectCash += pay
	if drop.FindsGems then
		gemChances[player] = (gemChances[player] or 0) + 1
	end
	table.insert(data.CollectItems, dropped.Item.Id)
	while #data.CollectItems > Drops.MAX_PILE do
		table.remove(data.CollectItems, 1)
	end
	local place = PlaceService.GetPlace(player)
	if place then
		updatePlace(place)
	end
end

-- Each collected item that gets a chance may find gems, more the more the player earns (see Gems).
-- The player's client pops a gem out of them for each item that found some as it flies into them
local function findGems(player: Player, data: PlayerDataService.Data)
	local found = 0
	for _ = 1, gemChances[player] or 0 do
		if rng:NextNumber() < Gems.COLLECT_CHANCE then
			found += 1
		end
	end
	gemChances[player] = 0
	if found > 0 then
		local gems = found * Gems.GetFind(data.MoneyPerSecond)
		PlayerDataService.AddGems(player, gems)
		GemsFound:FireClient(player, found, gems)
	end
end

-- The collect pad's prompt: everything waiting there goes into the player's money, and its items
-- may find them some gems
local function onCollect(place: Folder, player: Player)
	local data = PlayerDataService.Get(player)
	if place:GetAttribute("OwnerUserId") ~= player.UserId or not data then
		return
	end
	if data.CollectCash <= 0 and #data.CollectItems == 0 then
		return
	end

	PlayerDataService.AddMoney(player, data.CollectCash)
	data.CollectCash = 0
	table.clear(data.CollectItems)
	updatePlace(place)
	findGems(player, data)
end

local function findPrompt(place: Folder, name: string): ProximityPrompt?
	local holder = place:FindFirstChild(name)
	return holder and holder:FindFirstChildWhichIsA("ProximityPrompt", true)
end

local function watchWall(instance: Instance)
	if Drops.IsWall(instance) then
		walls[instance :: BasePart] = true
	end
end

function DropService.Start()
	for _, descendant in workspace:GetDescendants() do
		watchWall(descendant)
	end
	workspace.DescendantAdded:Connect(watchWall)
	workspace.DescendantRemoving:Connect(function(descendant)
		walls[descendant :: any] = nil
	end)

	for _, place in Places.GetAll() do
		local dropPrompt = findPrompt(place, DROP_BUTTON_NAME)
		if dropPrompt then
			dropPrompt.Triggered:Connect(function(player)
				onDrop(place, player)
			end)
		else
			warn(`{place.Name} needs a {DROP_BUTTON_NAME} with a ProximityPrompt for its items to drop`)
		end

		local collectPrompt = findPrompt(place, COLLECT_NAME)
		if collectPrompt then
			collectPrompt.RequiresLineOfSight = false
			collectPrompt.MaxActivationDistance = COLLECT_REACH
			collectPrompt.Triggered:Connect(function(player)
				onCollect(place, player)
			end)
		else
			warn(`{place.Name} needs a {COLLECT_NAME} model with a ProximityPrompt for drop cash to be collected`)
		end

		updatePlace(place)
		place:GetAttributeChangedSignal("OwnerUserId"):Connect(function()
			updatePlace(place)
		end)
	end

	PlayerDataService.Loaded:Connect(function(player)
		-- Items left on the pad last time still get their chance
		local data = PlayerDataService.Get(player)
		gemChances[player] = if data then #data.CollectItems else 0
		local place = PlaceService.GetPlace(player)
		if place then
			updatePlace(place)
		end
	end)

	DropResult.OnServerEvent:Connect(onResult)
	Players.PlayerRemoving:Connect(function(player)
		drops[player] = nil
		gemDrops[player] = nil
		gemChances[player] = nil
	end)
end

return DropService
