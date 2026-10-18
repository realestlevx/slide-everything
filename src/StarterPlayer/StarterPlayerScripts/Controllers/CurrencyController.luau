local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local FormatMoney = require(ReplicatedStorage.Shared.FormatMoney)

local LocalPlayer = Players.LocalPlayer
local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")

local GUI_NAME = "Cash/Gem" -- ScreenGui with a Cash and a Gem frame, each with an Amount label

local cashLabel: TextLabel? = nil
local gemLabel: TextLabel? = nil

local CurrencyController = {}

-- From the player's attributes, which the server keeps up to date. 0 while their data loads
local function getAmount(name: string): number
	local amount = LocalPlayer:GetAttribute(name)
	return if typeof(amount) == "number" then amount else 0
end

local function show()
	if cashLabel then
		cashLabel.Text = FormatMoney(getAmount("Money"))
	end
	if gemLabel then
		-- Shortened like money is, without the $
		gemLabel.Text = (FormatMoney(getAmount("Gems")):gsub("^%$", ""))
	end
end

-- The gui is made again on every respawn, so its labels are picked up again each time. The Cash
-- and Gem frames are found wherever they are in it, so the frames around them can change
local function bindGui(gui: Instance)
	local cash = gui:FindFirstChild("Cash", true)
	local gem = gui:FindFirstChild("Gem", true)
	local cashAmount = cash and cash:FindFirstChild("Amount")
	local gemAmount = gem and gem:FindFirstChild("Amount")
	cashLabel = if cashAmount and cashAmount:IsA("TextLabel") then cashAmount else nil
	gemLabel = if gemAmount and gemAmount:IsA("TextLabel") then gemAmount else nil
	show()
end

function CurrencyController.Start()
	LocalPlayer:GetAttributeChangedSignal("Money"):Connect(show)
	LocalPlayer:GetAttributeChangedSignal("Gems"):Connect(show)

	PlayerGui.ChildAdded:Connect(function(child)
		if child.Name == GUI_NAME then
			bindGui(child)
		end
	end)
	local gui = PlayerGui:FindFirstChild(GUI_NAME)
	if gui then
		task.spawn(bindGui, gui)
	end
end

return CurrencyController
