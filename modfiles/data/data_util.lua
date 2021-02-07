data_util = {
    nth_tick = {},
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
    local first_subfactory = Factory.import_by_string(context.factory, export_string)

    ui_util.context.set_subfactory(player, first_subfactory)
    calculation.update(player, first_subfactory)
    if refresh_interface then main_dialog.refresh(player, "all") end
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

-- Fills up the localised table in a smart way to avoid the limit of 20 strings per level
-- To make it state-less, it needs its return values passed back as arguments
-- Uses state to avoid needing to call table_size() because that function is slow
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


-- ** NTH_TICK **
local function register_nth_tick_handler(tick)
    script.on_nth_tick(tick, function(nth_tick_data)
        local event_data = global.nth_tick_events[nth_tick_data.nth_tick]
        local handler = NTH_TICK_HANDLERS[event_data.handler_name]
        handler(event_data.metadata)
    end)
end

function data_util.nth_tick.add(desired_tick, handler_name, metadata)
    local actual_tick = desired_tick
    -- Search until the next free nth_tick is found
    while (global.nth_tick_events[actual_tick] ~= nil) do
        actual_tick = actual_tick + 1
    end

    global.nth_tick_events[actual_tick] = {handler_name=handler_name, metadata=metadata}
    register_nth_tick_handler(actual_tick)

    return actual_tick  -- let caller know which tick they actually got
end

function data_util.nth_tick.remove(tick)
    script.on_nth_tick(tick, nil)
    global.nth_tick_events[tick] = nil
end

function data_util.nth_tick.register_all()
    if not global.nth_tick_events then return end
    for tick, _ in pairs(global.nth_tick_events) do
        register_nth_tick_handler(tick)
    end
end


-- ** PORTER **
-- Converts the given subfactories into a factory exchange string
function data_util.porter.get_export_string(subfactories)
    local export_table = {
        -- This can use the global mod_version since it's only called for migrated, valid subfactories
        mod_version = global.mod_version,
        export_modset = global.installed_mods,
        subfactories = {}
    }

    for _, subfactory in pairs(subfactories) do
        table.insert(export_table.subfactories, Subfactory.pack(subfactory))
    end

    local export_string = game.encode_string(game.table_to_json(export_table))
    return export_string
end

-- Converts the given factory exchange string into a temporary Factory
function data_util.porter.get_subfactories(export_string)
    local export_table = nil

    if not pcall(function()
        export_table = game.json_to_table(game.decode_string(export_string))
        assert(type(export_table) == "table")
    end) then return nil, "decoding_failure" end

    if not pcall(function()
        migrator.migrate_export_table(export_table)
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

        -- Include the modset at export time to be displayed to the user if a subfactory is invalid
        import_factory.export_modset = export_table.export_modset

    end) then return nil, "unpacking_failure" end

    -- This is not strictly a decoding failure, but close enough
    if import_factory.Subfactory.count == 0 then return nil, "decoding_failure" end

    return import_factory, nil
end

-- Creates a nice tooltip laying out which mods were added, removed and updated since the subfactory became invalid
function data_util.porter.format_modset_diff(old_modset)
    if not old_modset then return "" end

    local changes = {added={}, removed={}, updated={}}
    local new_modset = game.active_mods

    -- Determine changes by running through both sets of mods once each
    for name, current_version in pairs(new_modset) do
        local old_version = old_modset[name]
        if not old_version then
            changes.added[name] = current_version
        elseif old_version ~= current_version then
            changes.updated[name] = {old=old_version, current=current_version}
        end
    end

    for name, old_version in pairs(old_modset) do
        if not new_modset[name] then
            changes.removed[name] = old_version
        end
    end

    -- Compose tooltip from all three types of changes
    local tooltip = {"", {"fp.subfactory_modset_changes"}}
    local current_table, next_index = tooltip, 3

    if table_size(changes.added) > 0 then
        current_table, next_index = data_util.build_localised_string({
          {"fp.subfactory_mod_added"}}, current_table, next_index)
        for name, version in pairs(changes.added) do
            current_table, next_index = data_util.build_localised_string({
              {"fp.subfactory_mod_and_version", name, version}}, current_table, next_index)
        end
    end

    if table_size(changes.removed) > 0 then
        current_table, next_index = data_util.build_localised_string({
          {"fp.subfactory_mod_removed"}}, current_table, next_index)
        for name, version in pairs(changes.removed) do
            current_table, next_index = data_util.build_localised_string({
              {"fp.subfactory_mod_and_version", name, version}}, current_table, next_index)
        end
    end

    if table_size(changes.updated) > 0 then
        current_table, next_index = data_util.build_localised_string({
          {"fp.subfactory_mod_updated"}}, current_table, next_index)
        for name, versions in pairs(changes.updated) do
            current_table, next_index = data_util.build_localised_string({
              {"fp.subfactory_mod_and_versions", name, versions.old, versions.current}}, current_table, next_index)
        end
    end

    return tooltip
end
