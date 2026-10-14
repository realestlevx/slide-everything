local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Items = require(ReplicatedStorage.Shared.Items)
local Places = require(ReplicatedStorage.Shared.Places)
local Rolling = require(ReplicatedStorage.Shared.Rolling)

local RollResult = ReplicatedStorage.Remotes.RollResult

local rng = Random.new()
local rolling: { [Folder]: boolean } = {}
local rollTokens: { [Folder]: number } = {} -- Bumped to cancel a roll that's still spinning

local RollService = {}

local function clearStand(place: Folder)
	Rolling.ClearStand((place :: any).RollStand_1)
end

local function finishRoll(place: Folder, item: Items.Item)
	local stand = (place :: any).RollStand_1
	-- No highlight here: only the owner's local copy gets one (they're costly and capped per client)
	local display = Rolling.CreateDisplay(item, stand.Roll_Place)
	display.Name = "RolledItem"
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
	-- The owner's client is already spinning; it only needs the result for the last item.
	-- Everyone else just sees the result land
	RollResult:FireClient(player, place, item.Id)

	-- The owner started spinning before this request arrived, so everyone else sees the result
	-- land as the owner's spin ends
	task.delay(Rolling.SPIN_DURATION, function()
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
