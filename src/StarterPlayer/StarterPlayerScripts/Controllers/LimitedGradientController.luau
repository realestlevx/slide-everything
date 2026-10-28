local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Rainbow = require(ReplicatedStorage.Shared.Rainbow)

local LocalPlayer = Players.LocalPlayer

-- Every UIGradient named Limited, in Workspace or the player's guis, scrolls through the rainbow in
-- step with the drop's multiplier. So far only the favorite goal sign's free item has them
local GRADIENT_NAME = "Limited"

local gradients: { [UIGradient]: boolean } = {}

local LimitedGradientController = {}

local function track(instance: Instance)
	if instance.Name == GRADIENT_NAME and instance:IsA("UIGradient") then
		gradients[instance] = true
	end
end

local function scroll()
	if next(gradients) == nil then
		return
	end
	local colors = Rainbow(os.clock())
	for gradient in gradients do
		gradient.Color = colors
	end
end

function LimitedGradientController.Start()
	-- The places' signs stream in and out, and guis are made again on every respawn
	for _, root in { workspace, LocalPlayer:WaitForChild("PlayerGui") } do
		for _, descendant in root:GetDescendants() do
			track(descendant)
		end
		root.DescendantAdded:Connect(track)
		root.DescendantRemoving:Connect(function(instance)
			gradients[instance :: any] = nil
		end)
	end

	RunService.RenderStepped:Connect(scroll)
end

return LimitedGradientController
