local migration = {}

function migration.player_table(player_table)
    player_table.preferences.default_prototypes.wagons = prototyper.defaults.get_fallback("wagons")
end

return migration
