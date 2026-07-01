---@diagnostic disable

local migration = {}

function migration.player_table(player_table)
    local preferences = player_table.preferences
    preferences.default_prototypes = {
        machines = preferences.default_machines,
        fuels = preferences.default_fuels,
        beacons = preferences.default_beacons,
        belts = preferences.default_belts,
        pumps = preferences.default_pumps,
        silos = preferences.default_silos,
        wagons = preferences.default_wagons
    }
    -- Obsolete preference entries will be removed by init reload
end

return migration
