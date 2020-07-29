data_util = {
    porter = {}
}

-- ** MISC **
-- Adds given export_string-subfactories to the current factory
function data_util.add_subfactories_by_string(player, export_string, refresh_interface)
    local context = get_context(player)
    local first_subfactory = Factory.import_by_string(context.factory, player, export_string)

    ui_util.context.set_subfactory(player, first_subfactory)
    calculation.update(player, first_subfactory, refresh_interface)
end

-- Goes through every subfactory's top level products and updates their defined_by
function data_util.update_all_product_definitions(player)
    local player_table = get_table(player)
    local defined_by = player_table.settings.belts_or_lanes
    Factory.update_product_definitions(player_table.factory, defined_by)
    Factory.update_product_definitions(player_table.archive, defined_by)
    main_dialog.refresh(player, true)
end


-- ** PORTER **
-- Converts the given subfactories into a factory exchange string
function data_util.porter.get_export_string(player, subfactories)
    local export_table = {
        mod_version = get_table(player).mod_version,
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

    -- This is not strictly an decoding failure, but close enough
    if import_factory.Subfactory.count == 0 then return nil, "decoding_failure" end

    return import_factory, nil
end