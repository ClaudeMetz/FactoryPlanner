---@diagnostic disable

local migration = {}

function migration.player_table(player_table)
    for district in player_table.realm:iterator() do
        for factory in district:iterator() do
            for recipe_name, bonus in pairs(factory.productivity_boni) do
                factory[recipe_name] = math.floor(bonus * 100 + 1e-4)
            end
        end
    end
end

function migration.packed_factory(packed_factory)
    for recipe_name, bonus in pairs(packed_factory.productivity_boni) do
        packed_factory[recipe_name] = math.floor(bonus * 100 + 1e-4)
    end
end

return migration
