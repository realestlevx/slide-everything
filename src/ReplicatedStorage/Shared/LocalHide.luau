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

-- Each hidden thing -> what the properties that hide it were before. Weak, so things that stream out
-- aren't kept
local hidden: { [Instance]: { [string]: any } } = setmetatable({}, { __mode = "k" }) :: any

function LocalHide.Set(instance: Instance, hide: boolean)
	for _, rule in HIDING do
		if not instance:IsA(rule.Class) then
			continue
		end
		local saved = hidden[instance]
		if hide and not saved then
			saved = {}
			for property, value in rule.Properties do
				saved[property] = (instance :: any)[property];
				(instance :: any)[property] = value
			end
			hidden[instance] = saved
		elseif not hide and saved then
			for property, value in saved do
				(instance :: any)[property] = value
			end
			hidden[instance] = nil
		end
		return
	end
end

return LocalHide
