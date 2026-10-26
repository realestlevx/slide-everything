local PhysicsService = game:GetService("PhysicsService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PLAYERS_GROUP = "Players"
local ITEMS_GROUP = "Items"
local ITEM_BARRIERS_GROUP = "ItemBarriers"

-- Walls that keep items in but let players walk through: a part named Items_Barrier anywhere in
-- Workspace. They're only made solid on a client through its drop (see DropController)
local ITEM_BARRIER_NAME = "Items_Barrier"

local CollisionService = {}

local function setGroup(part: Instance, group: string)
	if part:IsA("BasePart") then
		part.CollisionGroup = group
	end
end

local function onCharacterAdded(character: Model)
	for _, descendant in character:GetDescendants() do
		setGroup(descendant, PLAYERS_GROUP)
	end
	-- Accessories and tools are added after spawning
	character.DescendantAdded:Connect(function(descendant)
		setGroup(descendant, PLAYERS_GROUP)
	end)
end

local function onPlayerAdded(player: Player)
	if player.Character then
		onCharacterAdded(player.Character)
	end
	player.CharacterAdded:Connect(onCharacterAdded)
end

function CollisionService.Start()
	-- Items still collide with the slide and each other, but players walk through them
	PhysicsService:RegisterCollisionGroup(PLAYERS_GROUP)
	PhysicsService:RegisterCollisionGroup(ITEMS_GROUP)
	PhysicsService:CollisionGroupSetCollidable(PLAYERS_GROUP, ITEMS_GROUP, false)

	-- Item barriers stop items but let players through
	PhysicsService:RegisterCollisionGroup(ITEM_BARRIERS_GROUP)
	PhysicsService:CollisionGroupSetCollidable(PLAYERS_GROUP, ITEM_BARRIERS_GROUP, false)
	for _, descendant in workspace:GetDescendants() do
		if descendant.Name == ITEM_BARRIER_NAME then
			setGroup(descendant, ITEM_BARRIERS_GROUP)
		end
	end

	-- Every clone of an item inherits the group
	for _, descendant in ReplicatedStorage.Items:GetDescendants() do
		setGroup(descendant, ITEMS_GROUP)
	end

	for _, player in Players:GetPlayers() do
		onPlayerAdded(player)
	end
	Players.PlayerAdded:Connect(onPlayerAdded)
end

return CollisionService
