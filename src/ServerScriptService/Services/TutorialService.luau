local AnalyticsService = game:GetService("AnalyticsService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Tutorial = require(ReplicatedStorage.Shared.Tutorial)

local PlayerDataService = require(script.Parent.PlayerDataService)

local FUNNEL_JOINED = "Joined" -- The onboarding funnel's first step, ahead of the tutorial's own

local TutorialService = {}

local function setStep(player: Player, data: PlayerDataService.Data, number: number)
	data.TutorialStep = number
	player:SetAttribute(Tutorial.ATTRIBUTE, number)
end

-- The onboarding funnel on the Creator Dashboard, showing where new players give up on the tutorial.
-- Roblox only counts a player's first time on each step, so coming back or doing one again won't skew
-- it, and only live servers send anything, not Studio. It's only analytics, so failing mustn't stop
-- the tutorial
local function logFunnelStep(player: Player, number: number, name: string)
	local ok, message = pcall(AnalyticsService.LogOnboardingFunnelStepEvent, AnalyticsService, player, number, name)
	if not ok then
		warn(`Couldn't log onboarding funnel step {name} for {player.Name}: {message}`)
	end
end

-- They've done this step of the tutorial. It's one further along the funnel, after Joined
local function logStepDone(player: Player, number: number)
	logFunnelStep(player, number + 1, Tutorial.Steps[number].Action)
end

-- The player did this: on to the next step, if it's what the one they're on had them do
function TutorialService.Complete(player: Player, action: string)
	local data = PlayerDataService.Get(player)
	local step, number = Tutorial.GetStep(player)
	if data and step and number and step.Action == action then
		setStep(player, data, if number < #Tutorial.Steps then number + 1 else Tutorial.DONE)
		logStepDone(player, number)
	end
end

function TutorialService.Start()
	-- Everything else they've done is saved, so someone coming back carries on from their step. Two
	-- steps need a look, as they could leave partway through what comes before them
	PlayerDataService.Loaded:Connect(function(player)
		local data = PlayerDataService.Get(player)
		local step, number = Tutorial.GetStep(player)
		if not (data and step and number) then
			return
		end
		if number == 1 then
			logFunnelStep(player, 1, FUNNEL_JOINED)
		end
		if step.Action == "Place" then
			-- What's in their hands isn't saved, so they start by taking it out again
			setStep(player, data, number - 1)
		elseif step.Action == "Roll" and next(data.LastRolls) then
			-- They left mid-spin. What it landed on was saved, and goes back on the stand to buy
			setStep(player, data, number + 1)
			logStepDone(player, number)
		end
	end)
end

return TutorialService
