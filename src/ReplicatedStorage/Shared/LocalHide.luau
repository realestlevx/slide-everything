-- Hides things on this client alone, and puts them back as they were: parts go see-through and stop
-- being stood on or hit, and the guis, lights and effects on them go off. Hiding something twice is
-- fine; it's put back as it was before the first time
local LocalHide = {}

-- The properties that hide each kind of thing, and what they're set to. The first class that matches wins
local HIDING: { { Class: string, Properties: { [string]: any } } } = {
	{ Class = "BasePart", Properties = { Transparency = 1, CanCollide = false, CanQuery = false } },
	{ Class = "Decal", Properties = { Transparency = 1 } }, -- Textures too
	{ Class = "LayerCollector", Properties = { Enabled = false } },
	{ Class = "Light", Properties = { Enabled = false } },
	{ Class = "ParticleEmitter", Properties = { Enabled = false } },
	{ Class = "Beam", Properties = { Enabled = false } },
	{ Class = "Trail", Properties = { Enabled = false } },
}

type Hidden = {
	Saved: { [string]: any }, -- What the properties that hide it were before
	Removed: RBXScriptConnection, -- Forgets it once it's out of the game, like when it streams out
}

-- Each hidden thing. Not weak: an instance no script holds on to can drop out of a weak table while
-- it's still in the game, and then it could never be put back
local hidden: { [Instance]: Hidden } = {}

function LocalHide.Set(instance: Instance, hide: boolean)
	for _, rule in HIDING do
		if not instance:IsA(rule.Class) then
			continue
		end
		local entry = hidden[instance]
		if hide and not entry then
			local saved = {}
			for property, value in rule.Properties do
				saved[property] = (instance :: any)[property];
				(instance :: any)[property] = value
			end
			local added: Hidden
			added = {
				Saved = saved,
				Removed = instance.AncestryChanged:Connect(function()
					if not instance:IsDescendantOf(game) then
						added.Removed:Disconnect()
						hidden[instance] = nil
					end
				end),
			}
			hidden[instance] = added
		elseif not hide and entry then
			for property, value in entry.Saved do
				(instance :: any)[property] = value
			end
			entry.Removed:Disconnect()
			hidden[instance] = nil
		end
		return
	end
end

return LocalHide
