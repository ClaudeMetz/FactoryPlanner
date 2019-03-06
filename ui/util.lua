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


-- Returns the sprite string of the given recipe
function ui_util.get_recipe_sprite(player, recipe)
    local sprite = "recipe/" .. recipe.name
    if recipe.name == "fp-space-science-pack" then
        sprite = "recipe/space-science-pack"
    elseif string.find(recipe.name, "^impostor%-[a-z0-9-]+$") then
        sprite = recipe.item_type .. "/" .. recipe.name:gsub("impostor%-", "")

        -- If the mining recipe has no sprite, the sprite of the first product is used instead
        if not player.gui.is_valid_sprite_path(sprite) then
            local product = recipe.products[1]
            sprite = product.type .. "/" .. product.name
        end
    end
    return sprite
end


-- Formats given number to given number of significant digits
function ui_util.format_number(number, precision)
    return ("%." .. precision .. "g"):format(number)
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

-- Deep-copies given table (seen does not need to be specified when calling it)
-- (From: https://stackoverflow.com/questions/640642/how-do-you-copy-a-lua-table-by-value)
function ui_util.copy_table(obj, seen)
    if type(obj) ~= 'table' then return obj end
    if seen and seen[obj] then return seen[obj] end
    local s = seen or {}
    local res = setmetatable({}, getmetatable(obj))
    s[obj] = res
    for k, v in pairs(obj) do res[ui_util.copy_table(k, s)] = ui_util.copy_table(v, s) end
    return res
end