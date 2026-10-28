local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Volumes = require(ReplicatedStorage.Shared.Volumes)

local PlayerDataService = require(script.Parent.PlayerDataService)

local SetFastMode = ReplicatedStorage.Remotes.SetFastMode
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

-- The settings menu's Fast Mode button. Like the volumes, it only changes this player's own screen
local function onSetFastMode(player: Player, on: any)
	local data = PlayerDataService.Get(player)
	if typeof(on) ~= "boolean" or not data then
		return
	end
	data.FastMode = on
	player:SetAttribute("FastMode", on)
end

function SettingsService.Start()
	SetVolume.OnServerEvent:Connect(onSetVolume)
	SetFastMode.OnServerEvent:Connect(onSetFastMode)
end

return SettingsService
