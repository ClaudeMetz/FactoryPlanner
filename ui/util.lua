ui_util = {}

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


-- Determines unit of given timescale, currently limited to presets
function ui_util.determine_unit(timescale)
    if timescale == 1 then
        return "s"
    elseif timescale == 60 then
        return "m"
    elseif timescale == 3600 then
        return "h"
    end
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