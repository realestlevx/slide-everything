local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PlayerDataService = require(script.Parent.PlayerDataService)

local SetSfxVolume = ReplicatedStorage.Remotes.SetSfxVolume

local SettingsService = {}

-- The settings menu's sound effects slider, sent once it's let go. The volume only changes what the
-- player hears on their own client, so this just keeps it for when they next join
local function onSetSfxVolume(player: Player, volume: any)
	-- NaN fails both comparisons, so it's turned away too
	if typeof(volume) ~= "number" or not (volume >= 0 and volume <= 1) then
		return
	end
	local data = PlayerDataService.Get(player)
	if not data then
		return
	end

	data.SfxVolume = volume
	player:SetAttribute("SfxVolume", volume)
end

function SettingsService.Start()
	SetSfxVolume.OnServerEvent:Connect(onSetSfxVolume)
end

return SettingsService
