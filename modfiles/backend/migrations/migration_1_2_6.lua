---@diagnostic disable

local migration = {}

function migration.global()
end

function migration.player_table(player_table)
    -- Reset all defaults tables since I don't want to deal with migrating them
    player_table.preferences.default_machines = nil
    player_table.preferences.default_fuels = nil
    player_table.preferences.default_beacons = nil
    player_table.preferences.default_belts = nil
    player_table.preferences.default_wagons = nil

    -- Reset these since the permitted values changed
    player_table.preferences.products_per_row = 6
    player_table.preferences.factory_list_rows = 28

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
