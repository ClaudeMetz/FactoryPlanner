data_util = {
    porter = {}
}

-- ** GETTER **
local getter_functions = {
    table = (function(index) return global.players[index] end),
    settings = (function(index) return global.players[index].settings end),
    preferences = (function(index) return global.players[index].preferences end),
    ui_state = (function(index) return global.players[index].ui_state end),
    main_elements = (function(index) return global.players[index].ui_state.main_elements end),
    context = (function(index) return global.players[index].ui_state.context end),
    modal_data = (function(index) return global.players[index].ui_state.modal_data end),
    modal_elements = (function(index) return global.players[index].ui_state.modal_data.modal_elements end),
    flags = (function(index) return global.players[index].ui_state.flags end)
}

function data_util.get(name, player)  -- 'player' might be a player_index
    local index = (type(player) == "number") and player or player.index
    return getter_functions[name](index)
end


-- ** MISC **
-- Adds given export_string-subfactories to the current factory
function data_util.add_subfactories_by_string(player, export_string, refresh_interface)
    local context = data_util.get("context", player)
    local first_subfactory = Factory.import_by_string(context.factory, player, export_string)

    ui_util.context.set_subfactory(player, first_subfactory)
    calculation.update(player, first_subfactory)
    if refresh_interface then main_dialog.refresh(player, nil) end
end

-- Goes through every subfactory's top level products and updates their defined_by
function data_util.update_all_product_definitions(player)
    local player_table = data_util.get("table", player)

    local defined_by = player_table.settings.belts_or_lanes
    Factory.update_product_definitions(player_table.factory, defined_by)
    Factory.update_product_definitions(player_table.archive, defined_by)

    local subfactory = player_table.ui_state.context.subfactory
    calculation.update(player, subfactory)
    main_dialog.refresh(player, "subfactory")
end

-- Returns the attribute string for the given prototype
function data_util.get_attributes(type, prototype)
    local all_prototypes = global["all_" .. type]

    -- Could figure out structure type itself, but that's slower
    if all_prototypes.structure_type == "simple" then
        return PROTOTYPE_ATTRIBUTES[type][prototype.id]
    else  -- structure_type == "complex"
        local category_id = all_prototypes.map[prototype.category]
        return PROTOTYPE_ATTRIBUTES[type][category_id][prototype.id]
    end
end

-- Executes an alt-action on the given action_type and data
function data_util.execute_alt_action(player, action_type, data)
    local alt_action = data_util.get("settings", player).alt_action

    local remote_action = remote_actions[alt_action]
    if remote_action ~= nil and remote_action[action_type] then
        remote_actions[action_type](player, alt_action, data)
    end
end

-- Removes useless lines and optionally refreshes the interface
function data_util.cleanup_subfactory(player, subfactory)
    calculation.update(player, subfactory)
    Subfactory.remove_useless_lines(subfactory)
    ui_util.context.set_floor(player, Subfactory.get(subfactory, "Floor", 1))
end

-- Formats the given effects for use in a tooltip
function data_util.format_module_effects(effects, multiplier, limit_effects)
    local tooltip_lines, effect_applies = {""}, false

    for effect_name, effect_value in pairs(effects) do
        if type(effect_value) == "table" then effect_value = effect_value.bonus end

        if effect_value ~= 0 then
            effect_applies = true

            local capped_indication = ""
            if limit_effects then
                if effect_name == "productivity" and effect_value < 0 then
                    effect_value, capped_indication = 0, {"fp.effect_maxed"}
                elseif effect_value < -0.8 then
                    effect_value, capped_indication = -0.8, {"fp.effect_maxed"}
                end
            end

            -- Force display of either a '+' or '-', also round the result
            local display_value = ("%+d"):format(math.floor((effect_value * multiplier * 100) + 0.5))
            table.insert(tooltip_lines, {"fp.module_" .. effect_name, display_value, capped_indication})
        end
    end

    if effect_applies then return {"fp.effects_tooltip", tooltip_lines} else return "" end
end


-- ** PORTER **
-- Converts the given subfactories into a factory exchange string
function data_util.porter.get_export_string(player, subfactories)
    local export_table = {
        mod_version = data_util.get("table", player).mod_version,
        subfactories = {}
    }

    for _, subfactory in pairs(subfactories) do
        table.insert(export_table.subfactories, Subfactory.pack(subfactory))
    end

    local export_string = game.encode_string(game.table_to_json(export_table))
    return export_string
end

-- Converts the given factory exchange string into a temporary Factory
function data_util.porter.get_subfactories(player, export_string)
    local export_table = nil

    if not pcall(function()
        export_table = game.json_to_table(game.decode_string(export_string))
        assert(type(export_table) == "table")
    end) then return nil, "decoding_failure" end

    if not pcall(function()
        migrator.migrate_export_table(export_table, player)
    end) then return nil, "migration_failure" end

    local import_factory = Factory.init()
    if not pcall(function()  -- Unpacking and validating could be pcall-ed separately, but that are too many slow pcalls
        for _, packed_subfactory in pairs(export_table.subfactories) do
            local unpacked_subfactory = Subfactory.unpack(packed_subfactory)

            -- The imported subfactories will be temporarily contained in a factory, so they
            -- can be validated and moved to the appropriate 'real' factory easily
            Factory.add(import_factory, unpacked_subfactory)

            -- Validate the subfactory to both add the valid-attributes to all the objects
            -- and potentially un-simplify the prototypes that came in packed
            Subfactory.validate(unpacked_subfactory)
        end
    end) then return nil, "unpacking_failure" end

    -- This is not strictly a decoding failure, but close enough
    if import_factory.Subfactory.count == 0 then return nil, "decoding_failure" end

    return import_factory, nil
end