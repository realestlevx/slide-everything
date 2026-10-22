local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")

local ItemModel = require(ReplicatedStorage.Shared.ItemModel)
local Items = require(ReplicatedStorage.Shared.Items)
local Places = require(ReplicatedStorage.Shared.Places)
local Rarities = require(ReplicatedStorage.Shared.Rarities)
local Rolling = require(ReplicatedStorage.Shared.Rolling)
local SignUpgrades = require(ReplicatedStorage.Shared.SignUpgrades)

local FloatController = require(script.Parent.FloatController)
local PromptController = require(script.Parent.PromptController)

local RollResult = ReplicatedStorage.Remotes.RollResult
local BuyResult = ReplicatedStorage.Remotes.BuyResult
local LocalPlayer = Players.LocalPlayer

-- Set by the server on the place as StandItem<number>, to the Id of what's on that stand
local STAND_ITEM_ATTRIBUTE = "StandItem"
local ROLL_SLOTS = "RollSlots" -- The sign upgrade for how many stands a roll fills
local ROLL_PLACE_NAME = "Roll_Place"
local RESULT_TIMEOUT = 5 -- Stop a spin whose result never comes (the server turned the roll down)
local PRICE_ERROR_COLOR = Color3.fromRGB(255, 50, 50)
local PRICE_FLASH = TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.In) -- Fades the red back out

local LEVER_ANGLE = math.rad(45) -- Pulled towards the player
local LEVER_BOUNCE_ANGLE = math.rad(-15) -- Swings back past upright before settling
local LEVER_PULL = TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
local LEVER_BOUNCE = TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local LEVER_SETTLE = TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local POP = TweenInfo.new(Rolling.POP_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local OUTCOME_FADE = TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local FOV_ZOOM = 8 -- How far the field of view drops while rolling
local FOV_ZOOM_IN = TweenInfo.new(Rolling.SPIN_DURATION, Enum.EasingStyle.Sine, Enum.EasingDirection.Out)
local FOV_SNAP_BACK = TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out)

local allItems: { Items.Item } = {}
for _, item in Items do
	table.insert(allItems, item)
end

-- One roll stand, as this player sees it
type StandState = {
	Preview: BasePart?, -- The owner's local item: spinning, then their copy of the result
	Rolled: Items.Item?, -- What sits on the stand, offered by its buy prompt
}

local spinTokens: { [Folder]: number } = {} -- Bumped to stop a spin early
local spinning: { [Folder]: boolean } = {}
local results: { [Folder]: { [string]: string } } = {} -- The server's picks for the current spin, by stand number as text
local standStates: { [Folder]: { [number]: StandState } } = {}
local rollPrompts: { [Folder]: ProximityPrompt } = {} -- Hidden while their spin plays
local priceColors: { [TextLabel]: Color3 } = {} -- Each price label's own color, taken before it first flashes
local revealTweens: { [Folder]: { Tween } } = {}
local leverRestCFrames: { [BasePart]: CFrame } = {}
local restingFov: number? = nil -- The player's normal FOV, kept until the snap back has fully finished
local zoomed = false

local RollController = {}

-- FindFirstChild down a path; parts may not be streamed in yet
local function find(root: Instance, ...: string): any
	local current: Instance? = root
	for _, name in { ... } do
		current = current and current:FindFirstChild(name)
	end
	return current
end

local function findStand(place: Folder, number: number, ...: string): any
	return find(place, Places.GetStandName(number), ...)
end

local function getState(place: Folder, number: number): StandState
	local states = standStates[place]
	if not states then
		states = {}
		standStates[place] = states
	end
	local state = states[number]
	if not state then
		state = {}
		states[number] = state
	end
	return state
end

-- How many stands the owner's roll fills, from their Roll Slots level the server keeps on the place
local function getStandCount(place: Folder): number
	local level = place:GetAttribute(`{ROLL_SLOTS}Level`)
	return SignUpgrades.GetValue(ROLL_SLOTS, if typeof(level) == "number" then level else 1)
end

local function pullLever(place: Folder)
	local shaft = find(place, "RollTools_Model", "Lever", "Lever_Shaft")
	local base = find(place, "RollTools_Model", "Lever", "Lever_Bottom")
	local holder = find(place, "RollTools_Model", "Proximity_Holder")
	if not (shaft and base and holder) then
		return
	end

	local rest = leverRestCFrames[shaft] or shaft.CFrame
	leverRestCFrames[shaft] = rest

	-- Swing around the bottom of the shaft, along the base's long side, towards the prompt
	local pivot = rest.Position - rest.UpVector * shaft.Size.Y / 2
	local axis = base.CFrame.LookVector
	local towardsPlayer = if axis:Cross(rest.UpVector):Dot(holder.Position - pivot) >= 0 then 1 else -1

	local angle = Instance.new("NumberValue")
	angle.Changed:Connect(function(value)
		local rotation = CFrame.new(pivot) * CFrame.fromAxisAngle(axis, value * towardsPlayer) * CFrame.new(-pivot)
		shaft.CFrame = rotation * rest
	end)

	for _, step in { { LEVER_PULL, LEVER_ANGLE }, { LEVER_BOUNCE, LEVER_BOUNCE_ANGLE }, { LEVER_SETTLE, 0 } } do
		local tween = TweenService:Create(angle, step[1], { Value = step[2] })
		tween:Play()
		tween.Completed:Wait()
	end
	angle:Destroy()
end

local function clearPreview(place: Folder, number: number)
	local state = getState(place, number)
	if state.Preview then
		state.Preview:Destroy()
		state.Preview = nil
	end
end

-- Every emitter in Roll_Place's attachment runs while the spin plays (locally, so only the owner sees it)
local function setRollingParticles(place: Folder, number: number, enabled: boolean)
	local attachment = findStand(place, number, ROLL_PLACE_NAME, "ParticleEmmiterAttachment")
	if not attachment then
		return
	end
	for _, child in attachment:GetChildren() do
		if child:IsA("ParticleEmitter") then
			child.Enabled = enabled
		end
	end
end

-- Played from the client, so only the owner hears them. Replaying restarts the sound instead of
-- stacking copies, which keeps the fast ticks at the start of a spin from piling up
local function playSound(...: string) -- Path under SoundService.SFX
	local sound = find(SoundService, "SFX", ...)
	if sound then
		sound:Play()
	end
end

-- One burst from every emitter in Roll_Place's Finish attachment, sized by its EmitCount attribute
local function burstFinishParticles(place: Folder, number: number)
	local attachment = findStand(place, number, ROLL_PLACE_NAME, "Finish")
	if not attachment then
		return
	end
	for _, child in attachment:GetChildren() do
		local count = child:GetAttribute("EmitCount")
		if child:IsA("ParticleEmitter") and typeof(count) == "number" then
			child:Emit(count)
		end
	end
end

-- A newer tween on FieldOfView replaces the running one, so snapping back cuts the zoom short.
-- The resting FOV is only captured from a camera at rest, never from one still snapping back,
-- otherwise rolling again mid-snap would lower it a bit more every time
local function zoomCamera()
	local camera = workspace.CurrentCamera
	restingFov = restingFov or camera.FieldOfView
	zoomed = true
	TweenService:Create(camera, FOV_ZOOM_IN, { FieldOfView = restingFov - FOV_ZOOM }):Play()
end

local function restoreCamera()
	if not zoomed then
		return
	end
	zoomed = false

	local snapBack = TweenService:Create(workspace.CurrentCamera, FOV_SNAP_BACK, { FieldOfView = restingFov })
	snapBack.Completed:Connect(function(state)
		-- Cancelled means a new roll took over mid-snap and still needs the same resting FOV
		if state == Enum.PlaybackState.Completed and not zoomed then
			restingFov = nil
		end
	end)
	snapBack:Play()
end

-- Only up once a roll has landed: hidden on an empty stand and while the items spin
local function getBuyPrompt(place: Folder, number: number): ProximityPrompt?
	return findStand(place, number, ROLL_PLACE_NAME, "ProximityPrompt")
end

-- The text is set while the prompt is still hidden, since the prompt UI only reads it when shown
local function updateBuyPrompt(place: Folder, number: number)
	local prompt = getBuyPrompt(place, number)
	if not prompt then
		return
	end
	local item = getState(place, number).Rolled
	if item then
		-- "Buy" keeps the prompt's own color; only the name gets the rarity's gradient
		prompt.ActionText = `Buy {item.Name}`
		prompt:SetAttribute("ProximityTextGradient", item.Rarity)
		prompt:SetAttribute("ProximityGradientText", item.Name)
	end
	PromptController.SetHidden(place, prompt, item == nil)
end

local function setRolledItem(place: Folder, number: number, item: Items.Item?)
	getState(place, number).Rolled = item
	updateBuyPrompt(place, number)
end

-- Too expensive: the price on the stand's stats billboard flashes red and fades back to its own color
local function showBuyError(place: Folder, number: number)
	playSound("Error")

	local price = findStand(place, number, ROLL_PLACE_NAME, "Stuff_StatsDisplay", "Price") :: TextLabel?
	if not price then
		return
	end
	local color = priceColors[price] or price.TextColor3
	priceColors[price] = color
	-- Starting a new tween on TextColor3 cancels a flash that's still fading
	price.TextColor3 = PRICE_ERROR_COLOR
	TweenService:Create(price, PRICE_FLASH, { TextColor3 = color }):Play()
end

local function onBought(place: Folder, number: number)
	playSound("Buy")
	clearPreview(place, number)
	local stand = findStand(place, number)
	if stand then
		Rolling.ClearStand(stand)
	end
	setRolledItem(place, number, nil)
end

local function showRollPrompt(place: Folder)
	local prompt = rollPrompts[place]
	if prompt then
		rollPrompts[place] = nil
		PromptController.SetHidden(place, prompt, false)
	end
end

-- Inside and its light only change color on the owner's screen; everyone else sees the stand's own color
local function getGlowParts(place: Folder, number: number): { Instance }
	local inside = findStand(place, number, "Inside")
	local light = inside and inside:FindFirstChild("SurfaceLight")
	return { inside, light }
end

local function cancelSpin(place: Folder)
	-- Other places' owners changing must not end this player's zoom
	if spinning[place] then
		restoreCamera()
	end
	spinTokens[place] = (spinTokens[place] or 0) + 1
	spinning[place] = nil
	for number in standStates[place] or {} do
		clearPreview(place, number)
		setRollingParticles(place, number, false)
		setRolledItem(place, number, nil)
	end
	showRollPrompt(place)
end

local function showPreview(place: Folder, number: number, item: Items.Item)
	local stand = findStand(place, number)
	local rollPlace = stand and stand:FindFirstChild(ROLL_PLACE_NAME)
	if not rollPlace then
		return
	end

	clearPreview(place, number)
	local preview = Rolling.CreateDisplay(item, rollPlace)
	preview.Name = "RollPreview"
	Rolling.AddHighlight(preview, Rolling.ROLLING_HIGHLIGHT)

	ItemModel.SetScale(preview, 0.01)
	preview.Parent = stand
	getState(place, number).Preview = preview
	FloatController.Float(preview)
	ItemModel.TweenScale(preview, POP, 1)
end

-- The owner's reveal runs on their own timing, the moment their last items land. Their previews stay
-- as their copies of the results; the server's copies are for everyone else
local function reveal(place: Folder, picks: { [number]: Items.Item })
	spinning[place] = nil
	playSound("Rolling", "Reveal")
	restoreCamera()
	showRollPrompt(place)

	local tweens = {}
	for number, item in picks do
		setRollingParticles(place, number, false)
		burstFinishParticles(place, number)
		setRolledItem(place, number, item)

		local preview = getState(place, number).Preview
		if preview then
			for _, highlight in Rolling.GetHighlights(preview) do
				table.insert(tweens, TweenService:Create(highlight, OUTCOME_FADE, Rolling.GetOutcomeHighlight(item)))
			end
		end

		local rarityColor = Rarities[item.Rarity].Color
		for _, glow in getGlowParts(place, number) do
			table.insert(tweens, TweenService:Create(glow, OUTCOME_FADE, { Color = rarityColor }))
		end

		local billboard = findStand(place, number, ROLL_PLACE_NAME, "Stuff_StatsDisplay")
		if billboard then
			Rolling.ShowStats(billboard, item)
		end
	end

	for _, tween in tweens do
		tween:Play()
	end
	revealTweens[place] = tweens
end

-- The server's copy of what's on a stand is only kept by the owner when it wasn't rolled just now,
-- so it gets the outline the owner's own copy would have had
local function highlightServerCopy(place: Folder, number: number)
	local display = findStand(place, number, "RolledItem")
	local state = getState(place, number)
	if display and state.Rolled and not state.Preview and #Rolling.GetHighlights(display) == 0 then
		Rolling.AddHighlight(display, Rolling.GetOutcomeHighlight(state.Rolled))
	end
end

-- A roll put back from the owner's last visit lands without a spin here, so it gets the end of a
-- reveal: the buy prompt, the outline and the rarity's glow
local function showRestoredRoll(place: Folder, number: number)
	if place:GetAttribute("OwnerUserId") ~= LocalPlayer.UserId or spinning[place] or getState(place, number).Preview then
		return
	end
	local item = Items[place:GetAttribute(`{STAND_ITEM_ATTRIBUTE}{number}`)]
	if not item then
		return
	end

	setRolledItem(place, number, item)
	highlightServerCopy(place, number)
	local rarityColor = Rarities[item.Rarity].Color
	for _, glow in getGlowParts(place, number) do
		glow.Color = rarityColor
	end
end

-- Every stand with an item on it, as the server keeps them on the place
local function showRestoredRolls(place: Folder)
	for name in place:GetAttributes() do
		local number = tonumber(name:match(`^{STAND_ITEM_ATTRIBUTE}(%d+)$`))
		if number then
			showRestoredRoll(place, number)
		end
	end
end

local function randomFiller(previous: Items.Item?): Items.Item
	local item
	repeat
		item = allItems[math.random(#allItems)]
	until item ~= previous or #allItems == 1
	return item
end

-- The server's picks normally arrived long before the last items
local function waitForResult(place: Folder, token: number): { [number]: Items.Item }?
	local deadline = os.clock() + RESULT_TIMEOUT
	while not results[place] and spinTokens[place] == token and os.clock() < deadline do
		task.wait()
	end
	if spinTokens[place] ~= token then
		return nil
	end

	local pickIds = results[place]
	if not pickIds then
		cancelSpin(place)
		return nil
	end
	local picks = {}
	for key, id in pickIds do
		local number, item = tonumber(key), Items[id]
		if number and item then
			picks[number] = item
		end
	end
	return picks
end

local function spin(place: Folder, numbers: { number })
	local token = (spinTokens[place] or 0) + 1
	spinTokens[place] = token
	spinning[place] = true
	for _, number in numbers do
		setRollingParticles(place, number, true)
	end

	local startTime = os.clock()
	local previous: { [number]: Items.Item } = {}
	for step = 1, Rolling.SPIN_STEPS do
		-- Quadratic ease-out: swaps start fast and slow down until the result
		local progress = (step - 1) / (Rolling.SPIN_STEPS - 1)
		local swapTime = Rolling.SPIN_DURATION * (1 - math.sqrt(1 - progress))
		local remaining = swapTime - (os.clock() - startTime)
		if remaining > 0 then
			task.wait(remaining)
		end
		if spinTokens[place] ~= token then
			return
		end

		if step == Rolling.SPIN_STEPS then
			local picks = waitForResult(place, token)
			if picks then
				for number, item in picks do
					showPreview(place, number, item)
				end
				-- A stand the server didn't fill, if the stand count changed mid-spin, is left empty
				for _, number in numbers do
					if not picks[number] then
						clearPreview(place, number)
						setRollingParticles(place, number, false)
					end
				end
				reveal(place, picks)
			end
			return
		end

		for _, number in numbers do
			previous[number] = randomFiller(previous[number])
			showPreview(place, number, previous[number])
		end
		playSound("Rolling", "Tick")
	end
end

-- Starts the moment the prompt fires instead of waiting a round trip for the server.
-- Mirrors the server's checks so it only spins for rolls the server will accept
local function startRoll(place: Folder, prompt: ProximityPrompt)
	if place:GetAttribute("OwnerUserId") ~= LocalPlayer.UserId or spinning[place] then
		return
	end

	rollPrompts[place] = prompt
	PromptController.SetHidden(place, prompt, true)
	results[place] = nil
	-- A fade still running from the last reveal would paint over the black
	for _, tween in revealTweens[place] or {} do
		tween:Cancel()
	end
	revealTweens[place] = nil

	local numbers = {}
	for number = 1, getStandCount(place) do
		table.insert(numbers, number)
		setRolledItem(place, number, nil)
		clearPreview(place, number)
		local stand = findStand(place, number)
		if stand then
			Rolling.ClearStand(stand)
		end
		for _, glow in getGlowParts(place, number) do
			glow.Color = Rolling.ROLLING_COLOR
		end
	end
	zoomCamera()
	task.spawn(pullLever, place)
	task.spawn(spin, place, numbers)
end

-- A stand bought or streamed back in brings a fresh prompt that doesn't know it was hidden, and the
-- server's copy of its item
local function onDescendantAdded(place: Folder, descendant: Instance)
	if descendant:IsA("ProximityPrompt") then
		local rollPlace = descendant.Parent
		local stand = rollPlace and rollPlace.Name == ROLL_PLACE_NAME and rollPlace.Parent
		local number = stand and Places.GetStandNumber(stand)
		if number then
			updateBuyPrompt(place, number)
		end
	elseif descendant.Name == "RolledItem" then
		local number = descendant.Parent and Places.GetStandNumber(descendant.Parent)
		if not number then
			return
		end
		-- The owner already shows their own copy, so the server's would just sit on top of it
		if getState(place, number).Preview then
			descendant:Destroy()
		else
			FloatController.Float(descendant)
			highlightServerCopy(place, number)
		end
	end
end

function RollController.Start()
	local places = Places.GetAll()

	ProximityPromptService.PromptTriggered:Connect(function(prompt)
		if prompt.Name ~= "RollProximity" then
			return
		end
		for _, place in places do
			if prompt:IsDescendantOf(place) then
				startRoll(place, prompt)
			end
		end
	end)

	RollResult.OnClientEvent:Connect(function(place: Folder, pickIds: { [string]: string })
		results[place] = pickIds
	end)

	BuyResult.OnClientEvent:Connect(function(place: Folder, number: number, bought: boolean)
		if bought then
			onBought(place, number)
		else
			showBuyError(place, number)
		end
	end)

	for _, place in places do
		for _, child in place:GetChildren() do
			local number = Places.GetStandNumber(child)
			if number then
				updateBuyPrompt(place, number)
			end
		end
		for _, descendant in place:GetDescendants() do
			if descendant.Name == "RolledItem" then
				FloatController.Float(descendant)
			end
		end

		place.DescendantAdded:Connect(function(descendant)
			onDescendantAdded(place, descendant)
		end)
		place:GetAttributeChangedSignal("OwnerUserId"):Connect(function()
			cancelSpin(place)
			showRestoredRolls(place)
		end)
		place.AttributeChanged:Connect(function(name)
			local number = tonumber(name:match(`^{STAND_ITEM_ATTRIBUTE}(%d+)$`))
			if number then
				showRestoredRoll(place, number)
			end
		end)
		showRestoredRolls(place)
	end
end

return RollController
