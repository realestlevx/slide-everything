local InventoryService = require(script.Parent.InventoryService)

local BinService = {}

local function onBinTriggered(player: Player)
	local owned = InventoryService.GetEquipped(player)
	if owned then
		InventoryService.Delete(player, { owned.Uid })
	end
end

-- Any prompt inside a Model named Bin deletes the item the player holds, for good. It only ever
-- touches the triggering player's own item, so a bin needs no owner check
function BinService.Start()
	for _, descendant in workspace:GetDescendants() do
		if not descendant:IsA("ProximityPrompt") then
			continue
		end
		local bin = descendant:FindFirstAncestor("Bin")
		if bin and bin:IsA("Model") then
			descendant.Triggered:Connect(onBinTriggered)
		end
	end
end

return BinService
