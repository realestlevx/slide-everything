local ServerScriptService = game:GetService("ServerScriptService")

-- Require every service first so they can reference each other, then start them
local services = {}
for _, module in ServerScriptService.Services:GetChildren() do
	if module:IsA("ModuleScript") then
		table.insert(services, require(module))
	end
end

for _, service in services do
	if service.Start then
		service.Start()
	end
end
