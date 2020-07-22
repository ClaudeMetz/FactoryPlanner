porter = {}

-- ** TOP LEVEL **
function porter.export(subfactory)
    local packed_subfactory = Subfactory.pack(subfactory)

    return game.encode_string(game.table_to_json(packed_subfactory))
end


function porter.import(subfactory_string)
    local packed_subfactory = game.json_to_table(game.decode_string(subfactory_string))
    local unpacked_subfactory = Subfactory.unpack(packed_subfactory)

    -- Validate the subfactory to both add the valid-attributes to all the objects
    -- and potentially un-simplify the prototypes that came in packed
    Subfactory.validate(unpacked_subfactory)

    return unpacked_subfactory
end


function porter.get_export_string(player, subfactories)
    local export_table = {
        mod_version = get_table(player).mod_version,
        subfactories = {}
    }

    local export_string = game.encode_string(game.table_to_json(export_table))
    return export_string
end