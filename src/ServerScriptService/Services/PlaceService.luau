local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local FormatMoney = require(ReplicatedStorage.Shared.FormatMoney)
local Places = require(ReplicatedStorage.Shared.Places)

local SPAWN_OFFSET = Vector3.new(0, 3, 0)
-- A base's ground is everything in its place's Bottoms folder. Its box goes on the place as the
-- BaseMin and BaseMax attributes, and where its players spawn as SpawnCFrame, so clients can tell
-- when their player has left the base and send them back even while those parts are streamed out
local BASE_FOLDER_NAME = "Bottoms"
-- The market's spawn goes on Workspace.Market as SpawnCFrame too, for the top bar's Market button
local MARKET_NAME = "Market"
local MARKET_SPAWN_NAME = "MarketSpawn"

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

local function getSpawn(place: Folder): CFrame
	return (place :: any).Spawn.CFrame + SPAWN_OFFSET
end

local function teleportToPlace(character: Model, place: Folder)
	character:WaitForChild("HumanoidRootPart")
	character:PivotTo(getSpawn(place))
end

local function measureBase(place: Folder)
	place:SetAttribute("SpawnCFrame", getSpawn(place))

	local folder = place:FindFirstChild(BASE_FOLDER_NAME)
	local parts = if folder then folder:GetDescendants() else {}
	local low, high = Vector3.one * math.huge, -Vector3.one * math.huge
	for _, part in parts do
		if part:IsA("BasePart") then
			-- Half the box around the part, however it's turned
			local cframe, half = part.CFrame, part.Size / 2
			local extent = (cframe.RightVector * half.X):Abs()
				+ (cframe.UpVector * half.Y):Abs()
				+ (cframe.LookVector * half.Z):Abs()
			low = low:Min(cframe.Position - extent)
			high = high:Max(cframe.Position + extent)
		end
	end
	if low.X > high.X then
		warn(`{place.Name} has no parts in a {BASE_FOLDER_NAME} folder, so its owner can't tell when they've left it`)
		return
	end
	place:SetAttribute("BaseMin", low)
	place:SetAttribute("BaseMax", high)
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
		measureBase(place)
	end
	local market = workspace:FindFirstChild(MARKET_NAME)
	local marketSpawn = market and market:FindFirstChild(MARKET_SPAWN_NAME)
	if marketSpawn and marketSpawn:IsA("BasePart") then
		market:SetAttribute("SpawnCFrame", marketSpawn.CFrame + SPAWN_OFFSET)
	end

	for _, player in Players:GetPlayers() do
		task.spawn(onPlayerAdded, player)
	end
	Players.PlayerAdded:Connect(onPlayerAdded)
	Players.PlayerRemoving:Connect(onPlayerRemoving)
end

return PlaceService
