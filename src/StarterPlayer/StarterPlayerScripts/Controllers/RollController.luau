local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")

local Items = require(ReplicatedStorage.Shared.Items)
local Places = require(ReplicatedStorage.Shared.Places)
local Rarities = require(ReplicatedStorage.Shared.Rarities)
local Rolling = require(ReplicatedStorage.Shared.Rolling)

local FloatController = require(script.Parent.FloatController)
local PromptController = require(script.Parent.PromptController)

local RollResult = ReplicatedStorage.Remotes.RollResult
local BuyResult = ReplicatedStorage.Remotes.BuyResult
local LocalPlayer = Players.LocalPlayer

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

local spinTokens: { [Folder]: number } = {} -- Bumped to stop a spin early
local spinning: { [Folder]: boolean } = {}
local results: { [Folder]: string } = {} -- The server's pick for the current spin
local previews: { [Folder]: MeshPart } = {} -- The owner's local item: spinning, then their copy of the result
local rollPrompts: { [Folder]: ProximityPrompt } = {} -- Hidden while their spin plays
local rolledItems: { [Folder]: Items.Item } = {} -- What sits on the stand, offered by the buy prompt
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

local function clearPreview(place: Folder)
	local preview = previews[place]
	if preview then
		preview:Destroy()
		previews[place] = nil
	end
end

-- Every emitter in Roll_Place's attachment runs while the spin plays (locally, so only the owner sees it)
local function setRollingParticles(place: Folder, enabled: boolean)
	local attachment = find(place, "RollStand_1", "Roll_Place", "ParticleEmmiterAttachment")
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
local function burstFinishParticles(place: Folder)
	local attachment = find(place, "RollStand_1", "Roll_Place", "Finish")
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
local function getBuyPrompt(place: Folder): ProximityPrompt?
	return find(place, "RollStand_1", "Roll_Place", "ProximityPrompt")
end

-- The text is set while the prompt is still hidden, since the prompt UI only reads it when shown
local function updateBuyPrompt(place: Folder)
	local prompt = getBuyPrompt(place)
	if not prompt then
		return
	end
	local item = rolledItems[place]
	if item then
		-- "Buy" keeps the prompt's own color; only the name gets the rarity's gradient
		prompt.ActionText = `Buy {item.Name}`
		prompt:SetAttribute("ProximityTextGradient", item.Rarity)
		prompt:SetAttribute("ProximityGradientText", item.Name)
	end
	PromptController.SetHidden(place, prompt, item == nil)
end

local function setRolledItem(place: Folder, item: Items.Item?)
	rolledItems[place] = item
	updateBuyPrompt(place)
end

-- Too expensive: the price on the stats billboard flashes red and fades back to its own color
local function showBuyError(place: Folder)
	playSound("Error")

	local price = find(place, "RollStand_1", "Roll_Place", "Stuff_StatsDisplay", "Price") :: TextLabel?
	if not price then
		return
	end
	local color = priceColors[price] or price.TextColor3
	priceColors[price] = color
	-- Starting a new tween on TextColor3 cancels a flash that's still fading
	price.TextColor3 = PRICE_ERROR_COLOR
	TweenService:Create(price, PRICE_FLASH, { TextColor3 = color }):Play()
end

local function onBought(place: Folder)
	playSound("Buy")
	clearPreview(place)
	local stand = find(place, "RollStand_1")
	if stand then
		Rolling.ClearStand(stand)
	end
	setRolledItem(place, nil)
end

local function showRollPrompt(place: Folder)
	local prompt = rollPrompts[place]
	if prompt then
		rollPrompts[place] = nil
		PromptController.SetHidden(place, prompt, false)
	end
end

-- Inside and its light only change color on the owner's screen; everyone else sees the stand's own color
local function getGlowParts(place: Folder): { Instance }
	local inside = find(place, "RollStand_1", "Inside")
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
	clearPreview(place)
	setRollingParticles(place, false)
	showRollPrompt(place)
	setRolledItem(place, nil)
end

local function showPreview(place: Folder, item: Items.Item)
	local stand = find(place, "RollStand_1")
	local rollPlace = find(place, "RollStand_1", "Roll_Place")
	if not rollPlace then
		return
	end

	clearPreview(place)
	local preview = Rolling.CreateDisplay(item, rollPlace)
	preview.Name = "RollPreview"
	Rolling.AddHighlight(preview, Rolling.ROLLING_HIGHLIGHT)

	local fullSize = preview.Size
	preview.Size = fullSize * 0.01
	preview.Parent = stand
	previews[place] = preview
	FloatController.Float(preview)
	TweenService:Create(preview, POP, { Size = fullSize }):Play()
end

-- The owner's reveal runs on their own timing, the moment their last item lands. Their preview stays
-- as their copy of the result; the server's copy is for everyone else
local function reveal(place: Folder, item: Items.Item)
	spinning[place] = nil
	setRollingParticles(place, false)
	burstFinishParticles(place)
	playSound("Rolling", "Reveal")
	restoreCamera()
	showRollPrompt(place)
	setRolledItem(place, item)

	local tweens = {}
	local preview = previews[place]
	local highlight = preview and preview:FindFirstChildOfClass("Highlight")
	if highlight then
		table.insert(tweens, TweenService:Create(highlight, OUTCOME_FADE, Rolling.GetOutcomeHighlight(item)))
	end

	local rarityColor = Rarities[item.Rarity].Color
	for _, glow in getGlowParts(place) do
		table.insert(tweens, TweenService:Create(glow, OUTCOME_FADE, { Color = rarityColor }))
	end

	for _, tween in tweens do
		tween:Play()
	end
	revealTweens[place] = tweens

	local billboard = find(place, "RollStand_1", "Roll_Place", "Stuff_StatsDisplay")
	if billboard then
		Rolling.ShowStats(billboard, item)
	end
end

local function randomFiller(previous: Items.Item?): Items.Item
	local item
	repeat
		item = allItems[math.random(#allItems)]
	until item ~= previous or #allItems == 1
	return item
end

-- The server's pick normally arrived long before the last item
local function waitForResult(place: Folder, token: number): Items.Item?
	local deadline = os.clock() + RESULT_TIMEOUT
	while not results[place] and spinTokens[place] == token and os.clock() < deadline do
		task.wait()
	end
	if spinTokens[place] ~= token then
		return nil
	end

	local resultId = results[place]
	if not resultId then
		cancelSpin(place)
		return nil
	end
	return Items[resultId]
end

local function spin(place: Folder)
	local token = (spinTokens[place] or 0) + 1
	spinTokens[place] = token
	spinning[place] = true
	setRollingParticles(place, true)

	local startTime = os.clock()
	local previous
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
			local result = waitForResult(place, token)
			if result then
				showPreview(place, result)
				reveal(place, result)
			end
			return
		end

		previous = randomFiller(previous)
		showPreview(place, previous)
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
	setRolledItem(place, nil)
	results[place] = nil
	-- A fade still running from the last reveal would paint over the black
	for _, tween in revealTweens[place] or {} do
		tween:Cancel()
	end
	revealTweens[place] = nil
	clearPreview(place)
	local stand = find(place, "RollStand_1")
	if stand then
		Rolling.ClearStand(stand)
	end
	for _, glow in getGlowParts(place) do
		glow.Color = Rolling.ROLLING_COLOR
	end
	zoomCamera()
	task.spawn(pullLever, place)
	task.spawn(spin, place)
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

	RollResult.OnClientEvent:Connect(function(place: Folder, resultId: string)
		results[place] = resultId
	end)

	BuyResult.OnClientEvent:Connect(function(place: Folder, bought: boolean)
		if bought then
			onBought(place)
		else
			showBuyError(place)
		end
	end)

	for _, place in places do
		updateBuyPrompt(place)
		place.DescendantAdded:Connect(function(descendant)
			-- Streamed back in as a fresh prompt that doesn't know it was hidden
			if descendant == getBuyPrompt(place) then
				updateBuyPrompt(place)
			end
		end)

		for _, descendant in place:GetDescendants() do
			if descendant.Name == "RolledItem" then
				FloatController.Float(descendant)
			end
		end

		place.DescendantAdded:Connect(function(descendant)
			if descendant.Name ~= "RolledItem" then
				return
			end
			-- The owner already shows their own copy, so the server's would just sit on top of it
			if previews[place] then
				descendant:Destroy()
			else
				FloatController.Float(descendant)
			end
		end)
		place:GetAttributeChangedSignal("OwnerUserId"):Connect(function()
			cancelSpin(place)
		end)
	end
end

return RollController
