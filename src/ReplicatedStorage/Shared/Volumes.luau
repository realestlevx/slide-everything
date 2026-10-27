-- The volumes a player sets with the Settings menu's sliders: name -> the SoundGroup in SoundService
-- it turns up and down. Each is saved, and handed to the client on join as the player's <name>Volume
-- attribute, 0 to 1 of how loud the group's set in Studio
local Volumes: { [string]: string } = {
	Sfx = "SFX",
	Music = "Music",
}

return Volumes
