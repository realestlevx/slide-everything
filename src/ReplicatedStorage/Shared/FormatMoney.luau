local MONEY_SUFFIXES = { "K", "M", "B", "T", "Qa", "Qi" }

-- 950 -> "$950", 1250 -> "$1.2K", 3000000 -> "$3M"
local function formatMoney(amount: number): string
	local sign = if amount < 0 then "-" else ""
	amount = math.floor(math.abs(amount))

	local suffixIndex = math.min(math.floor(math.log10(math.max(amount, 1)) / 3), #MONEY_SUFFIXES)
	if suffixIndex == 0 then
		return `{sign}${amount}`
	end

	-- Truncate to one decimal so 999999 shows as 999.9K rather than rounding up to 1000K
	local tenths = math.floor(amount * 10 / 1000 ^ suffixIndex)
	local short = if tenths % 10 == 0 then `{tenths // 10}` else string.format("%.1f", tenths / 10)

	return `{sign}${short}{MONEY_SUFFIXES[suffixIndex]}`
end

return formatMoney
