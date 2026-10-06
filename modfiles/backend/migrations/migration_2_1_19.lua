---@diagnostic disable

local migration = {}

function migration.player_table(player_table)
    local function migrate_floor(floor)
        floor.simplex_item_weights = floor.simplex_item_weights or {}

        for line in floor:iterator() do
            if line.class == "Floor" then
                migrate_floor(line)
            else
                line.recipe.production_type = nil
            end
        end
    end

    for district in player_table.realm:iterator() do
        for factory in district:iterator() do
            migrate_floor(factory.top_floor)
        end
    end
end

function migration.packed_factory(packed_factory)
    local function migrate_floor(floor)
        floor.simplex_item_weights = floor.simplex_item_weights or {}

        for _, line in pairs(floor.lines) do
            if line.class == "Floor" then
                migrate_floor(line)
            else
                line.recipe.production_type = nil
            end
        end
    end

    migrate_floor(packed_factory.top_floor)
end

return migration
