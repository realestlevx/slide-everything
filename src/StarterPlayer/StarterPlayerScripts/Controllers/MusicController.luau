local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")

local Volumes = require(ReplicatedStorage.Shared.Volumes)

local LocalPlayer = Players.LocalPlayer

-- Every Sound in SoundService.Music plays, one after another, in a new shuffled order each time
-- round, for as long as the player's in the game. Sounds put in it later join the next time round.
-- Played from the client, so each player hears it from the start, at their own volume
local LOAD_TIMEOUT = 10 -- Seconds a track can take to load before it's skipped
local VOLUME_ATTRIBUTE = "MusicVolume" -- See Volumes

local MusicController = {}

local random = Random.new()

local function getTracks(group: Instance): { Sound }
	local tracks = {}
	for _, descendant in group:GetDescendants() do
		if descendant:IsA("Sound") then
			table.insert(tracks, descendant)
		end
	end
	return tracks
end

local function shuffle(tracks: { Sound })
	for i = #tracks, 2, -1 do
		local j = random:NextInteger(1, i)
		tracks[i], tracks[j] = tracks[j], tracks[i]
	end
end

-- Plays the track from the start and waits until it's over: finished, stopped, taken out of the
-- group, or never loaded
local function play(track: Sound, group: Instance)
	local over = Instance.new("BindableEvent")
	local function finish()
		over:Fire()
	end
	local connections = {
		track.Ended:Connect(finish),
		track.Stopped:Connect(finish),
		track.AncestryChanged:Connect(function()
			if not track:IsDescendantOf(group) then
				finish()
			end
		end),
	}
	task.delay(LOAD_TIMEOUT, function()
		if not track.IsLoaded then
			track:Stop()
			finish()
		end
	end)

	track.Looped = false -- Played through once, then it's the next one's turn
	track.TimePosition = 0
	track:Play()
	over.Event:Wait()
	for _, connection in connections do
		connection:Disconnect()
	end
	over:Destroy()
end

local function playForever(group: Instance)
	local last: Sound? = nil
	while true do
		local tracks = getTracks(group)
		if #tracks == 0 then
			group.DescendantAdded:Wait()
			continue
		end
		shuffle(tracks)
		-- So the last of one round doesn't play again straight away as the first of the next
		if #tracks > 1 and tracks[1] == last then
			tracks[1], tracks[#tracks] = tracks[#tracks], tracks[1]
		end
		for _, track in tracks do
			if track:IsDescendantOf(group) then
				play(track, group)
				last = track
			end
		end
	end
end

function MusicController.Start()
	local group = SoundService:FindFirstChild(Volumes.Music)
	if not group then
		return
	end
	-- Anything left playing in Studio waits its turn instead of playing over the rest
	for _, track in getTracks(group) do
		track:Stop()
	end

	task.spawn(function()
		-- Held until the player's saved volume is in, so music they've turned down doesn't blare first
		if LocalPlayer:GetAttribute(VOLUME_ATTRIBUTE) == nil then
			LocalPlayer:GetAttributeChangedSignal(VOLUME_ATTRIBUTE):Wait()
		end
		playForever(group)
	end)
end

return MusicController
