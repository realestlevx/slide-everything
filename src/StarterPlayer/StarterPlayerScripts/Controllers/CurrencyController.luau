local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")

local FormatMoney = require(ReplicatedStorage.Shared.FormatMoney)

local LocalPlayer = Players.LocalPlayer
local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")

local GUI_NAME = "Cash/Gem" -- ScreenGui with a Cash and a Gem frame, each with an Amount label
local EFFECTS_NAME = "CashEffects" -- ScreenGui with a hidden Cash template for the bills that fly in
local CASH_TEMPLATE_NAME = "Cash"
local ICON_NAME = "ImageLabel" -- The icon in the Cash frame that the bills fly into

-- The counters count to a new amount rather than jumping to it
local COUNT_INFO = TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

-- Collected cash pops out of the middle of the screen as bills, one as each of its items reaches
-- the player, which then fly into the cash counter. Each one counts its share onto the counter and
-- makes it grow a little
local POP_INFO = TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local POP_MIN_SPREAD = 0.08 -- Share of the screen's height a bill pops out from the middle, at least
local POP_MAX_SPREAD = 0.2 -- And at most
local HANG_TIME = 0.1 -- Seconds a bill hangs where it popped out to
local FLY_INFO = TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
local PULSE_SCALE = 1.1
local PULSE_GROW_INFO = TweenInfo.new(0.05, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local PULSE_SHRINK_INFO = TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
-- Seconds held cash waits to be popped out before it goes onto the counter anyway, so the counter
-- can't stay short if the collect never finishes here
local HOLD_TIMEOUT = 10
local COIN_SOUND_NAME = "Coin" -- Sound in SoundService.SFX, played as each bill lands in the counter

type Counter = {
	Attribute: string, -- The player attribute the server keeps the real amount in
	Format: (number) -> string,
	Label: TextLabel?,
	Shown: NumberValue, -- What the label shows, counting toward the real amount
	Loaded: boolean, -- Has had a real amount; the first one is shown straight away
}

local heldCash = 0 -- Collected cash that isn't on the counter yet, while it's shown flying in
local waitingCash = 0 -- The part of that not popped out yet
local billsFlying = 0
local holds = 0 -- Counts every hold, so a hold's timeout can tell a later one has taken over
local cashIcon: GuiObject? = nil
local cashPulse: UIScale? = nil

local CurrencyController = {}

local function makeCounter(attribute: string, format: (number) -> string): Counter
	local counter: Counter = {
		Attribute = attribute,
		Format = format,
		Label = nil,
		Shown = Instance.new("NumberValue"),
		Loaded = false,
	}
	counter.Shown.Changed:Connect(function(shown: number)
		if counter.Label then
			counter.Label.Text = format(shown)
		end
	end)
	return counter
end

local cashCounter = makeCounter("Money", FormatMoney)
local gemCounter = makeCounter("Gems", function(amount: number)
	-- Shortened like money is, without the $
	return (FormatMoney(amount):gsub("^%$", ""))
end)

-- Counts the label to the player's amount, less any cash still on its way in. Nothing to count to
-- while their data loads
local function update(counter: Counter)
	local amount = LocalPlayer:GetAttribute(counter.Attribute)
	if typeof(amount) ~= "number" then
		return
	end
	if counter == cashCounter then
		amount -= heldCash
	end
	if counter.Loaded then
		-- A new tween on Value replaces the running one, so it counts on from wherever it's got to
		TweenService:Create(counter.Shown, COUNT_INFO, { Value = amount }):Play()
	else
		counter.Loaded = true
		counter.Shown.Value = amount
	end
end

-- Grows from its middle and springs back. Another before it's back keeps it grown
local function pulseCash()
	local pulse = cashPulse
	if not pulse then
		return
	end
	local grow = TweenService:Create(pulse, PULSE_GROW_INFO, { Scale = PULSE_SCALE })
	grow.Completed:Connect(function(state: Enum.PlaybackState)
		if state == Enum.PlaybackState.Completed then
			TweenService:Create(pulse, PULSE_SHRINK_INFO, { Scale = 1 }):Play()
		end
	end)
	grow:Play()
end

-- Each bill plays its own copy, so bills landing close together don't cut each other off
local function playCoin()
	local sfx = SoundService:FindFirstChild("SFX")
	local sound = sfx and sfx:FindFirstChild(COIN_SOUND_NAME)
	if not (sound and sound:IsA("Sound")) then
		return
	end
	local copy = sound:Clone()
	copy.Parent = sfx
	copy.Ended:Connect(function()
		copy:Destroy()
	end)
	copy:Play()
end

-- A bill's share of the held cash reaches the counter. Once the last bill is in, whatever's left of
-- them is let in exactly, so rounding can't leave the counter a little short
local function letIn(amount: number)
	billsFlying -= 1
	heldCash = if billsFlying == 0 then waitingCash else math.max(heldCash - amount, 0)
	update(cashCounter)
	pulseCash()
end

-- Everything in the Cash frame moves into a holder the same size that grows from its middle, since
-- a UIScale on the frame itself would grow it from its corner. The frame stays where it is for the
-- HUD to slide
local function makePulse(frame: GuiObject): UIScale
	local holder = Instance.new("Frame")
	holder.Name = "PulseHolder"
	holder.BackgroundTransparency = 1
	holder.BorderSizePixel = 0
	holder.AnchorPoint = Vector2.new(0.5, 0.5)
	holder.Position = UDim2.fromScale(0.5, 0.5)
	holder.Size = UDim2.fromScale(1, 1)
	for _, child in frame:GetChildren() do
		if child:IsA("GuiObject") then
			child.Parent = holder
		end
	end
	holder.Parent = frame

	local pulse = Instance.new("UIScale")
	pulse.Parent = holder
	return pulse
end

-- Pops out from the middle of the screen, hangs there a moment, then flies into the icon,
-- shrinking to its size. Timed by the clock rather than its tweens, so its share still gets in if
-- the gui is made again on a respawn partway through
local function flyBill(effects: ScreenGui, template: GuiObject, amount: number)
	local bill = template:Clone()
	bill.AnchorPoint = Vector2.new(0.5, 0.5)
	bill.Position = UDim2.fromScale(0.5, 0.5)
	bill.Visible = true
	local scale = Instance.new("UIScale")
	scale.Scale = 0
	scale.Parent = bill
	bill.Parent = effects

	-- Positions are offsets from the effects gui's corner, so screen points are measured from there
	local function getCenter(gui: GuiObject): Vector2
		return gui.AbsolutePosition + gui.AbsoluteSize / 2 - effects.AbsolutePosition
	end

	local angle = math.random() * 2 * math.pi
	local spread = effects.AbsoluteSize.Y * (POP_MIN_SPREAD + math.random() * (POP_MAX_SPREAD - POP_MIN_SPREAD))
	local popped = effects.AbsoluteSize / 2 + Vector2.new(math.cos(angle), math.sin(angle)) * spread

	TweenService:Create(scale, POP_INFO, { Scale = 1 }):Play()
	TweenService:Create(bill, POP_INFO, { Position = UDim2.fromOffset(popped.X, popped.Y) }):Play()

	task.wait(POP_INFO.Time + HANG_TIME)
	-- Popped out fully by now, so this is its whole size
	local from = getCenter(bill)
	local size = bill.AbsoluteSize.Y
	local progress = Instance.new("NumberValue")
	-- The icon is looked up every frame, so the bill still meets it if it moves or grows
	progress.Changed:Connect(function(alpha: number)
		local icon = cashIcon
		if not (icon and bill.Parent) then
			return
		end
		local at = from:Lerp(getCenter(icon), alpha)
		bill.Position = UDim2.fromOffset(at.X, at.Y)
		local iconScale = icon.AbsoluteSize.Y / math.max(size, 1)
		scale.Scale = 1 + (iconScale - 1) * alpha
	end)
	TweenService:Create(progress, FLY_INFO, { Value = 1 }):Play()
	task.wait(FLY_INFO.Time)
	progress:Destroy()
	bill:Destroy()
	playCoin()
	letIn(amount)
end

-- Collected cash is kept off the counter until PopCash shows it flying in, so the counter doesn't
-- jump while the collected items are still on their way to the player
function CurrencyController.HoldCash(amount: number)
	if amount <= 0 then
		return
	end
	heldCash += amount
	waitingCash += amount
	update(cashCounter)

	holds += 1
	local hold = holds
	task.delay(HOLD_TIMEOUT, function()
		if holds == hold then
			CurrencyController.PopCash(1)
		end
	end)
end

-- A share of the held cash, 0 to 1, pops out of the middle of the screen as a bill that flies into
-- the counter. 1 pops all that's left. Without the effects gui or the counter, it goes straight on
function CurrencyController.PopCash(share: number)
	if waitingCash <= 0 then
		return
	end
	local amount = if share >= 1 then waitingCash else waitingCash * share
	waitingCash -= amount
	billsFlying += 1

	local effects = PlayerGui:FindFirstChild(EFFECTS_NAME)
	local template = effects and effects:FindFirstChild(CASH_TEMPLATE_NAME)
	local icon = cashIcon
	local counterGui = icon and icon:FindFirstAncestorWhichIsA("ScreenGui")
	if not (effects and effects:IsA("ScreenGui") and template and template:IsA("GuiObject") and counterGui) then
		letIn(amount)
		return
	end

	-- Laid out over the same part of the screen as the counter, so a bill lands right on the icon,
	-- and drawn over the counter as it gets there
	effects.ScreenInsets = counterGui.ScreenInsets
	effects.DisplayOrder = math.max(effects.DisplayOrder, counterGui.DisplayOrder + 1)

	task.spawn(flyBill, effects, template, amount)
end

-- The gui is made again on every respawn, so its labels are picked up again each time. The Cash
-- and Gem frames are found wherever they are in it, so the frames around them can change
local function bindGui(gui: Instance)
	local cash = gui:FindFirstChild("Cash", true)
	local gem = gui:FindFirstChild("Gem", true)
	cashPulse = if cash and cash:IsA("GuiObject") then makePulse(cash) else nil

	local cashAmount = cash and cash:FindFirstChild("Amount", true)
	local gemAmount = gem and gem:FindFirstChild("Amount", true)
	cashCounter.Label = if cashAmount and cashAmount:IsA("TextLabel") then cashAmount else nil
	gemCounter.Label = if gemAmount and gemAmount:IsA("TextLabel") then gemAmount else nil
	local icon = cash and cash:FindFirstChild(ICON_NAME, true)
	cashIcon = if icon and icon:IsA("GuiObject") then icon else nil

	for _, counter in { cashCounter, gemCounter } do
		if counter.Label then
			counter.Label.Text = counter.Format(counter.Shown.Value)
		end
	end
end

function CurrencyController.Start()
	LocalPlayer:GetAttributeChangedSignal("Money"):Connect(function()
		update(cashCounter)
	end)
	LocalPlayer:GetAttributeChangedSignal("Gems"):Connect(function()
		update(gemCounter)
	end)
	update(cashCounter)
	update(gemCounter)

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
