-- The tutorial a new player goes through: one thing to do at a time, and nothing else in the game
-- works until they've finished it. The player's TutorialStep attribute says which step they're on,
-- so the server and their client go by the same thing. Only the server sets it (see TutorialService)
export type Step = {
	Action: string, -- What the step has the player do, as asked about with Tutorial.Allows
	Text: string, -- Said across the top of the screen, so keep it short (see TutorialController)
}

local COLOR = Color3.fromRGB(255, 221, 64) -- The beam and the glow, and the words picked out in the steps

-- Picks a word out in a step's text, which shows as rich text
local function key(word: string): string
	return `<font color="#{COLOR:ToHex()}">{word}</font>`
end

local Tutorial = {
	ATTRIBUTE = "TutorialStep",
	COLOR = COLOR,
	-- The saved step once it's over. Not just a step past the last, so steps added later aren't given
	-- to players who already finished
	DONE = 0,
	-- What the tutorial's roll lands on. A real roll is more than a new player can pay for about 1 time
	-- in 20, which would leave them stuck on the step to buy it
	FIRST_ROLL = "ToyCar",
	-- Said across the top of the screen when they try anything else (see TopTextController.CheckTutorial)
	LOCKED_TEXT = `<font color="#FF3232">do the tutorial first!</font>`,
	-- Said across the top of the screen as they finish the last step (see TutorialController)
	DONE_TEXT = `<font color="#60FD1D">tutorial complete!</font> <font color="#FFFFFF">repeat and have fun!</font>`,
	Steps = {
		{ Action = "Roll", Text = `{key("Roll")} an item at the lever` },
		{ Action = "BuyItem", Text = `Buy the {key("item")} you rolled` },
		{ Action = "Slots", Text = `Buy your first {key("slot")}` },
		{ Action = "Equip", Text = `Pick your item from the {key("hotbar")}` },
		{ Action = "Place", Text = `Put your item in your {key("slot")}` },
		{ Action = "UpgradeItem", Text = `{key("Upgrade")} your item` },
		{ Action = "Drop", Text = `{key("Drop")} your item down the slide` },
		{ Action = "Collect", Text = `{key("Collect")} your cash` },
		{ Action = "Luck", Text = `Buy more {key("luck")}` },
		{ Action = "SlideSpeed", Text = `Upgrade your {key("sliding speed")}` },
	} :: { Step },
	-- What stays usable through the whole tutorial, as Action = true: the settings menu with its luck
	-- slider, and the backpack. What's inside the backpack still follows the steps. Others that could go
	-- here: LeaveBase (walking off without being sent back), Feedback (the favorite sign and mailbox) and
	-- Passes (game pass purchases)
	AlwaysAllowed = {
		Settings = true,
		SetLuck = true,
		Backpack = true,
	} :: { [string]: boolean },
}

-- The step the player is on and its number. Nil once it's over, and until their data has loaded
function Tutorial.GetStep(player: Player): (Step?, number?)
	local number = player:GetAttribute(Tutorial.ATTRIBUTE)
	local step = if typeof(number) == "number" then Tutorial.Steps[number] else nil
	return step, if step then number else nil
end

-- Whether the player can do this right now. Outside the tutorial, everything. In it, only what their
-- step has them do
function Tutorial.Allows(player: Player, action: string): boolean
	local step = Tutorial.GetStep(player)
	return step == nil or step.Action == action or Tutorial.AlwaysAllowed[action] == true
end

-- Whether their data has loaded and they've no tutorial left to do
function Tutorial.IsDone(player: Player): boolean
	return player:GetAttribute(Tutorial.ATTRIBUTE) == Tutorial.DONE
end

return Tutorial
