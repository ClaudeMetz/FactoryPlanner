data_util = {
}


-- ** MISC **
-- Still can't believe this is not a thing in Lua
-- This has the added feature of turning any number strings into actual numbers
function data_util.split_string(s, separator)
    local result = {}
    for token in string.gmatch(s, "[^" .. separator .. "]+") do
        table.insert(result, (tonumber(token) or token))
    end
    return result
end

-- Adds given export_string-subfactories to the current factory
function data_util.add_subfactories_by_string(player, export_string)
    local context = util.globals.context(player)
    local first_subfactory = Factory.import_by_string(context.factory, export_string)
    util.context.set_subfactory(player, first_subfactory)

    for _, subfactory in pairs(Factory.get_in_order(context.factory, "Subfactory")) do
        if not subfactory.valid then Subfactory.repair(subfactory, player) end
        solver.update(player, subfactory)
    end
end

function data_util.import_tutorial_subfactory()
    local imported_tutorial_factory, error = util.porter.process_export_string(TUTORIAL_EXPORT_STRING)
    return (not error) and Factory.get(imported_tutorial_factory, "Subfactory", 1) or nil
end

-- Checks whether the given recipe's products are used on the given floor
-- The triple loop is crappy, but it's the simplest way to check
function data_util.check_product_compatibiltiy(floor, recipe)
    for _, product in pairs(recipe.proto.products) do
        for _, line in pairs(Floor.get_all(floor, "Line")) do
            for _, ingredient in pairs(Line.get_all(line, "Ingredient")) do
                if ingredient.proto.type == product.type and ingredient.proto.name == product.name then
                    return true
                end
            end
        end
    end
    return false
end


-- Formats the given effects for use in a tooltip
function data_util.format_module_effects(effects, limit_effects)
    local tooltip_lines, effect_applies = {"", "\n"}, false
    local lower_bound, upper_bound = MAGIC_NUMBERS.effects_lower_bound, MAGIC_NUMBERS.effects_upper_bound

    for effect_name, effect_value in pairs(effects) do
        if effect_value ~= 0 then
            effect_applies = true
            local capped_indication = ""  ---@type LocalisedString

            if limit_effects then
                if effect_name == "productivity" and effect_value < 0 then
                    effect_value, capped_indication = 0, {"fp.effect_maxed"}
                elseif effect_value < lower_bound then
                    effect_value, capped_indication = lower_bound, {"fp.effect_maxed"}
                elseif effect_value > upper_bound then
                    effect_value, capped_indication = upper_bound, {"fp.effect_maxed"}
                end
            end

            -- Force display of either a '+' or '-', also round the result
            local display_value = ("%+d"):format(math.floor((effect_value * 100) + 0.5))
            table.insert(tooltip_lines, {"fp.effect_line", {"fp." .. effect_name}, display_value, capped_indication})
        end
    end

    return (effect_applies) and tooltip_lines or ""
end

-- Fills up the localised table in a smart way to avoid the limit of 20 strings per level
-- To make it stateless, it needs its return values passed back as arguments
-- Uses state to avoid needing to call table_size() because that function is slow
---@param strings_to_insert LocalisedString[]
---@param current_table LocalisedString
---@param next_index integer
---@return LocalisedString, integer
function data_util.build_localised_string(strings_to_insert, current_table, next_index)
    current_table = current_table or {""}
    next_index = next_index or 2

    for _, string_to_insert in ipairs(strings_to_insert) do
        if next_index == 20 then  -- go a level deeper if this one is almost full
            local new_table = {""}
            current_table[next_index] = new_table
            current_table = new_table
            next_index = 2
        end
        current_table[next_index] = string_to_insert
        next_index = next_index + 1
    end

    return current_table, next_index
end


function data_util.current_limitations(player)
    local ui_state = util.globals.ui_state(player)
    return {
        archive_open = ui_state.flags.archive_open,
        matrix_active = (ui_state.context.subfactory.matrix_free_items ~= nil),
        recipebook = RECIPEBOOK_ACTIVE
    }
end

function data_util.action_allowed(action_limitations, active_limitations)
    -- If a particular limitation is nil, it indicates that the action is allowed regardless
    -- If it is non-nil, it needs to match the current state of the limitation exactly
    for limitation_name, limitation in pairs(action_limitations) do
        if active_limitations[limitation_name] ~= limitation then return false end
    end
    return true
end

function data_util.generate_tutorial_tooltip(action_name, active_limitations, player)
    active_limitations = active_limitations or data_util.current_limitations(player)

    local tooltip = {"", "\n"}
    for _, action_line in pairs(TUTORIAL_TOOLTIPS[action_name]) do
        if data_util.action_allowed(action_line.limitations, active_limitations) then
            table.insert(tooltip, action_line.string)
        end
    end

    return tooltip
end

function data_util.add_tutorial_tooltips(data, player, action_list)
    local active_limitations = data_util.current_limitations(player)  -- done here so it's 'cached'
    for reference_name, action_name in pairs(action_list) do
        data[reference_name] = data_util.generate_tutorial_tooltip(action_name, active_limitations, nil)
    end
end
