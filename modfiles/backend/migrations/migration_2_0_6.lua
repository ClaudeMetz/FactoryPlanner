---@diagnostic disable

local migration = {}

function migration.player_table(player_table)
    for district in player_table.realm:iterator() do
        district.products = nil
        district.byproducts = nil
        district.ingredients = nil

        for factory in district:iterator() do
            local function iterate_floor(floor)
                for line in floor:iterator() do
                    line.products = nil
                    line.byproducts = nil
                    line.ingredients = nil

                    if line.class == "Floor" then
                        iterate_floor(line)
                    end
                end
            end
            iterate_floor(factory.top_floor)
        end
    end
end

return migration
