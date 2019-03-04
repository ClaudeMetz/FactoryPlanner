ui_util = {}

-- Readjusts the size of the main dialog according to the user setting of number of items per row
function ui_util.recalculate_main_dialog_dimensions(player)
    local column_count = settings.get_player_settings(player)["fp_subfactory_items_per_row"].value
    local width = 880 + ((column_count - 4) * 180)
    global.players[player.index].main_dialog_dimensions.width = width
end


-- Sets the font color of the given label / button-label
function ui_util.set_label_color(ui_element, color)
    if color == "red" then
        ui_element.style.font_color = {r = 1, g = 0.2, b = 0.2}
    elseif color == "white" or color == "default" then
        ui_element.style.font_color = {r = 1, g = 1, b = 1}
    end
end

-- Sets all 4 padding attributes at once
function ui_util.set_padding(ui_element, padding)
    ui_element.style.top_padding = padding
    ui_element.style.right_padding = padding
    ui_element.style.bottom_padding = padding
    ui_element.style.left_padding = padding
end


-- Returns string representing the given timescale
-- (Currently only needs to handle 1 second/minute/hour)
function ui_util.format_timescale(timescale)
    if timescale == 1 then
        return "1s"
    elseif timescale == 60 then
        return "1m"
    elseif timescale == 3600 then
        return "1h"
    end
end

-- Formats given number to given number of significant digits
function ui_util.format_number(number, precision)
    return ("%." .. precision .. "g"):format(number)
end

-- Returns string representing the given power 
function ui_util.format_energy_consumption(energy_consumption, precision)
    local scale_counter = 1
    while energy_consumption > 1000 do
        energy_consumption = energy_consumption / 1000
        scale_counter = scale_counter + 1
    end
    local scale = {"W", "kW", "MW", "GW", "TW", "PW", "EW", "ZW", "YW"}
    return (ui_util.format_number(energy_consumption, precision) .. " " .. scale[scale_counter])
end


-- Sorts a table by string-key using an iterator
function ui_util.pairsByKeys(t, f)
    local a = {}
    for n in pairs(t) do table.insert(a, n) end
    table.sort(a, f)
    local i = 0      -- iterator variable
    local iter = function ()   -- iterator function
        i = i + 1
        if a[i] == nil then return nil
        else return a[i], t[a[i]]
        end
    end
    return iter
end

-- Splits given string
function ui_util.split(s, separator)
    local r = {}
    for token in string.gmatch(s, "[^" .. separator .. "]+") do
        if tonumber(token) ~= nil then
            token = tonumber(token)
        end
        table.insert(r, token) 
    end
    return r
end