local HttpService = game:GetService("HttpService")

-- The FavoriteGoalSign model (in Workspace["Favorites/Feedback"]) shows how many players have
-- favorited the game out of GOAL on a fill bar. Game servers can't call roblox.com, so the count comes
-- from the games API through roproxy, which needs Allow HTTP Requests on in Game Settings > Security
local SIGN_NAME = "FavoriteGoalSign"
local GOAL = 1000
local REFRESH_INTERVAL = 300 -- Seconds between fetches
local REQUEST_URL = "https://games.roproxy.com/v1/games/%d/favorites/count"

local goalText: TextLabel
local fill: GuiObject

local FavoriteGoalService = {}

local function render(favorites: number)
	goalText.Text = string.format("%d/%d FAVORITES", favorites, GOAL)
	fill.Size = UDim2.new(math.clamp(favorites / GOAL, 0, 1), 0, fill.Size.Y.Scale, fill.Size.Y.Offset)
end

local function fetchFavorites(): number?
	local requested, response = pcall(HttpService.RequestAsync, HttpService, {
		Url = string.format(REQUEST_URL, game.GameId),
		Method = "GET",
	})
	if not requested or not response.Success then
		return nil
	end

	local decoded, data = pcall(HttpService.JSONDecode, HttpService, response.Body)
	if not decoded or type(data) ~= "table" then
		return nil
	end

	local favorites = tonumber(data.favoritesCount)
	if not favorites or favorites < 0 or favorites ~= favorites or favorites == math.huge then
		return nil
	end
	return math.floor(favorites)
end

function FavoriteGoalService.Start()
	local sign = workspace:FindFirstChild(SIGN_NAME, true)
	if not sign then
		return
	end
	goalText = sign:FindFirstChild("FavoriteGoalText", true) :: TextLabel
	fill = sign:FindFirstChild("Fill", true) :: GuiObject
	render(0)

	if not HttpService.HttpEnabled then
		warn("[FavoriteGoalService] Turn on Allow HTTP Requests in Game Settings > Security")
		return
	end

	task.spawn(function()
		while true do
			local favorites = fetchFavorites()
			if favorites then
				render(favorites)
			else
				warn("[FavoriteGoalService] Couldn't fetch the favorite count")
			end
			task.wait(REFRESH_INTERVAL)
		end
	end)
end

return FavoriteGoalService
