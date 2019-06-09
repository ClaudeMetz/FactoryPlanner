ui_util = {
    fnei = {}
}

-- Readjusts the size of the main dialog according to the user setting of number of items per row
function ui_util.recalculate_main_dialog_dimensions(player)
    local player_table = global.players[player.index]
    local width = 880 + ((player_table.settings.items_per_row - 4) * 175)
    player_table.main_dialog_dimensions.width = width
end


-- Sets the font color of the given label / button-label
function ui_util.set_label_color(ui_element, color)
    if color == "red" then
        ui_element.style.font_color = {r = 1, g = 0.2, b = 0.2}
    elseif color == "dark_red" then
        ui_element.style.font_color = {r = 0.8, g = 0, b = 0}
    elseif color == "yellow" then
        ui_element.style.font_color = {r = 0.8, g = 0.8, b = 0}
    elseif color == "white" or color == "default_label" then
        ui_element.style.font_color = {r = 1, g = 1, b = 1}
    elseif color == "black" or color == "default_button" then
        ui_element.style.font_color = {r = 0, g = 0, b = 0}
    end
end


-- Returns the type of the given prototype (item/fluid)
function ui_util.get_prototype_type(proto)
    local index = global.all_items.index
    if index[proto.name] ~= "dupe" then
        return index[proto.name]
    else
        -- Fall-back to the slow (and awful) method if the name describes both an item and fluid
        if pcall(function () local a = proto.type end) then return "item"
        else return "fluid" end
    end
end

-- Returns the sprite string of the given item
function ui_util.get_item_sprite(player, item)
    return (ui_util.get_prototype_type(item) .. "/" .. item.name)
end

-- Returns the sprite string of the given recipe
function ui_util.get_recipe_sprite(player, recipe)
    local sprite = "recipe/" .. recipe.name

    -- Handle custom recipes separately
    if recipe.name == "fp-space-science-pack" then
        sprite = "item/space-science-pack"
    elseif string.find(recipe.name, "^impostor%-[a-z0-9-_]+$") then
        -- If the impostor recipe has exactly one product, use it's sprite
        if #recipe.products == 1 then
            sprite = recipe.products[1].type .. "/" .. recipe.products[1].name
        else  -- Otherwise (0 or 2+ products), use the first ingredient's sprite
            sprite = recipe.ingredients[1].type .. "/" .. recipe.ingredients[1].name
        end
    end

    return sprite
end


-- Formats given number to given number of significant digits
function ui_util.format_number(number, precision)
    return ("%." .. precision .. "g"):format(number)
end

-- Returns string representing the given timescale (Currently only needs to handle 1 second/minute/hour)
function ui_util.format_timescale(timescale, raw)
    local ts = nil
    if timescale == 1 then
        ts = "s"
    elseif timescale == 60 then
        ts = "m"
    elseif timescale == 3600 then
        ts = "h"
    end
    if raw then return ts
    else return ("1" .. ts) end
end

-- Returns string representing the given power 
function ui_util.format_energy_consumption(energy_consumption, precision)
    local scale = {"W", "kW", "MW", "GW", "TW", "PW", "EW", "ZW", "YW"}
    local scale_counter = 1

    while scale_counter < #scale and energy_consumption >= 1000 do
        energy_consumption = energy_consumption / 1000
        scale_counter = scale_counter + 1
    end

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

-- **** FNEI ****
-- This indicates the version of the FNEI remote interface this is compatible with
local fnei_version = 1

-- Opens FNEI to show the given item
-- Mirrors FNEI's distinction between left and right clicks
function ui_util.fnei.show_item(item, click)
    if remote.interfaces["fnei"] ~= nil and remote.call("fnei", "version") == fnei_version then
        local action_type = (click == "left") and "craft" or "usage"
        remote.call("fnei", "show_item", action_type, item.type, item.name)
    end
end

-- Opens FNEI to show the given recipe
-- Attempts to show an appropriate item context, if possible
function ui_util.fnei.show_recipe(recipe, line_products)
    if remote.interfaces["fnei"] ~= nil and remote.call("fnei", "version") == fnei_version then
        if recipe.prototype.main_product then
            local product = recipe.prototype.main_product
            remote.call("fnei", "show_recipe", recipe.name, product.type, product.name)
        elseif #line_products == 1 then
            local product = line_products[1]
            remote.call("fnei", "show_recipe", recipe.name, product.type, product.name)
        else
            -- The functionality to show a recipe without context does not exist (yet) in FNEI,
            -- so for now, this case will not show any recipe
            -- remote.call("fnei", "show_recipe", recipe.name)
        end
    end
end