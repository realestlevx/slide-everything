-- Colors for a gradient that scrolls through the rainbow, like the drop's multiplier and the Limited
-- gradient. They're made again every frame, each a little further round, instead of sliding the
-- gradient's Offset, which leaves a flat color where it's slid off the end
local COLORS = 12 -- Keypoints across it; a ColorSequence takes up to 20
local PERIOD = 2 -- Seconds for a color to scroll all the way across

-- The rainbow at time (from os.clock), so everything showing it scrolls in step
local function getRainbow(time: number): ColorSequence
	local keypoints = {}
	for index = 0, COLORS - 1 do
		local at = index / (COLORS - 1)
		-- Both ends are the same color, so it scrolls round without a seam
		local hue = (at - time / PERIOD) % 1
		table.insert(keypoints, ColorSequenceKeypoint.new(at, Color3.fromHSV(hue, 1, 1)))
	end
	return ColorSequence.new(keypoints)
end

return getRainbow
