local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")

local Drops = require(ReplicatedStorage.Shared.Drops)
local FormatMoney = require(ReplicatedStorage.Shared.FormatMoney)
local ItemModel = require(ReplicatedStorage.Shared.ItemModel)
local Items = require(ReplicatedStorage.Shared.Items)
local PhysicalItem = require(ReplicatedStorage.Shared.PhysicalItem)
local Places = require(ReplicatedStorage.Shared.Places)

local CurrencyController = require(script.Parent.CurrencyController)

local LocalPlayer = Players.LocalPlayer

local BILLBOARD_NAME = "Collect_Gui" -- On a place's collect pad, with an Amount label for the uncollected cash
local COLLECT_NAME = "Collect" -- Model in a place with the collect pad
local STACK_PART_NAME = "StackPart" -- Invisible box over the collect pad that finished items stack up in
-- Spots across the stack part an item can go, this many each way. It goes on whichever is lowest,
-- so the stack rises evenly
local STACK_GRID = 3
local EDGE_INSET = 0.15 -- Share of the stack part's width and depth kept clear on each side
local SPOT_JITTER = 0.5 -- Studs an item may sit off its spot, so the stack doesn't look like a grid
local REBUILD_STAGGER = 0.05 -- Seconds between items when a saved stack is put back
local APPEAR_INFO = TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

-- Collected, every item flies up off the stack, then into the player, shrinking away as it goes.
-- The top of the stack goes first
local RISE_HEIGHT = 4 -- Studs
local RISE_INFO = TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local FLY_INFO = TweenInfo.new(0.45, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
-- They set off closer and closer together, so the ticks as they reach the player speed up
local FIRST_GAP = 0.2 -- Seconds between the first item setting off and the second
local GAP_SHRINK = 0.85 -- Each gap is this share of the one before
local MIN_GAP = 0.04 -- Seconds; the fastest the ticks get
local MIN_SCALE = 0.02 -- Parts can't shrink to nothing
-- Each tick plays a little higher than the one before, up to MAX_TICK_PITCH
local TICK_PITCH_STEP = 0.02
local MAX_TICK_PITCH = 1.6
local MAX_TICK_SOUNDS = 8 -- Ticks heard at once; past this the oldest is cut short

type StackItem = {
	Part: BasePart, -- The item's outer part, with any others welded inside
}

-- Every place's stack is made on this client. The server keeps what's in each, and says so with
-- the place's CollectItems attribute. The player's own stack puts on a show: items fade in as they
-- finish, the saved stack comes back an item at a time, and collected items fly into the player.
-- Other players' stacks just show what's in them, changing at once
local stacks: { [Folder]: { StackItem } } = {}
local stackPlace: Folder? = nil -- The place whose saved stack has been put back, which happens once
local synced: { [Folder]: number } = {} -- Other places -> how many of their CollectItems are stacked
-- The pad streams out while the player is far down the slide, so items that finish then wait here
-- and are stacked once it's back
local pending: { [Folder]: { Items.Item } } = {}
local itemsFlying = 0 -- Collected items still on their way into the player
local lastCash: { [Folder]: number } = {} -- Each place's CollectCash when it was last seen
local tickSounds: { Sound } = {} -- Ticks still playing, oldest first

local CollectController = {}

local function isOwn(place: Folder): boolean
	return place:GetAttribute("OwnerUserId") == LocalPlayer.UserId
end

local function getStack(place: Folder): { StackItem }
	local stack = stacks[place]
	if not stack then
		stack = {}
		stacks[place] = stack
	end
	return stack
end

local function getStackPart(place: Folder): BasePart?
	local collect = place:FindFirstChild(COLLECT_NAME)
	local stackPart = collect and collect:FindFirstChild(STACK_PART_NAME)
	return if stackPart and stackPart:IsA("BasePart") then stackPart else nil
end

-- Half the height of a box turned this way, from its middle to its lowest corner
local function getHalfHeight(rotation: CFrame, size: Vector3): number
	return (
		math.abs(rotation.RightVector.Y) * size.X
		+ math.abs(rotation.UpVector.Y) * size.Y
		+ math.abs(rotation.LookVector.Y) * size.Z
	) / 2
end

-- An item lands on the stack where the lowest of the spots is, lowered from the top of the stack
-- part until it meets what's already there. Nil once even the lowest spot would stick out the top
local function findLanding(stackPart: BasePart, rotation: CFrame, size: Vector3): CFrame?
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.RespectCanCollide = true
	params.FilterDescendantsInstances = if LocalPlayer.Character then { LocalPlayer.Character } else {}

	local halfHeight = getHalfHeight(rotation, size)
	local up = stackPart.CFrame.UpVector
	local fall = stackPart.Size.Y + halfHeight * 2
	local lowest: CFrame? = nil
	local lowestHeight = math.huge
	for column = 1, STACK_GRID do
		for row = 1, STACK_GRID do
			local x = ((column - 0.5) / STACK_GRID - 0.5) * stackPart.Size.X * (1 - EDGE_INSET * 2)
			local z = ((row - 0.5) / STACK_GRID - 0.5) * stackPart.Size.Z * (1 - EDGE_INSET * 2)
			x += (math.random() - 0.5) * 2 * SPOT_JITTER
			z += (math.random() - 0.5) * 2 * SPOT_JITTER
			local above = stackPart.CFrame * Vector3.new(x, stackPart.Size.Y / 2 + halfHeight, z)
			local start = CFrame.new(above) * rotation
			local hit = workspace:Blockcast(start, size, -up * fall, params)
			local landing = start - up * (if hit then hit.Distance else fall)
			local height = (landing.Position - stackPart.Position):Dot(up)
			-- Ties go either way, so the stack doesn't always start in the same corner
			if height < lowestHeight - 0.01 or (math.abs(height - lowestHeight) <= 0.01 and math.random() < 0.5) then
				lowest, lowestHeight = landing, height
			end
		end
	end

	if lowestHeight + halfHeight > stackPart.Size.Y / 2 then
		return nil
	end
	return lowest
end

-- A finished item appears on top of the stack, anchored where it lands. It fades in unless instant.
-- If the pad hasn't streamed in, it's stacked once it does
function CollectController.AddToPile(place: Folder, item: Items.Item, instant: boolean?)
	local stackPart = getStackPart(place)
	local stack = getStack(place)
	if not stackPart then
		local waiting = pending[place] or {}
		pending[place] = waiting
		if #stack + #waiting < Drops.MAX_PILE then
			table.insert(waiting, item)
		end
		return
	elseif #stack >= Drops.MAX_PILE then
		return
	end
	local modelled, size = PhysicalItem.GetShape(item)
	local rotation = CFrame.Angles(0, math.random() * 2 * math.pi, 0) * modelled
	local landing = findLanding(stackPart, rotation, size)
	if not landing then
		return
	end

	local copy = PhysicalItem.Create(item, landing)
	-- Only the outer part is anchored; the parts inside are welded to it, so they move with it
	copy.Anchored = true
	if not instant then
		ItemModel.SetLocalTransparency(copy, 1)
		ItemModel.TweenLocalTransparency(copy, APPEAR_INFO, 0)
	end
	copy.Parent = workspace
	table.insert(stack, { Part = copy })
end

local function addPending(place: Folder)
	local waiting = pending[place]
	pending[place] = nil
	for _, item in waiting or {} do
		CollectController.AddToPile(place, item)
	end
end

-- Played from the client, so only this player hears them
local function findSound(name: string): Sound? -- Sound in SoundService.SFX.Collection
	local sfx = SoundService:FindFirstChild("SFX")
	local collection = sfx and sfx:FindFirstChild("Collection")
	local sound = collection and collection:FindFirstChild(name)
	return if sound and sound:IsA("Sound") then sound else nil
end

local function playSound(name: string)
	local sound = findSound(name)
	if sound then
		sound:Play()
	end
end

-- Every tick is its own copy, so ticks close together all play out instead of restarting one sound,
-- which cuts it off before it's heard
local function playTick(pitch: number)
	local sound = findSound("Tick")
	if not sound then
		return
	end
	if #tickSounds >= MAX_TICK_SOUNDS then
		table.remove(tickSounds, 1):Destroy()
	end
	local copy = sound:Clone()
	copy.PlaybackSpeed = sound.PlaybackSpeed * pitch
	copy.Parent = sound.Parent
	table.insert(tickSounds, copy)
	copy.Ended:Connect(function()
		local index = table.find(tickSounds, copy)
		if index then
			table.remove(tickSounds, index)
		end
		copy:Destroy()
	end)
	copy:Play()
end

local function getRoot(): BasePart?
	local character = LocalPlayer.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	return if root and root:IsA("BasePart") then root else nil
end

-- Up off the stack, then into the player while shrinking. It follows the player if they move
local function flyToPlayer(stackItem: StackItem, startDelay: number, pitch: number)
	local part = stackItem.Part
	-- Off the stack now, so nothing lands on or touches it
	ItemModel.SetVisualOnly(part)

	task.wait(startDelay)
	local rise = TweenService:Create(part, RISE_INFO, { CFrame = part.CFrame + Vector3.yAxis * RISE_HEIGHT })
	rise:Play()
	rise.Completed:Wait()

	local from = part.CFrame
	local progress = Instance.new("NumberValue")
	progress.Changed:Connect(function(alpha: number)
		local root = getRoot()
		local target = if root then root.Position else from.Position
		part.CFrame = from.Rotation + from.Position:Lerp(target, alpha)
		ItemModel.SetScale(part, math.max(1 - alpha, MIN_SCALE))
	end)
	local fly = TweenService:Create(progress, FLY_INFO, { Value = 1 })
	fly:Play()
	fly.Completed:Wait()
	part:Destroy()
	progress:Destroy()
	playTick(pitch)

	-- Each item brings its share of the collected cash in as a bill, and the last brings the rest
	CurrencyController.PopCash(1 / itemsFlying)
	itemsFlying -= 1
end

local function collectStack(place: Folder)
	local stack = getStack(place)
	playSound("Collect")
	itemsFlying += #stack
	local startDelay, gap, pitch = 0, FIRST_GAP, 1
	for index = #stack, 1, -1 do
		task.spawn(flyToPlayer, stack[index], startDelay, pitch)
		startDelay += gap
		gap = math.max(gap * GAP_SHRINK, MIN_GAP)
		pitch = math.min(pitch + TICK_PITCH_STEP, MAX_TICK_PITCH)
	end
	table.clear(stack)
	pending[place] = nil
end

local function clearStack(place: Folder)
	local stack = getStack(place)
	for _, stackItem in stack do
		stackItem.Part:Destroy()
	end
	table.clear(stack)
	synced[place] = nil
	pending[place] = nil
end

local function getSavedIds(place: Folder): { string }
	local saved = place:GetAttribute("CollectItems")
	local ids = {}
	if typeof(saved) == "string" then
		for id in saved:gmatch("[^,]+") do
			table.insert(ids, id)
		end
	end
	return ids
end

-- Someone else's stack: items that finish there appear at once, and all of them vanish once it's
-- collected. Their pad may not have streamed in yet, in which case it's stacked once it does
local function syncOtherStack(place: Folder)
	local ids = getSavedIds(place)
	if #ids < (synced[place] or 0) then
		clearStack(place)
	end
	if not getStackPart(place) then
		return
	end
	for index = (synced[place] or 0) + 1, #ids do
		local item = Items[ids[index]]
		if item then
			CollectController.AddToPile(place, item, true)
		end
	end
	synced[place] = #ids
end

-- The saved stack comes back once, the first time the player's data shows up on their place. After
-- that, it grows as items finish here, and flies to the player when the pad is collected
local function onStackChanged(place: Folder)
	if not isOwn(place) then
		syncOtherStack(place)
		return
	end
	local saved = place:GetAttribute("CollectItems")
	if typeof(saved) ~= "string" then
		return
	end

	if stackPlace ~= place then
		stackPlace = place
		clearStack(place)
		for _, id in getSavedIds(place) do
			local item = Items[id]
			if item then
				CollectController.AddToPile(place, item)
				task.wait(REBUILD_STAGGER)
			end
		end
	elseif saved == "" then
		collectStack(place)
	end
end

-- Everyone sees what's waiting on each place's pad
local function showCash(place: Folder)
	local collect = place:FindFirstChild(COLLECT_NAME)
	local billboard = collect and collect:FindFirstChild(BILLBOARD_NAME, true)
	local amount = billboard and billboard:FindFirstChild("Amount", true)
	if amount and amount:IsA("TextLabel") then
		local cash = place:GetAttribute("CollectCash")
		amount.Text = FormatMoney(if typeof(cash) == "number" then cash else 0, 2)
	end
end

-- Cash going down on the player's own pad has been collected. It's kept off their cash counter
-- and pops out onto it a bill at a time, as its items fly into them
local function onCashChanged(place: Folder)
	local cash = place:GetAttribute("CollectCash")
	local last = lastCash[place]
	lastCash[place] = if typeof(cash) == "number" then cash else nil
	if not (isOwn(place) and typeof(cash) == "number" and last and cash < last) then
		return
	end
	CurrencyController.HoldCash(last - cash)
	-- Items still in the stack are about to fly, once the emptied CollectItems arrives. With none
	-- at all, it pops out in one go
	if itemsFlying == 0 and #getStack(place) == 0 then
		CurrencyController.PopCash(1)
	end
end

function CollectController.Start()
	for _, place in Places.GetAll() do
		showCash(place)
		local cash = place:GetAttribute("CollectCash")
		lastCash[place] = if typeof(cash) == "number" then cash else nil
		place:GetAttributeChangedSignal("CollectCash"):Connect(function()
			showCash(place)
			onCashChanged(place)
		end)
		-- The pad is streamed, so its billboard and stack part can arrive after the attributes
		place.DescendantAdded:Connect(function(descendant)
			if descendant.Name == BILLBOARD_NAME then
				showCash(place)
			elseif descendant.Name == STACK_PART_NAME then
				if isOwn(place) then
					addPending(place)
				else
					syncOtherStack(place)
				end
			end
		end)

		task.spawn(onStackChanged, place)
		place:GetAttributeChangedSignal("CollectItems"):Connect(function()
			onStackChanged(place)
		end)
		place:GetAttributeChangedSignal("OwnerUserId"):Connect(function()
			-- A new owner's cash on the pad isn't a collect, even if it's less than the last one's
			local ownCash = place:GetAttribute("CollectCash")
			lastCash[place] = if typeof(ownCash) == "number" then ownCash else nil
			-- Whatever was stacked here was the last owner's
			if stackPlace == place then
				stackPlace = nil
			end
			clearStack(place)
			onStackChanged(place)
		end)
	end
end

return CollectController
