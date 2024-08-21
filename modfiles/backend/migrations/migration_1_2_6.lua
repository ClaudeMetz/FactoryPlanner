---@diagnostic disable

local migration = {}

function migration.global()
end

function migration.player_table(player_table)
    player_table.preferences.default_fuels = {}  -- reset due to combined_category change

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
