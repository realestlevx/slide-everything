local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")

local FormatMoney = require(ReplicatedStorage.Shared.FormatMoney)
local OfflineEarnings = require(ReplicatedStorage.Shared.OfflineEarnings)

local ButtonController = require(script.Parent.ButtonController)
local CurrencyController = require(script.Parent.CurrencyController)
local MenuController = require(script.Parent.MenuController)

local OfflineCashTaken = ReplicatedStorage.Remotes.OfflineCashTaken
local TakeOfflineCash = ReplicatedStorage.Remotes.TakeOfflineCash
local LocalPlayer = Players.LocalPlayer
local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")

local GUI_NAME = "OfflineEarnings"
local OPEN_DELAY = 1 -- Seconds it waits once there's something to show, so the player's arrived first
local ROBUX = "\u{E002}" -- Shows as the Robux icon
local PRICE_CHECK_ATTEMPTS = 3 -- Tries at asking Roblox what the product costs this player
local PRICE_CHECK_RETRY_DELAY = 2 -- Seconds between those tries
-- Seconds after a purchase before taking it as it is works again, if the server hasn't multiplied it by
-- then, so the popup can't get stuck open
local RECEIPT_TIMEOUT = 15
-- What they take pops out of the middle of the screen as bills that fly into the cash counter, one
-- after the other, closer and closer together, like the items they collect from their pad
local BILLS = 15
local FIRST_GAP = 0.2 -- Seconds between the first bill and the second
local GAP_SHRINK = 0.85 -- Each gap is this share of the one before
local MIN_GAP = 0.04 -- Seconds

local menu = MenuController.Create()
local offered = false -- It opens by itself once, when there's something waiting as they join
local receiptDue = false -- The product's been bought, and the server's about to multiply what's waiting
local price: number? = nil

-- Parts of the gui, which is remade on every respawn, so they're found again each time
local normalAmount: TextLabel? = nil
local multipliedAmount: TextLabel? = nil
local priceLabel: TextLabel? = nil

local OfflineEarningsController = {}

-- What's waiting drops to nothing as it's taken, which isn't shown while the popup closes
local function showAmounts()
	local waiting = OfflineEarnings.GetWaiting(LocalPlayer)
	if waiting <= 0 then
		return
	end
	if normalAmount then
		normalAmount.Text = FormatMoney(waiting)
	end
	if multipliedAmount then
		multipliedAmount.Text = FormatMoney(waiting * OfflineEarnings.MULTIPLIER)
	end
end

-- Hidden until Roblox has given it rather than showing whatever the design has
local function showPrice()
	local label = priceLabel
	if label then
		label.Visible = price ~= nil
		label.Text = `{ROBUX}{price}`
	end
end

-- Asks Roblox what the product costs this player. Regional pricing can make that less than the price
-- it's set at, so it's asked from here, a few times over if Roblox can't be reached
local function loadPrice()
	local ok, result
	for attempt = 1, PRICE_CHECK_ATTEMPTS do
		ok, result =
			pcall(MarketplaceService.GetProductInfoAsync, MarketplaceService, OfflineEarnings.PRODUCT_ID, Enum.InfoType.Product)
		if ok or attempt == PRICE_CHECK_ATTEMPTS then
			break
		end
		task.wait(PRICE_CHECK_RETRY_DELAY)
	end
	if not ok then
		warn(`Couldn't get the offline earnings product's price: {result}`)
		return
	end
	-- Nil while it's off sale, when the price stays hidden
	if typeof(result.PriceInRobux) == "number" then
		price = result.PriceInRobux
		showPrice()
	end
end

local function playSound(...: string) -- Path under SoundService.SFX
	local sound: Instance? = SoundService:FindFirstChild("SFX")
	for _, name in { ... } do
		sound = sound and sound:FindFirstChild(name)
	end
	if sound and sound:IsA("Sound") then
		sound:Play()
	end
end

local function offer()
	if offered or OfflineEarnings.GetWaiting(LocalPlayer) <= 0 then
		return
	end
	offered = true
	task.spawn(loadPrice)
	task.delay(OPEN_DELAY, function()
		-- A purchase left unfinished last time can take it before it opens
		if OfflineEarnings.GetWaiting(LocalPlayer) > 0 then
			MenuController.SetOpen(menu, true)
			playSound("Offline")
		end
	end)
end

local function onTake()
	if menu.IsOpen and not receiptDue then
		playSound("Collection", "Collect")
		MenuController.SetOpen(menu, false)
		TakeOfflineCash:FireServer()
	end
end

-- It only closes once the server's multiplied it. A prompt that's cancelled leaves it open
local function onMultiply()
	if menu.IsOpen then
		playSound("Collection", "Collect")
		MarketplaceService:PromptProductPurchase(LocalPlayer, OfflineEarnings.PRODUCT_ID)
	end
end

-- With the purchase on its way to the server, taking what's waiting as it is would leave it nothing to
-- multiply
local function onPurchaseFinished(userId: number, productId: number, purchased: boolean)
	if userId == LocalPlayer.UserId and productId == OfflineEarnings.PRODUCT_ID and purchased then
		receiptDue = true
		task.delay(RECEIPT_TIMEOUT, function()
			receiptDue = false
		end)
	end
end

local function popBills(amount: number)
	CurrencyController.HoldCash(amount)
	local gap = FIRST_GAP
	for left = BILLS, 1, -1 do
		CurrencyController.PopCash(1 / left)
		task.wait(gap)
		gap = math.max(gap * GAP_SHRINK, MIN_GAP)
	end
end

local function onTaken(amount: any)
	if typeof(amount) ~= "number" then
		return
	end
	receiptDue = false
	MenuController.SetOpen(menu, false)
	popBills(amount)
end

local function bindGui(gui: Instance)
	local frame = gui:WaitForChild("Main") :: GuiObject
	local content = frame:WaitForChild("Frame")
	local buttons = content:WaitForChild("Buttons")
	local takeButton = buttons:WaitForChild("NormalButton") :: GuiButton
	local multiplyButton = buttons:WaitForChild("MultiplierButton") :: GuiButton

	normalAmount = content:WaitForChild("NormalAmount") :: TextLabel
	multipliedAmount = content:WaitForChild("MultiplierAmount") :: TextLabel
	priceLabel = multiplyButton:WaitForChild("Price") :: TextLabel
	showAmounts()
	showPrice()

	MenuController.Bind(menu, frame)
	ButtonController.Animate(takeButton)
	ButtonController.Animate(multiplyButton)
	takeButton.Activated:Connect(onTake)
	multiplyButton.Activated:Connect(onMultiply)
end

function OfflineEarningsController.Start()
	PlayerGui.ChildAdded:Connect(function(child)
		if child.Name == GUI_NAME then
			bindGui(child)
		end
	end)
	local gui = PlayerGui:FindFirstChild(GUI_NAME)
	if gui then
		task.spawn(bindGui, gui)
	end

	OfflineCashTaken.OnClientEvent:Connect(onTaken)
	MarketplaceService.PromptProductPurchaseFinished:Connect(onPurchaseFinished)
	LocalPlayer:GetAttributeChangedSignal("CashMultiplier"):Connect(showAmounts)
	LocalPlayer:GetAttributeChangedSignal(OfflineEarnings.ATTRIBUTE):Connect(function()
		showAmounts()
		offer()
	end)
	offer()
end

return OfflineEarningsController
