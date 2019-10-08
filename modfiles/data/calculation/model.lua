-- Contains the 'meat and potatoes' calculation model that struggles with some more complex setups
model = {}

function model.update_subfactory(subfactory_data)
    -- Initialize aggregate with the top level items
    local aggregate = structures.aggregate.init(subfactory_data.player_index, 1)
    for _, product in ipairs(subfactory_data.top_level_products) do
        structures.aggregate.add(aggregate, "Product", product)
    end

    model.update_floor(subfactory_data.top_floor, aggregate)  -- updates aggregate

    structures.aggregate.combine_classes(aggregate, "Ingredient", "Fuel")
    calculation.interface.set_subfactory_result {
        player_index = subfactory_data.player_index,
        energy_consumption = aggregate.energy_consumption,
        Product = aggregate.Product,
        Byproduct = aggregate.Byproduct,
        Ingredient = aggregate.Ingredient
    }
end

function model.update_floor(floor_data, aggregate)
    for _, line_data in ipairs(floor_data.lines) do
        local subfloor = line_data.subfloor
        if subfloor ~= nil then
            -- Initialize aggregate with the requirments from the current one
            local subfloor_aggregate = structures.aggregate.init(aggregate.player_index, subfloor.id)
            for _, product in ipairs(line_data.recipe_proto.products) do
                subfloor_aggregate.Product[product.type][product.name] = aggregate.Product[product.type][product.name]
            end
            
            model.update_floor(subfloor, subfloor_aggregate)

            calculation.interface.set_line_result {
                player_index = aggregate.player_index,
                floor_id = aggregate.floor_id,
                line_id = line_data.id,
                energy_consumption = subfloor_aggregate.energy_consumption,
                production_ratio = subfloor_aggregate.production_ratio,
                Product = subfloor_aggregate.Product,
                Byproduct = subfloor_aggregate.Byproduct,
                Ingredient = subfloor_aggregate.Ingredient,
                Fuel = subfloor_aggregate.Fuel
            }
        else
            -- Update aggregate according to the current line, which also adjusts the respective real line object
            model.update_line(line_data, aggregate)
        end
    end
end

function model.update_line(line_data, aggregate)
    -- TODO all

    -- aggregate.production_ratio = aggregate.production_ratio or production_ratio

    --calculation.interface.set_line_result(result)
end