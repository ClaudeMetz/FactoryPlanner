---@diagnostic disable

local migration = {}

function migration.global()
end

function migration.player_table(player_table)
    -- Reset all defaults tables since I don't want to deal with migrating them
    player_table.preferences.default_machines = {}
    player_table.preferences.default_fuels = {}
    player_table.preferences.default_belts = {}
    player_table.preferences.default_wagons = {}
    player_table.preferences.default_beacons = {}

    for district in player_table.realm:iterator() do
        for factory in district:iterator() do
            factory.productivity_boni = {}
        end
    end
end

function migration.packed_factory(packed_factory)
    packed_factory.productivity_boni = {}
end

return migration
