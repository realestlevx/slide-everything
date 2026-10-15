local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- UIGradients designed in Studio, looked up by name
local gradients = ReplicatedStorage:WaitForChild("Gradients")

local GRADIENT_NAME = "AppliedGradient"
local COPIED_PROPERTIES = { "Color", "Transparency", "Rotation", "Offset", "Enabled" }

-- Gives target (a GuiObject or UIStroke) a copy of the gradient with that name; nil or an unknown name
-- removes it. A UIGradient multiplies the color underneath, so the target should be white.
-- An existing copy is updated rather than replaced, so the server and the owner's client both showing
-- the same stats don't stack up gradients on it. Returns whether a gradient was applied
local function applyGradient(target: Instance, name: string?): boolean
	local template = if name then gradients:FindFirstChild(name) else nil
	local gradient = target:FindFirstChild(GRADIENT_NAME) :: UIGradient?

	if not (template and template:IsA("UIGradient")) then
		if gradient then
			gradient:Destroy()
		end
		return false
	end

	if gradient then
		for _, property in COPIED_PROPERTIES do
			(gradient :: any)[property] = (template :: any)[property]
		end
	else
		gradient = template:Clone()
		gradient.Name = GRADIENT_NAME
		gradient.Parent = target
	end
	return true
end

return applyGradient
