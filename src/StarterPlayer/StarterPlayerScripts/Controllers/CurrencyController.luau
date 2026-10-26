local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")

local FormatMoney = require(ReplicatedStorage.Shared.FormatMoney)

local LocalPlayer = Players.LocalPlayer
local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")

local GUI_NAME = "Cash/Gem" -- ScreenGui with a Cash and a Gem frame, each with an Amount label
-- ScreenGui with a hidden Cash and Gem template, for the bills and gems that fly into their counters
local EFFECTS_NAME = "CashEffects"
local ICON_NAME = "ImageLabel" -- The icon in a counter's frame that its bills or gems fly into

-- The counters count to a new amount rather than jumping to it
local COUNT_INFO = TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

-- Collected cash pops out of the middle of the screen as bills, one as each of its items reaches
-- the player, which then fly into the cash counter. Each one counts its share onto the counter and
-- makes it grow a little. Found gems do the same into the gem counter
local POP_INFO = TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local POP_MIN_SPREAD = 0.08 -- Share of the screen's height a bill pops out from the middle, at least
local POP_MAX_SPREAD = 0.2 -- And at most
local HANG_TIME = 0.1 -- Seconds a bill hangs where it popped out to
local FLY_INFO = TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
local PULSE_SCALE = 1.1
local PULSE_GROW_INFO = TweenInfo.new(0.05, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local PULSE_SHRINK_INFO = TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
-- Seconds held cash or gems wait to be popped out before they go onto the counter anyway, so the
-- counter can't stay short if the collect never finishes here
local HOLD_TIMEOUT = 10

-- Gems found by a collect come in after its cash, a gem at a time, up to MAX_GEM_POPS of them that
-- share out what was found. They wait a moment first, as the collect's cash can get here just after
-- the gems do
local GEM_WAIT = 0.3 -- Seconds
local MAX_GEM_POPS = 5
local GEM_POP_GAP = 0.08 -- Seconds between one gem popping out and the next

type Counter = {
	Attribute: string, -- The player attribute the server keeps the real amount in
	Format: (number) -> string,
	Name: string, -- Its frame in the gui, and its template in the effects gui
	Sound: string, -- Sound in SoundService.SFX, played as each bill or gem lands in the counter
	Label: TextLabel?,
	Icon: GuiObject?,
	Pulse: UIScale?,
	Shown: NumberValue, -- What the label shows, counting toward the real amount
	Loaded: boolean, -- Has had a real amount; the first one is shown straight away
	Held: number, -- Gained but not on the counter yet, while it's shown flying in
	Waiting: number, -- The part of that not popped out yet
	Flying: number,
	Holds: number, -- Counts every hold, so a hold's timeout can tell a later one has taken over
}

local lastGems: number? = nil -- The player's gems when last seen, so gems found can be told apart

local CurrencyController = {}

local function makeCounter(attribute: string, name: string, sound: string, format: (number) -> string): Counter
	local counter: Counter = {
		Attribute = attribute,
		Format = format,
		Name = name,
		Sound = sound,
		Label = nil,
		Icon = nil,
		Pulse = nil,
		Shown = Instance.new("NumberValue"),
		Loaded = false,
		Held = 0,
		Waiting = 0,
		Flying = 0,
		Holds = 0,
	}
	counter.Shown.Changed:Connect(function(shown: number)
		if counter.Label then
			counter.Label.Text = format(shown)
		end
	end)
	return counter
end

local cashCounter = makeCounter("Money", "Cash", "Coin", FormatMoney)
local gemCounter = makeCounter("Gems", "Gem", "Gem", function(amount: number)
	-- Shortened like money is, without the $
	return (FormatMoney(amount):gsub("^%$", ""))
end)

-- Counts the label to the player's amount, less any still on its way in. Nothing to count to while
-- their data loads
local function update(counter: Counter)
	local amount = LocalPlayer:GetAttribute(counter.Attribute)
	if typeof(amount) ~= "number" then
		return
	end
	amount -= counter.Held
	if counter.Loaded then
		-- A new tween on Value replaces the running one, so it counts on from wherever it's got to
		TweenService:Create(counter.Shown, COUNT_INFO, { Value = amount }):Play()
	else
		counter.Loaded = true
		counter.Shown.Value = amount
	end
end

-- Grows from its middle and springs back. Another before it's back keeps it grown
local function pulse(counter: Counter)
	local scale = counter.Pulse
	if not scale then
		return
	end
	local grow = TweenService:Create(scale, PULSE_GROW_INFO, { Scale = PULSE_SCALE })
	grow.Completed:Connect(function(state: Enum.PlaybackState)
		if state == Enum.PlaybackState.Completed then
			TweenService:Create(scale, PULSE_SHRINK_INFO, { Scale = 1 }):Play()
		end
	end)
	grow:Play()
end

-- Each bill or gem plays its own copy, so ones landing close together don't cut each other off
local function playLanding(counter: Counter)
	local sfx = SoundService:FindFirstChild("SFX")
	local sound = sfx and sfx:FindFirstChild(counter.Sound)
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

-- A bill's or gem's share of the held amount reaches the counter. Once the last one is in, whatever's
-- left of them is let in exactly, so rounding can't leave the counter a little short
local function letIn(counter: Counter, amount: number)
	counter.Flying -= 1
	counter.Held = if counter.Flying == 0 then counter.Waiting else math.max(counter.Held - amount, 0)
	update(counter)
	pulse(counter)
end

-- Everything in a counter's frame moves into a holder the same size that grows from its middle,
-- since a UIScale on the frame itself would grow it from its corner. The frame stays where it is
-- for the HUD to slide
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

	local scale = Instance.new("UIScale")
	scale.Parent = holder
	return scale
end

-- Pops out from the middle of the screen, hangs there a moment, then flies into the counter's
-- icon, shrinking to its size. Timed by the clock rather than its tweens, so its share still gets
-- in if the gui is made again on a respawn partway through
local function flyIn(counter: Counter, effects: ScreenGui, template: GuiObject, amount: number)
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
		local icon = counter.Icon
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
	playLanding(counter)
	letIn(counter, amount)
end

-- A share of the counter's held amount, 0 to 1, pops out of the middle of the screen and flies into
-- the counter. 1 pops all that's left. Without the effects gui or the counter, it goes straight on
local function pop(counter: Counter, share: number)
	if counter.Waiting <= 0 then
		return
	end
	local amount = if share >= 1 then counter.Waiting else counter.Waiting * share
	counter.Waiting -= amount
	counter.Flying += 1

	local effects = PlayerGui:FindFirstChild(EFFECTS_NAME)
	local template = effects and effects:FindFirstChild(counter.Name)
	local icon = counter.Icon
	local counterGui = icon and icon:FindFirstAncestorWhichIsA("ScreenGui")
	if not (effects and effects:IsA("ScreenGui") and template and template:IsA("GuiObject") and counterGui) then
		letIn(counter, amount)
		return
	end

	-- Laid out over the same part of the screen as the counter, so it lands right on the icon, and
	-- drawn over the counter as it gets there
	effects.ScreenInsets = counterGui.ScreenInsets
	effects.DisplayOrder = math.max(effects.DisplayOrder, counterGui.DisplayOrder + 1)

	task.spawn(flyIn, counter, effects, template, amount)
end

-- Kept off the counter until it's popped out and shown flying in
local function hold(counter: Counter, amount: number)
	if amount <= 0 then
		return
	end
	counter.Held += amount
	counter.Waiting += amount
	update(counter)

	counter.Holds += 1
	local holdNumber = counter.Holds
	task.delay(HOLD_TIMEOUT, function()
		if counter.Holds == holdNumber then
			pop(counter, 1)
		end
	end)
end

-- Gems found wait for any collected cash to land first, then pop out a gem at a time
local function popGems(found: number)
	local waited = task.wait(GEM_WAIT)
	while (cashCounter.Waiting > 0 or cashCounter.Flying > 0) and waited < HOLD_TIMEOUT do
		waited += task.wait()
	end
	for left = math.clamp(found, 1, MAX_GEM_POPS), 1, -1 do
		pop(gemCounter, 1 / left)
		task.wait(GEM_POP_GAP)
	end
end

-- Gems going up have been found, so they fly in. The first amount is the player's data loading
local function onGemsChanged()
	local gems = LocalPlayer:GetAttribute("Gems")
	local last = lastGems
	lastGems = if typeof(gems) == "number" then gems else nil
	if typeof(gems) == "number" and last and gems > last then
		hold(gemCounter, gems - last)
		task.spawn(popGems, gems - last)
	else
		update(gemCounter)
	end
end

-- Collected cash is kept off the counter until PopCash shows it flying in, so the counter doesn't
-- jump while the collected items are still on their way to the player
function CurrencyController.HoldCash(amount: number)
	hold(cashCounter, amount)
end

-- A share of the held cash, 0 to 1, pops out of the middle of the screen as a bill that flies into
-- the counter. 1 pops all that's left
function CurrencyController.PopCash(share: number)
	pop(cashCounter, share)
end

-- The gui is made again on every respawn, so its labels are picked up again each time. The Cash
-- and Gem frames are found wherever they are in it, so the frames around them can change
local function bindGui(gui: Instance)
	for _, counter in { cashCounter, gemCounter } do
		local frame = gui:FindFirstChild(counter.Name, true)
		counter.Pulse = if frame and frame:IsA("GuiObject") then makePulse(frame) else nil
		local amount = frame and frame:FindFirstChild("Amount", true)
		counter.Label = if amount and amount:IsA("TextLabel") then amount else nil
		local icon = frame and frame:FindFirstChild(ICON_NAME, true)
		counter.Icon = if icon and icon:IsA("GuiObject") then icon else nil
		if counter.Label then
			counter.Label.Text = counter.Format(counter.Shown.Value)
		end
	end
end

function CurrencyController.Start()
	LocalPlayer:GetAttributeChangedSignal("Money"):Connect(function()
		update(cashCounter)
	end)
	LocalPlayer:GetAttributeChangedSignal("Gems"):Connect(onGemsChanged)
	update(cashCounter)
	onGemsChanged()

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
