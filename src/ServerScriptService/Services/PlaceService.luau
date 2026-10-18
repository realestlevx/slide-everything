local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local FormatMoney = require(ReplicatedStorage.Shared.FormatMoney)
local Places = require(ReplicatedStorage.Shared.Places)

local SPAWN_OFFSET = Vector3.new(0, 3, 0)

local places: { Folder } = {}
local owners: { [Folder]: Player } = {}
local defaultImages: { [Folder]: string } = {}
local connections: { [Player]: { RBXScriptConnection } } = {}

local PlaceService = {}

function PlaceService.GetPlace(player: Player): Folder?
	for place, owner in owners do
		if owner == player then
			return place
		end
	end
	return nil
end

local function getBillboard(place: Folder): BillboardGui
	return (place :: any).OwnerOfPlace.BillboardGui
end

local function updateMoneyPerSecond(place: Folder, player: Player)
	local label = (getBillboard(place) :: any).MoneyPerSecond
	label.Text = `{FormatMoney(player:GetAttribute("MoneyPerSecond") or 0, 2)}/s`
end

local function loadHeadshot(place: Folder, player: Player)
	local ok, image = pcall(
		Players.GetUserThumbnailAsync,
		Players,
		player.UserId,
		Enum.ThumbnailType.HeadShot,
		Enum.ThumbnailSize.Size150x150
	)
	-- The owner may have left while the thumbnail was loading
	if ok and owners[place] == player then
		(getBillboard(place) :: any).ImageLabel.Image = image
	end
end

local function teleportToPlace(character: Model, place: Folder)
	character:WaitForChild("HumanoidRootPart")
	character:PivotTo((place :: any).Spawn.CFrame + SPAWN_OFFSET)
end

local function getRandomFreePlace(): Folder?
	local free = {}
	for _, place in places do
		if not owners[place] then
			table.insert(free, place)
		end
	end

	if #free == 0 then
		return nil
	end
	return free[math.random(#free)]
end

local function onPlayerAdded(player: Player)
	local place = getRandomFreePlace()
	if not place then
		player:Kick("This server is full. Please join another one.")
		return
	end

	owners[place] = player
	place:SetAttribute("OwnerUserId", player.UserId)
	player:SetAttribute("Place", place.Name)

	local billboard = getBillboard(place);
	(billboard :: any).ImageLabel.Image = defaultImages[place]
	updateMoneyPerSecond(place, player)
	billboard.Enabled = true
	task.spawn(loadHeadshot, place, player)

	connections[player] = {
		player:GetAttributeChangedSignal("MoneyPerSecond"):Connect(function()
			updateMoneyPerSecond(place, player)
		end),
		player.CharacterAdded:Connect(function(character)
			teleportToPlace(character, place)
		end),
	}
	if player.Character then
		task.spawn(teleportToPlace, player.Character, place)
	end
end

local function onPlayerRemoving(player: Player)
	for _, connection in connections[player] or {} do
		connection:Disconnect()
	end
	connections[player] = nil

	local place = PlaceService.GetPlace(player)
	if place then
		owners[place] = nil
		place:SetAttribute("OwnerUserId", nil)
		getBillboard(place).Enabled = false
	end
end

function PlaceService.Start()
	places = Places.GetAll()
	for _, place in places do
		defaultImages[place] = (getBillboard(place) :: any).ImageLabel.Image
		getBillboard(place).Enabled = false
	end

	for _, player in Players:GetPlayers() do
		task.spawn(onPlayerAdded, player)
	end
	Players.PlayerAdded:Connect(onPlayerAdded)
	Players.PlayerRemoving:Connect(onPlayerRemoving)
end

return PlaceService
