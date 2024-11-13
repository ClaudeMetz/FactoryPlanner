---@diagnostic disable

local DistrictItemSet = require("backend.data.DistrictItemSet")

local migration = {}

function migration.player_table(player_table)
    for district in player_table.realm:iterator() do
        district.products = nil
        district.byproducts = nil
        district.ingredients = nil

        district.product_set = DistrictItemSet.init("product")
        district.ingredient_set = DistrictItemSet.init("ingredient")

        for factory in district:iterator() do
            local function iterate_floor(floor)
                for line in floor:iterator() do
                    line.products = {}
                    line.byproducts = {}
                    line.ingredients = {}

                    if line.class == "Floor" then
                        iterate_floor(line)
                    else
                        line.machine.total_effects = nil
                    end
                end
            end
            iterate_floor(factory.top_floor)
        end
    end
end

return migration
