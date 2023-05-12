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
    compact_elements = (function(index) return global.players[index].ui_state.compact_elements end),
    context = (function(index) return global.players[index].ui_state.context end),
    modal_data = (function(index) return global.players[index].ui_state.modal_data end),
    modal_elements = (function(index) return global.players[index].ui_state.modal_data.modal_elements end),
    flags = (function(index) return global.players[index].ui_state.flags end)
}

function data_util.get(name, player)
    return getter_functions[name](player.index)
end


-- ** MISC **
-- Adds given export_string-subfactories to the current factory
function data_util.add_subfactories_by_string(player, export_string)
    local context = data_util.get("context", player)
    local first_subfactory = Factory.import_by_string(context.factory, export_string)
    ui_util.context.set_subfactory(player, first_subfactory)

    for _, subfactory in pairs(Factory.get_in_order(context.factory, "Subfactory")) do
        if not subfactory.valid then Subfactory.repair(subfactory, player) end
        solver.update(player, subfactory)
    end
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

    for effect_name, effect_value in pairs(effects) do
        if effect_value ~= 0 then
            effect_applies = true
            local capped_indication = ""  ---@type LocalisedString

            if limit_effects then
                if effect_name == "productivity" and effect_value < 0 then
                    effect_value, capped_indication = 0, {"fp.effect_maxed"}
                elseif effect_value < EFFECTS_LOWER_BOUND then
                    effect_value, capped_indication = EFFECTS_LOWER_BOUND, {"fp.effect_maxed"}
                elseif effect_value > EFFECTS_UPPER_BOUND then
                    effect_value, capped_indication = EFFECTS_UPPER_BOUND, {"fp.effect_maxed"}
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
    local ui_state = data_util.get("ui_state", player)
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


-- ** NTH_TICK **
local function register_nth_tick_handler(tick)
    script.on_nth_tick(tick, function(nth_tick_data)
        local event_data = global.nth_tick_events[nth_tick_data.nth_tick]
        local handler = NTH_TICK_HANDLERS[event_data.handler_name]
        handler(event_data.metadata)
        data_util.nth_tick.remove(tick)
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
        export_table = game.json_to_table(game.decode_string(export_string) --[[@as string]])
        assert(type(export_table) == "table")
    end) then return nil, "decoding_failure" end

    if not pcall(function()
        migrator.migrate_export_table(export_table)
    end) then return nil, "migration_failure" end

    local import_factory = Factory.init()
    if not pcall(function()  -- Unpacking and validating could be pcall-ed separately, but that's too many slow pcalls
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
    if Factory.count(import_factory, "Subfactory") == 0 then return nil, "decoding_failure" end

    return import_factory, nil
end

-- Creates a nice tooltip laying out which mods were added, removed and updated since the subfactory became invalid
function data_util.porter.format_modset_diff(old_modset)
    if not old_modset then return "" end

    local changes = {added={}, removed={}, updated={}}
    local new_modset = script.active_mods

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

    if next(changes.added) then
        current_table, next_index = data_util.build_localised_string({
            {"fp.subfactory_mod_added"}}, current_table, next_index)
        for name, version in pairs(changes.added) do
            current_table, next_index = data_util.build_localised_string({
                {"fp.subfactory_mod_and_version", name, version}}, current_table, next_index)
        end
    end

    if next(changes.removed) then
        current_table, next_index = data_util.build_localised_string({
            {"fp.subfactory_mod_removed"}}, current_table, next_index)
        for name, version in pairs(changes.removed) do
            current_table, next_index = data_util.build_localised_string({
                {"fp.subfactory_mod_and_version", name, version}}, current_table, next_index)
        end
    end

    if next(changes.updated) then
        current_table, next_index = data_util.build_localised_string({
            {"fp.subfactory_mod_updated"}}, current_table, next_index)
        for name, versions in pairs(changes.updated) do
            current_table, next_index = data_util.build_localised_string({
                {"fp.subfactory_mod_and_versions", name, versions.old, versions.current}}, current_table, next_index)
        end
    end

    -- Return an empty string if no changes were found, ie. the tooltip is still only the header
    return (table_size(tooltip) == 2) and "" or tooltip
end
