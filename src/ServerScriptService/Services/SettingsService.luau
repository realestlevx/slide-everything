local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Volumes = require(ReplicatedStorage.Shared.Volumes)

local PlayerDataService = require(script.Parent.PlayerDataService)

local SetVolume = ReplicatedStorage.Remotes.SetVolume

local SettingsService = {}

-- One of the settings menu's sliders, sent once it's let go. Volumes only change what the player
-- hears on their own client, so this just keeps them for when they next join
local function onSetVolume(player: Player, name: any, volume: any)
	if typeof(name) ~= "string" or not Volumes[name] then
		return
	end
	-- NaN fails both comparisons, so it's turned away too
	if typeof(volume) ~= "number" or not (volume >= 0 and volume <= 1) then
		return
	end
	local data = PlayerDataService.Get(player)
	if not data then
		return
	end

	data.Volumes[name] = volume
	player:SetAttribute(`{name}Volume`, volume)
end

function SettingsService.Start()
	SetVolume.OnServerEvent:Connect(onSetVolume)
end

return SettingsService
