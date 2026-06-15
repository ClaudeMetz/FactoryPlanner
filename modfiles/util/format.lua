local _format = {}

-- Formats given number to given number of significant digits
---@param number number
---@param precision integer
---@return string formatted_number
function _format.number(number, precision)
    if number >= 10 ^ precision then
        return ("%d"):format(number)  -- %g uses scientific notation here, avoid it
    end
    if number < 10 ^ -precision then
        number = 0
    elseif number < 1 then
        -- log10 gives -(leading zero count), reducing sig figs to keep display width consistent with numbers >= 1
        precision = precision + math.floor(math.log10(number))
    end
    return ("%." .. precision .. "g"):format(number)
end

local prefixes = {"", "kilo", "mega", "giga", "tera", "peta", "exa", "zetta", "yotta"}
local units = {
    ["W"] = {"fp.unit_watt"},
    ["E/m"] = {"", {"fp.unit_emissions"}, "/", {"fp.unit_minute"}}
}

-- Returns string representing the given power
---@param value number
---@param unit string
---@param precision integer
---@return LocalisedString formatted_number
function _format.SI_value(value, unit, precision)
    local sign = (value >= 0) and "" or "-"
    value = math.abs(value)

    local scale_counter = 0
    if value > 0 then
        scale_counter = math.max(0, math.floor(math.log10(value) / 3))  -- /3 because SI prefixes are powers of 1000
        -- Values that round to 1000 would produce scientific notation in %g
        if value / (1000 ^ scale_counter) > 999 then scale_counter = scale_counter + 1 end
    end

    value = value / (1000 ^ scale_counter)
    local prefix = scale_counter == 0 and "" or {"fp.prefix_" .. prefixes[scale_counter + 1]}
    return {"", sign .. util.format.number(value, precision) .. " ", prefix, units[unit]}
end


---@param name string
---@param amount number
---@return LocalisedString tooltip_line
function _format.special_tooltip(name, amount)
    if util.is_special_power_item(name) then
        return util.format.SI_value(amount, "W", MAGIC_NUMBERS.formatting_precision)
    else  -- any of the emission types
        return util.format.SI_value(amount, "E/m", MAGIC_NUMBERS.formatting_precision)
    end
end


-- Factorio truncates (rather than rounds) numbers on item buttons to fit the available space,
-- so a value like 1.09 displays as "1.0" instead of "1.1". To compensate, we pre-ceil the number
-- at the same precision Factorio will use, so that truncation produces the correct rounded result.
--
-- Factorio fits each number into ~4 characters including any SI suffix (k, M, G, T, P, E, ...).
-- This means:
--   no suffix:   1 decimal for values under 100 (e.g. "23.4"), 0 decimals from 100-999 (e.g. "234")
--   with suffix: 1 decimal for values under 10  (e.g. "2.3k"), 0 decimals from 10 up   (e.g. "23k")
-- The no-suffix range gets a wider threshold (100 vs 10) because the absent suffix character
-- leaves room for an extra digit before decimals have to be dropped.
--
-- The 1e-9 epsilon prevents float representation noise (e.g. 2.3 stored as 2.2999...99) from
-- spuriously bumping a clean value up to the next display increment.
function _format.button_number(value)
    if value <= 0 then return value end

    local tier = math.max(0, math.floor(math.log10(value) / 3))
    local scale = 10 ^ (3 * tier)
    local scaled = value / scale
    local threshold = (tier == 0) and 100 or 10
    local factor = (scaled < threshold) and 10 or 1
    return math.ceil(scaled * factor - 1e-9) / factor * scale
end


---@param amount number
---@param ceil_number boolean
---@return number button_number
---@return LocalisedString tooltip_line
function _format.machine_amount(amount, ceil_number)
    if amount == 0 then return nil, {""} end

    local button_number = _format.button_number(amount)
    -- If the formatting returns 0, it is a very small number, so show it as 0.001
    if ceil_number then button_number = math.ceil(button_number) end

    local tooltip_number = util.format.number(amount, MAGIC_NUMBERS.formatting_precision)
    if tooltip_number == "0" then tooltip_number = "≤0.001" end

    local plural_parameter = (tooltip_number == "1") and 1 or 2
    local tooltip_line = {"", "\n", tooltip_number, " ", {"fp.pl_machine", plural_parameter}}

    return button_number, tooltip_line
end


---@param ticks number
---@return LocalisedString formatted_time
function _format.time(ticks)
    if ticks == 0 then return {"fp.none"} end
    local seconds = ticks / 60

    local minutes = math.floor(seconds / 60)
    local minutes_string = (minutes > 0) and {"fp.time_minutes", minutes, minutes} or ""

    seconds = math.floor(seconds - (60 * minutes))
    local seconds_string = (seconds > 0) and {"fp.time_seconds", seconds, seconds} or ""

    return (seconds_string ~= "" and minutes_string ~= "")
        and {"", minutes_string, ", ", seconds_string}
        or {"", minutes_string, seconds_string}  -- one or none will be non-""
  end

return _format
