local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CashPasses = require(ReplicatedStorage.Shared.CashPasses)
local Tutorial = require(ReplicatedStorage.Shared.Tutorial)

local ButtonController = require(script.Parent.ButtonController)

local LocalPlayer = Players.LocalPlayer
local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")

local GUI_NAME = "Cash/Gem" -- ScreenGui with the cash counter
local BUTTON_NAME = "BuyCash" -- Button in it that offers the next cash pass up
local RECEIPT_TIMEOUT = 15 -- Seconds to wait for the server to hear of a purchase before offering again

local button: GuiButton? = nil
local receiptDue = false -- One's been bought, and the server's about to raise their multiplier

local CashPassController = {}

-- The next pass up from the best one they have. Nil once there's none left to offer, and while what
-- they have isn't known: a developer product can be bought again, so they'd pay for one they already
-- have. That's until their data has loaded, and while one they've bought is reaching the server
local function getNextTier()
	local current = LocalPlayer:GetAttribute("CashMultiplier")
	if typeof(current) ~= "number" or receiptDue then
		return nil
	end
	for _, tier in CashPasses.Tiers do
		if tier.Multiplier > current and tier.Id > 0 then
			return tier
		end
	end
	return nil
end

local function updateButton()
	if button then
		button.Visible = getNextTier() ~= nil and Tutorial.Allows(LocalPlayer, "Passes")
	end
end

-- Roblox tells the server once it's bought, which raises their multiplier (see ProductService)
local function promptNextTier()
	local tier = getNextTier()
	if tier then
		MarketplaceService:PromptProductPurchase(LocalPlayer, tier.Id)
	end
end

local function onPurchaseFinished(userId: number, productId: number, purchased: boolean)
	if userId ~= LocalPlayer.UserId or not purchased then
		return
	end
	for _, tier in CashPasses.Tiers do
		if tier.Id == productId then
			receiptDue = true
			updateButton()
			task.delay(RECEIPT_TIMEOUT, function()
				receiptDue = false
				updateButton()
			end)
			return
		end
	end
end

local function bindGui(gui: Instance)
	local found = gui:FindFirstChild(BUTTON_NAME, true)
	button = if found and found:IsA("GuiButton") then found else nil
	if button then
		button.Activated:Connect(promptNextTier)
		ButtonController.Animate(button)
		updateButton()
	end
end

function CashPassController.Start()
	LocalPlayer:GetAttributeChangedSignal("CashMultiplier"):Connect(function()
		receiptDue = false
		updateButton()
	end)
	MarketplaceService.PromptProductPurchaseFinished:Connect(onPurchaseFinished)
	LocalPlayer:GetAttributeChangedSignal(Tutorial.ATTRIBUTE):Connect(updateButton)

	-- The gui comes back fresh each time the character respawns
	PlayerGui.ChildAdded:Connect(function(child)
		if child.Name == GUI_NAME then
			bindGui(child)
		end
	end)
	local gui = PlayerGui:FindFirstChild(GUI_NAME)
	if gui then
		bindGui(gui)
	end
end

return CashPassController
