porter = {}

-- ** TOP LEVEL **
function porter.get_export_string(player, subfactories)
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


function porter.get_subfactories(player, export_string)
    local export_table = nil

    if not pcall(function()
        export_table = game.json_to_table(game.decode_string(export_string))
    end) then return nil, "decoding_failure" end

    if not pcall(function()
        migrator.migrate_export_table(export_table, player)
    end) then return nil, "migration_failure" end


    local import_factory = Factory.init()

    -- Unpacking and validating could be pcall-ed separately, but that would be too many slow pcalls
    if not pcall(function()
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

    return import_factory
end