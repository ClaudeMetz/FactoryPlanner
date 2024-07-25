local _format = {}

-- Formats given number to given number of significant digits
---@param number number
---@param precision integer
---@return string formatted_number
function _format.number(number, precision)
    -- To avoid scientific notation, chop off the decimals points for big numbers
    if (number / (10 ^ precision)) >= 1 then
        return ("%d"):format(number)
    else
        -- Set very small numbers to 0
        if number < (0.1 ^ precision) then
            number = 0

        -- Decrease significant digits for every zero after the decimal point
        -- This keeps the number of digits after the decimal point constant
        elseif number < 1 then
            local n = number
            while n < 1 do
                precision = precision - 1
                n = n * 10
            end
        end

        -- Show the number in the shortest possible way
        return ("%." .. precision .. "g"):format(number)
    end
end

-- Returns string representing the given power
---@param value number
---@param unit string
---@param precision integer
---@return LocalisedString formatted_number
function _format.SI_value(value, unit, precision)
    local prefixes = {"", "kilo", "mega", "giga", "tera", "peta", "exa", "zetta", "yotta"}
    local units = {
        ["W"] = {"fp.unit_watt"},
        ["J"] = {"fp.unit_joule"},
        ["E/m"] = {"", {"fp.unit_emissions"}, "/", {"fp.unit_minute"}}
    }

    local sign = (value >= 0) and "" or "-"
    value = math.abs(value) or 0

    local scale_counter = 0
    -- Determine unit of the energy consumption, while keeping the result above 1 (ie no 0.1kW, but 100W)
    while scale_counter < #prefixes and value > (1000 ^ (scale_counter + 1)) do
        scale_counter = scale_counter + 1
    end

    -- Round up if energy consumption is close to the next tier
    if (value / (1000 ^ scale_counter)) > 999 then
        scale_counter = scale_counter + 1
    end

    value = value / (1000 ^ scale_counter)
    local prefix = (scale_counter == 0) and "" or {"fp.prefix_" .. prefixes[scale_counter + 1]}
    return {"", sign .. util.format.number(value, precision) .. " ", prefix, units[unit]}
end


---@param count number
---@param active boolean
---@param round_number boolean
---@return string formatted_count
---@return LocalisedString tooltip_line
function _format.machine_count(count, active, round_number)
    -- The formatting is used to 'round down' when the decimal is very small
    local formatted_count = util.format.number(count, 3)
    local tooltip_count = formatted_count

    -- If the formatting returns 0, it is a very small number, so show it as 0.001
    if formatted_count == "0" and active then
        tooltip_count = "≤0.001"
        formatted_count = "0.01"  -- shows up as 0.0 on the button
    end

    if round_number then formatted_count = tostring(math.ceil(formatted_count --[[@as number]])) end

    local plural_parameter = (tooltip_count == "1") and 1 or 2
    local tooltip_line = {"", tooltip_count, " ", {"fp.pl_machine", plural_parameter}}

    return formatted_count, tooltip_line
end


---@param ticks number
---@return LocalisedString formatted_time
function _format.format_time(ticks)
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
