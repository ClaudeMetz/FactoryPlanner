---@diagnostic disable

local Recipe = require("backend.data.Recipe")

local migration = {}

function migration.player_table(player_table)
    for district in player_table.realm:iterator() do
        for factory in district:iterator() do
            factory.matrix_solver_active = (factory.matrix_free_items ~= nil)
            factory.matrix_free_items = factory.matrix_free_items or {}


            local function iterate_floor(floor)
                for line in floor:iterator() do
                    if line.class == "Floor" then
                        iterate_floor(line)
                    else
                        -- Use simplified proto to avoid fluid temperature data build
                        local recipe_proto = {name = line.recipe_proto.name, category = nil,
                            data_type = "recipes", simplified = true}
                        line.recipe = Recipe.init(recipe_proto, line.production_type, line)
                        line.recipe.priority_product = line.priority_product
                        line.recipe.temperatures = line.temperatures or {}

                        line.recipe_proto = nil
                        line.production_type = nil
                        line.priority_product = nil
                        line.temperatures = nil

                        line.temperature_data = nil
                    end
                end
            end
            iterate_floor(factory.top_floor)
        end
    end
end

function migration.packed_factory(packed_factory)
    packed_factory.matrix_solver_active = (packed_factory.matrix_free_items ~= nil)
    packed_factory.matrix_free_items = packed_factory.matrix_free_items or {}


    local function iterate_floor(packed_floor)
        for _, packed_line in pairs(packed_floor.lines) do
            if packed_line.class == "Floor" then
                iterate_floor(packed_line)
            else
                packed_line.recipe = {
                    class = "Recipe",
                    proto = packed_line.recipe_proto,
                    production_type = packed_line.production_type,
                    priority_product = packed_line.priority_product,
                    temperatures = packed_line.temperatures or {}
                }
            end
        end
    end
    iterate_floor(packed_factory.top_floor)
end

return migration
