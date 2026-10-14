local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Items = require(ReplicatedStorage.Shared.Items)
local Places = require(ReplicatedStorage.Shared.Places)
local Rolling = require(ReplicatedStorage.Shared.Rolling)

local RollStarted = ReplicatedStorage.Remotes.RollStarted

-- Lands just after the owner's spin ends, so the real item replaces their preview seamlessly
local FINISH_DELAY = Rolling.SPIN_DURATION + 0.25

local rng = Random.new()
local rolling: { [Folder]: boolean } = {}
local rollTokens: { [Folder]: number } = {} -- Bumped to cancel a roll that's still spinning

local RollService = {}

local function clearStand(place: Folder)
	local stand = (place :: any).RollStand_1
	local rolledItem = stand:FindFirstChild("RolledItem")
	if rolledItem then
		rolledItem:Destroy()
	end
	stand.Roll_Place.Stuff_StatsDisplay.Enabled = false
end

local function finishRoll(place: Folder, item: Items.Item)
	local stand = (place :: any).RollStand_1
	local display = Rolling.CreateDisplay(item, stand.Roll_Place)
	display.Name = "RolledItem"
	Rolling.AddHighlight(display, Rolling.GetOutcomeHighlight(item))
	display.Parent = stand
	Rolling.ShowStats(stand.Roll_Place.Stuff_StatsDisplay, item)
end

local function onRollTriggered(place: Folder, player: Player)
	-- Prompts are hidden for non-owners on the client, but never trust that
	if place:GetAttribute("OwnerUserId") ~= player.UserId or rolling[place] then
		return
	end

	local token = (rollTokens[place] or 0) + 1
	rollTokens[place] = token
	rolling[place] = true

	local item = Rolling.Pick(rng)
	clearStand(place)
	-- Only the owner watches the spin; everyone else just sees the result land
	RollStarted:FireClient(player, place, item.Id)

	task.delay(FINISH_DELAY, function()
		if rollTokens[place] ~= token then
			return
		end
		rolling[place] = nil
		finishRoll(place, item)
	end)
end

local function onOwnerChanged(place: Folder)
	rollTokens[place] = (rollTokens[place] or 0) + 1
	rolling[place] = nil
	clearStand(place)
end

function RollService.Start()
	for _, place in Places.GetAll() do
		clearStand(place)

		local prompt = (place :: any).RollTools_Model.Proximity_Holder.RollProximity
		prompt.Triggered:Connect(function(player)
			onRollTriggered(place, player)
		end)
		place:GetAttributeChangedSignal("OwnerUserId"):Connect(function()
			onOwnerChanged(place)
		end)
	end
end

return RollService
