-- Contains the 'meat and potatoes' calculation model that struggles with some more complex setups
model = {}

function model.update_subfactory(subfactory_data)
    -- Initialize aggregate with the top level items
    local aggregate = structures.aggregate.init(subfactory_data.player_index, 1)
    for _, product in ipairs(subfactory_data.top_level_products) do
        structures.aggregate.add(aggregate, "Product", product)
    end

    model.update_floor(subfactory_data.top_floor, aggregate)  -- updates aggregate

    -- Fuels are combined with Ingredients for top-level purposes
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
    local desired_products = util.table.deepcopy(aggregate.Product)

    for _, line_data in ipairs(floor_data.lines) do
        local subfloor = line_data.subfloor
        if subfloor ~= nil then
            -- Initialize aggregate with the requirments from the current one
            local subfloor_aggregate = structures.aggregate.init(aggregate.player_index, subfloor.id)
            for _, product in ipairs(line_data.recipe_proto.products) do
                subfloor_aggregate.Product[product.type][product.name] = aggregate.Product[product.type][product.name]
            end
            
            model.update_floor(subfloor, subfloor_aggregate)  -- updates aggregate

            -- Update the parent line of the subfloor with the results from the subfloor aggregate
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
            -- Update aggregate according to the current line, which also adjusts the respective line object
            model.update_line(line_data, aggregate)  -- updates aggregate
        end
    end

    -- Convert all outstanding non-desired products to ingredients
    for _, product in pairs(structures.class.to_array(aggregate.Product)) do
        local desired_product = desired_products[product.type][product.name]
        if desired_product == nil then
            structures.aggregate.add(aggregate, "Ingredient", product)
            structures.aggregate.subtract(aggregate, "Product", product)
        end
    end
end

function model.update_line(line_data, aggregate)    
    -- Determine relevant products
    local relevant_products, byproducts = structures.class.init(), structures.class.init()
    local relevant_product_count = 0

    for _, product in pairs(line_data.recipe_proto.products) do
        if aggregate.Product[product.type][product.name] ~= nil then
            structures.class.add(relevant_products, product)
            relevant_product_count = relevant_product_count + 1
        else
            structures.class.add(byproducts, product)
        end
    end

    relevant_products = structures.class.to_array(relevant_products)
    byproducts = structures.class.to_array(byproducts)
    

    -- Determine production ratio
    local production_ratio = 0

    -- Determines the production ratio that would be needed to fully satisfy the given product
    local function determine_production_ratio(relevant_product)
        local demand = aggregate.Product[relevant_product.type][relevant_product.name]
        local net_amount = data_util.determine_net_product(line_data.recipe_proto, relevant_product.name)
        return ((demand * (line_data.percentage / 100)) / net_amount)
    end

    if relevant_product_count == 1 then
        local relevant_product = relevant_products[1]
        production_ratio = determine_production_ratio(relevant_product)
    elseif relevant_product_count >= 2 then
        -- Determine the highest production ratio needed to fulfill every demand
        for _, relevant_product in pairs(relevant_products) do
            local ratio = determine_production_ratio(relevant_product)
            production_ratio = math.max(production_ratio, ratio)
        end
    end

    -- Set the production ratio of the current aggregate to the one of the first line (relevant for subfloors)
    aggregate.production_ratio = aggregate.production_ratio or production_ratio


    -- Determine byproducts
    local Byproduct = structures.class.init()
    for _, byproduct in pairs(byproducts) do
        byproduct.amount = data_util.determine_item_amount(byproduct) * production_ratio

        structures.class.add(Byproduct, byproduct)
        structures.aggregate.add(aggregate, "Byproduct", byproduct)
    end
    

    -- Determine products
    local Product = structures.class.init()
    for _, product in pairs(relevant_products) do
        product.amount = data_util.determine_item_amount(product) * production_ratio

        local product_demand = aggregate.Product[product.type][product.name]
        if product.amount > product_demand then
            local overflow_amount = product.amount - product_demand
            structures.class.add(Byproduct, product, overflow_amount)
            structures.aggregate.add(aggregate, "Byproduct", product, overflow_amount)
            product.amount = product_demand  -- desired amount
        end

        structures.class.add(Product, product)
        structures.aggregate.subtract(aggregate, "Product", product)
    end


    -- Determine ingredients
    local Ingredient = structures.class.init()
    for _, ingredient in pairs(line_data.recipe_proto.ingredients) do
        local ingredient = util.table.deepcopy(ingredient)
        ingredient.amount = data_util.determine_item_amount(ingredient)
        
        -- Incorporate productivity
        -- Temporary solution for this until catalyst_amount is part of the prototype
        local proddable_amount = ingredient.amount - data_util.determine_catalyst_amount(
          game.get_player(aggregate.player_index), line_data.recipe_proto, "ingredients", ingredient.name)

        local prodded_amount = ingredient.amount
        if proddable_amount > 0 then
            -- Only apply the productivity bonus to the proddable part of the ingredient amount
            prodded_amount = ingredient.amount - proddable_amount + 
              (proddable_amount / (1 + line_data.total_effects.productivity))
        end
        
        ingredient.amount = prodded_amount * production_ratio
        structures.class.add(Ingredient, ingredient)

        -- Reduce the line-byproducts and -ingredients so only the net amounts remain
        local byproduct_amount = Byproduct[ingredient.type][ingredient.name]
        if byproduct_amount ~= nil then
            structures.class.subtract(Byproduct, ingredient, ingredient.amount)
            structures.class.subtract(Ingredient, ingredient, byproduct_amount)
        end

        -- Ingredients should be taken out of byproducts as much as possible for the aggregate
        local available_byproduct = aggregate.Byproduct[ingredient.type][ingredient.name]
        if available_byproduct ~= nil then
            if available_byproduct == ingredient.amount then
                structures.aggregate.subtract(aggregate, "Byproduct", ingredient)

            elseif available_byproduct < ingredient.amount then
                structures.aggregate.subtract(aggregate, "Byproduct", ingredient)
                structures.aggregate.add(aggregate, "Product", ingredient, (ingredient.amount - available_byproduct))

            elseif available_byproduct > ingredient.amount then
                structures.aggregate.subtract(aggregate, "Byproduct", ingredient)
            end
        else
            structures.aggregate.add(aggregate, "Product", ingredient)
        end
    end


    -- Determine machine count
    local machine_count = 0

    -- Determine energy consumption
    local energy_consumption = 0
    aggregate.energy_consumption = aggregate.energy_consumption + energy_consumption


    -- Determine fuel needs
    local Fuel = structures.class.init()


    -- Update the actual line with the calculated results
    calculation.interface.set_line_result {
        player_index = aggregate.player_index,
        floor_id = aggregate.floor_id,
        line_id = line_data.id,
        machine_count = machine_count,
        energy_consumption = energy_consumption,
        production_ratio = production_ratio,
        Product = Product,
        Byproduct = Byproduct,
        Ingredient = Ingredient,
        Fuel = Fuel
    }
end