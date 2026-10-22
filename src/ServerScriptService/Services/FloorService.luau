local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local Floors = require(ReplicatedStorage.Shared.Floors)
local Places = require(ReplicatedStorage.Shared.Places)

local PlaceService = require(script.Parent.PlaceService)
local PlayerDataService = require(script.Parent.PlayerDataService)

-- Place -> floor number -> where the floor's model is built, from the place's Floor<N>_Position part
local spots: { [Folder]: { [number]: CFrame } } = {}

local FloorService = {}

-- The floor's model in ServerStorage. Warns and gives nil without one
local function getTemplate(number: number): Model?
	local name = Floors.GetName(number)
	local template = ServerStorage:FindFirstChild(name)
	if not (template and template:IsA("Model")) then
		warn(`ServerStorage needs a {name} model for floor {number} to be built`)
		return nil
	end
	return template
end

local function getOwnerData(place: Folder): PlayerDataService.Data?
	local ownerId = place:GetAttribute("OwnerUserId")
	local owner = if typeof(ownerId) == "number" then Players:GetPlayerByUserId(ownerId) else nil
	return if owner then PlayerDataService.Get(owner) else nil
end

-- What the place's sign sells the floor for, or nil if it can't be built there
function FloorService.GetPrice(place: Folder, number: number): number?
	local spot = spots[place] and spots[place][number]
	return if spot then Floors.GetPrice(number) else nil
end

local function build(place: Folder, number: number)
	local name = Floors.GetName(number)
	local spot = spots[place] and spots[place][number]
	local template = getTemplate(number)
	if place:FindFirstChild(name) or not (spot and template) then
		return
	end
	local floor = template:Clone()
	floor.Name = name
	-- Streamed in all at once, so the buyer's client has every part to build it up from as it arrives
	floor.ModelStreamingMode = Enum.ModelStreamingMode.Atomic
	floor:PivotTo(spot)
	floor.Parent = place
end

-- The place shows the floors its owner has, and only floor 1 while nobody owns it. The Floors
-- attribute tells clients how many there are, as the floors' parts are streamed
local function refreshPlace(place: Folder)
	local data = getOwnerData(place)
	local count = if data then data.Floors else 1
	place:SetAttribute("Floors", count)
	for number in spots[place] do
		local built = place:FindFirstChild(Floors.GetName(number))
		if number <= count then
			build(place, number)
		elseif built then
			built:Destroy()
		end
	end
end

-- The owner bought the next floor: it's built at once, for everyone
function FloorService.Add(place: Folder, data: PlayerDataService.Data)
	data.Floors += 1
	refreshPlace(place)
end

function FloorService.Start()
	for _, place in Places.GetAll() do
		-- Each Floor<N>_Position part only marks where its floor goes, and would get in the way of
		-- the items dropping from the floors above, so it goes once its spot is known
		spots[place] = {}
		for number in Floors.Prices do
			local marker = place:FindFirstChild(Floors.GetMarkerName(number), true)
			if marker and marker:IsA("BasePart") then
				spots[place][number] = marker.CFrame
				marker:Destroy()
			else
				warn(`{place:GetFullName()} needs a {Floors.GetMarkerName(number)} part for floor {number} to be built`)
			end
		end

		refreshPlace(place)
		place:GetAttributeChangedSignal("OwnerUserId"):Connect(function()
			refreshPlace(place)
		end)
	end

	PlayerDataService.Loaded:Connect(function(player)
		local place = PlaceService.GetPlace(player)
		if place then
			refreshPlace(place)
		end
	end)
end

return FloorService
