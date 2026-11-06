local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GamePasses = require(ReplicatedStorage.Shared.GamePasses)
local Tutorial = require(ReplicatedStorage.Shared.Tutorial)

local ButtonController = require(script.Parent.ButtonController)

local LocalPlayer = Players.LocalPlayer
local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")

local GUI_NAME = "Cash/Gem" -- ScreenGui with the cash counter
local BUTTON_NAME = "BuyCash" -- Button in it that offers the next cash pass up

local button: GuiButton? = nil

local CashPassController = {}

-- The next pass up from the best one they have. Nil once there's none left to offer
local function getNextTier()
	local current = GamePasses.GetCashMultiplier(LocalPlayer)
	for _, tier in GamePasses.CashTiers do
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

-- Roblox tells the server once it's bought, which raises their multiplier
local function promptNextTier()
	local tier = getNextTier()
	if tier then
		MarketplaceService:PromptGamePassPurchase(LocalPlayer, tier.Id)
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
	LocalPlayer:GetAttributeChangedSignal("CashMultiplier"):Connect(updateButton)
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
