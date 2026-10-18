local Players = game:GetService("Players")

-- Roblox sometimes leaves a scaled TextLabel on a BillboardGui blank: the label keeps its text but
-- measures 0x0 and draws nothing, until its text changes again. It comes and goes, so instead of
-- avoiding a cause, labels showing that symptom get their text set again
local CHECK_INTERVAL = 0.5 -- Seconds between checks

local billboards: { [BillboardGui]: boolean } = {}

local BillboardTextController = {}

local function getWorldPosition(billboard: BillboardGui): Vector3?
	local target = billboard.Adornee or billboard.Parent
	if target and target:IsA("BasePart") then
		return target.Position
	elseif target and target:IsA("Attachment") then
		return target.WorldPosition
	elseif target and target:IsA("Model") then
		return target:GetPivot().Position
	end
	return nil
end

-- Out of range or disabled, every label measures 0x0, so only billboards being drawn can be checked
local function isDrawn(billboard: BillboardGui): boolean
	local position = getWorldPosition(billboard)
	return billboard.Enabled
		and position ~= nil
		and (workspace.CurrentCamera.CFrame.Position - position).Magnitude <= billboard.MaxDistance
end

-- Hidden itself or inside a hidden frame (like the slot buttons other players don't get)
local function isHidden(gui: GuiObject, billboard: BillboardGui): boolean
	local current: Instance? = gui
	while current and current ~= billboard do
		if current:IsA("GuiObject") and not current.Visible then
			return true
		end
		current = current.Parent
	end
	return false
end

local function isBlank(instance: Instance, billboard: BillboardGui): boolean
	if not (instance:IsA("TextLabel") or instance:IsA("TextButton")) then
		return false
	end
	local label = instance :: TextLabel
	return label.Text ~= "" and label.AbsoluteSize.X > 0 and label.TextBounds.X == 0 and not isHidden(label, billboard)
end

local function track(instance: Instance)
	if instance:IsA("BillboardGui") then
		billboards[instance] = true
	end
end

local function repairBlankLabels()
	local blank: { [TextLabel]: string } = {}
	for billboard in billboards do
		if not billboard:IsDescendantOf(game) then
			billboards[billboard] = nil
		elseif isDrawn(billboard) then
			for _, descendant in billboard:GetDescendants() do
				if isBlank(descendant, billboard) then
					blank[descendant :: TextLabel] = (descendant :: TextLabel).Text
				end
			end
		end
	end
	if next(blank) == nil then
		return
	end

	-- Emptied for a frame, so the text really changes twice. They draw nothing anyway, so it doesn't show
	for label in blank do
		label.Text = ""
	end
	task.wait()
	for label, text in blank do
		-- Unless something else set new text in the meantime
		if label.Text == "" then
			label.Text = text
		end
	end
end

function BillboardTextController.Start()
	-- Slot billboards are copied into PlayerGui; the rest stay in the world
	for _, root in { workspace, Players.LocalPlayer:WaitForChild("PlayerGui") } do
		for _, descendant in root:GetDescendants() do
			track(descendant)
		end
		root.DescendantAdded:Connect(track)
	end

	task.spawn(function()
		while true do
			task.wait(CHECK_INTERVAL)
			repairBlankLabels()
		end
	end)
end

return BillboardTextController
