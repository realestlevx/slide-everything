local MONEY_SUFFIXES = { "K", "M", "B", "T", "Qa", "Qi" }

-- 950 -> "$950", 1250 -> "$1.2K", 3000000 -> "$3M". Earnings pass decimals so small upgrades still
-- show: (1.025, 2) -> "$1.02", (1025, 2) -> "$1.02K"
local function formatMoney(amount: number, decimals: number?): string
	local sign = if amount < 0 then "-" else ""
	amount = math.abs(amount)

	local suffixIndex = math.min(math.floor(math.log10(math.max(amount, 1)) / 3), #MONEY_SUFFIXES)
	-- Whole dollars, or one decimal once there's a suffix, unless asked for more
	local places = decimals or (if suffixIndex == 0 then 0 else 1)
	local factor = 10 ^ places
	-- Truncated, so 999999 shows as 999.9K rather than rounding up to 1000K. The tiny nudge keeps
	-- float error (1.025 * 100 = 102.4999...) from dropping a digit
	local short = math.floor(amount / 1000 ^ suffixIndex * factor + 1e-6) / factor

	local text = string.format(`%.{places}f`, short)
	if places > 0 then
		-- No trailing zeros: "$3M", not "$3.0M"
		text = (text:gsub("0+$", ""):gsub("%.$", ""))
	end

	return `{sign}${text}{MONEY_SUFFIXES[suffixIndex] or ""}`
end

return formatMoney
