if not game:IsLoaded() then
	game.Loaded:Wait()
end

-- Require every controller first so they can reference each other, then start them
local controllers = {}
for _, module in script.Parent:WaitForChild("Controllers"):GetChildren() do
	if module:IsA("ModuleScript") then
		table.insert(controllers, require(module))
	end
end

for _, controller in controllers do
	if controller.Start then
		controller.Start()
	end
end
