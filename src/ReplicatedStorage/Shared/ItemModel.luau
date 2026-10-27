local TweenService = game:GetService("TweenService")

-- An item is a part in ReplicatedStorage.Items: a single MeshPart, or a part that collides as a box
-- with more parts inside it (meshes, glowing bits) that only show. The parts inside are welded to
-- the outer one, so moving that moves the whole item, and they can carry effects like particles.
-- Everything that resizes or fades an item goes through here, so the parts inside go along with it
local ItemModel = {}

-- Turned off while the item is hidden, and back on as it shows again
local EFFECT_CLASSES = { "ParticleEmitter", "Trail", "Beam", "Light" }

type Inner = {
	Part: BasePart,
	Size: Vector3, -- At full size
	Offset: CFrame, -- From the outer part, at full size
	Weld: Weld,
}

type Record = {
	Size: Vector3, -- The outer part's, at full size
	Inner: { Inner },
	Attachments: { [Attachment]: Vector3 }, -- Each one's Position at full size
	Effects: { [Instance]: boolean }, -- Each one's own Enabled
	Scale: number,
	-- Extra growth on top of Scale while the player is close enough to use the item, so the two
	-- tween on their own without undoing each other
	Focus: number,
	Transparency: number,
	Tween: Tween?, -- Scaling, if it's running
	ScaleValue: NumberValue?,
	FocusTween: Tween?,
	FocusValue: NumberValue?,
	Arrivals: RBXScriptConnection?, -- Takes on whatever arrives in the item later (see addLate)
}

local records: { [BasePart]: Record } = setmetatable({}, { __mode = "k" }) :: any

local function isEffect(instance: Instance): boolean
	for _, class in EFFECT_CLASSES do
		if instance:IsA(class) then
			return true
		end
	end
	return false
end

local function applyScale(root: BasePart, record: Record)
	local scale = record.Scale * record.Focus
	root.Size = record.Size * scale
	for _, inner in record.Inner do
		inner.Part.Size = inner.Size * scale
		inner.Weld.C0 = inner.Offset.Rotation + inner.Offset.Position * scale
	end
	for attachment, position in record.Attachments do
		attachment.Position = position * scale
	end
end

-- With streaming, the parts inside an item the server made can arrive after the item itself, still
-- at full size, and ones that stream out come back as the server has them. Either way they're taken
-- on at the size and fade the rest of the item is at
local function addLate(root: BasePart, record: Record, descendant: Instance)
	if descendant:IsA("Weld") and descendant.Part0 == root and descendant.Part1 then
		local known = false
		for _, inner in record.Inner do
			known = known or inner.Weld == descendant
		end
		if not known then
			local part = descendant.Part1
			table.insert(record.Inner, { Part = part, Size = part.Size, Offset = descendant.C0, Weld = descendant })
		end
		applyScale(root, record)
	elseif descendant:IsA("Attachment") then
		if not record.Attachments[descendant] then
			record.Attachments[descendant] = descendant.Position
		end
		applyScale(root, record)
	elseif descendant:IsA("BasePart") then
		descendant.LocalTransparencyModifier = root.LocalTransparencyModifier
	elseif isEffect(descendant) then
		if record.Effects[descendant] == nil then
			record.Effects[descendant] = (descendant :: any).Enabled
		end
		(descendant :: any).Enabled = record.Effects[descendant] and record.Transparency < 1
	end
end

-- Taken from the item as it is now, which counts as full size. Copies of items are recorded as
-- they're made; ones made elsewhere, like the server's, are recorded the first time they're used
local function getRecord(root: BasePart): Record
	local record = records[root]
	if record then
		return record
	end
	record = {
		Size = root.Size,
		Inner = {},
		Attachments = {},
		Effects = {},
		Scale = 1,
		Focus = 1,
		Transparency = 0,
		Tween = nil,
		ScaleValue = nil,
		FocusTween = nil,
		FocusValue = nil,
		Arrivals = nil,
	}
	for _, descendant in root:GetDescendants() do
		if descendant:IsA("Weld") and descendant.Part0 == root and descendant.Part1 then
			local part = descendant.Part1
			table.insert(record.Inner, { Part = part, Size = part.Size, Offset = descendant.C0, Weld = descendant })
		elseif descendant:IsA("Attachment") then
			record.Attachments[descendant] = descendant.Position
		elseif isEffect(descendant) then
			record.Effects[descendant] = (descendant :: any).Enabled
		end
	end
	record.Arrivals = root.DescendantAdded:Connect(function(descendant)
		addLate(root, record, descendant)
	end)
	records[root] = record
	return record
end

-- Welds the parts inside a fresh copy of an item to its outer part where they sit, and records it.
-- Call it before moving the copy
function ItemModel.Prepare(root: BasePart)
	-- A record from before would take the new welds on as late arrivals
	local old = records[root]
	if old and old.Arrivals then
		old.Arrivals:Disconnect()
	end
	for _, descendant in root:GetDescendants() do
		if descendant:IsA("WeldConstraint") or descendant:IsA("JointInstance") then
			descendant:Destroy()
		end
	end
	for _, descendant in root:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.Anchored = false
			descendant.Massless = true
			local weld = Instance.new("Weld")
			weld.Part0 = root
			weld.Part1 = descendant
			weld.C0 = root.CFrame:ToObjectSpace(descendant.CFrame)
			weld.Parent = descendant
		end
	end
	records[root] = nil
	getRecord(root)
end

-- The outer part and every part inside it
function ItemModel.GetParts(root: BasePart): { BasePart }
	local parts = { root }
	for _, descendant in root:GetDescendants() do
		if descendant:IsA("BasePart") then
			table.insert(parts, descendant)
		end
	end
	return parts
end

-- Moves the whole item. Once it's in the workspace, setting the outer part's CFrame carries the
-- welded parts along too; before then, only this does
function ItemModel.PivotTo(root: BasePart, cframe: CFrame)
	local record = getRecord(root)
	root.CFrame = cframe
	for _, inner in record.Inner do
		inner.Part.CFrame = cframe * inner.Weld.C0
	end
end

-- No part of the item collides, is touched or is hit by raycasts
function ItemModel.SetVisualOnly(root: BasePart)
	for _, part in ItemModel.GetParts(root) do
		part.CanCollide = false
		part.CanTouch = false
		part.CanQuery = false
	end
end

-- Its share of full size, 1 being full size
function ItemModel.GetScale(root: BasePart): number
	return getRecord(root).Scale
end

-- How tall a part of this size stands when turned this way. Turning it about the Y axis, as
-- floating does, doesn't change it
function ItemModel.GetHeight(rotation: CFrame, size: Vector3): number
	local up = rotation:VectorToObjectSpace(Vector3.yAxis)
	return math.abs(up.X) * size.X + math.abs(up.Y) * size.Y + math.abs(up.Z) * size.Z
end

-- Grows or shrinks the whole item around its outer part's middle. Stops any scaling tween
function ItemModel.SetScale(root: BasePart, scale: number)
	local record = getRecord(root)
	if record.Tween then
		record.Tween:Cancel()
		record.Tween = nil
	end
	record.Scale = scale
	applyScale(root, record)
end

-- Scales the whole item to the given share of full size over the tween, from wherever it is
function ItemModel.TweenScale(root: BasePart, info: TweenInfo, scale: number)
	local record = getRecord(root)
	if record.Tween then
		record.Tween:Cancel()
	end
	local value = record.ScaleValue
	if not value then
		value = Instance.new("NumberValue")
		value.Value = record.Scale
		value.Changed:Connect(function(current: number)
			record.Scale = current
			applyScale(root, record)
		end)
		record.ScaleValue = value
	end
	value.Value = record.Scale
	local tween = TweenService:Create(value, info, { Value = scale })
	record.Tween = tween
	tween:Play()
end

-- Grows the whole item by this much on top of its scale over the tween, from wherever it is, or
-- back to 1. For showing the player they're close enough to use it
function ItemModel.TweenFocus(root: BasePart, info: TweenInfo, focus: number)
	local record = getRecord(root)
	if record.FocusTween then
		record.FocusTween:Cancel()
	end
	local value = record.FocusValue
	if not value then
		value = Instance.new("NumberValue")
		value.Value = record.Focus
		value.Changed:Connect(function(current: number)
			record.Focus = current
			applyScale(root, record)
		end)
		record.FocusValue = value
	end
	value.Value = record.Focus
	local tween = TweenService:Create(value, info, { Value = focus })
	record.FocusTween = tween
	tween:Play()
end

local function setEffects(record: Record, shown: boolean)
	for effect, enabled in record.Effects do
		(effect :: any).Enabled = shown and enabled
	end
end

-- How see-through the whole item looks on this screen only, through LocalTransparencyModifier. Its
-- effects stop while it's fully hidden
function ItemModel.SetLocalTransparency(root: BasePart, transparency: number)
	local record = getRecord(root)
	record.Transparency = transparency
	for _, part in ItemModel.GetParts(root) do
		part.LocalTransparencyModifier = transparency
	end
	setEffects(record, transparency < 1)
end

-- Fades the whole item to that LocalTransparencyModifier. Effects stop as a fade out starts, and
-- start as a fade in does
function ItemModel.TweenLocalTransparency(root: BasePart, info: TweenInfo, transparency: number)
	local record = getRecord(root)
	record.Transparency = transparency
	for _, part in ItemModel.GetParts(root) do
		TweenService:Create(part, info, { LocalTransparencyModifier = transparency }):Play()
	end
	setEffects(record, transparency < 1)
end

return ItemModel
