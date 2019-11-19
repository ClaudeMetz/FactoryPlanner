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
        pollution = aggregate.pollution,
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
            
            local floor_products = structures.class.to_array(subfloor_aggregate.Product)
            model.update_floor(subfloor, subfloor_aggregate)  -- updates aggregate

            -- Convert the internal product-format into positive products for the line and main aggregate
            for _, product in pairs(floor_products) do
                local aggregate_product_amount = subfloor_aggregate.Product[product.type][product.name] or 0
                subfloor_aggregate.Product[product.type][product.name] = product.amount - aggregate_product_amount
            end
            

            -- Update the main aggregate with the results
            aggregate.energy_consumption = subfloor_aggregate.energy_consumption
            aggregate.pollution = subfloor_aggregate.pollution

            local function update_main_aggregate(class_name, destination_class_name)
                for _, item in ipairs(structures.class.to_array(subfloor_aggregate[class_name])) do
                    local amount = (class_name == "Product") and -item.amount or item.amount
                    structures.aggregate.add(aggregate, destination_class_name, item, amount)
                end
            end
            
            update_main_aggregate("Byproduct", "Byproduct")
            update_main_aggregate("Product", "Product")
            update_main_aggregate("Ingredient", "Product")
            update_main_aggregate("Fuel", "Product")


            -- Update the parent line of the subfloor with the results from the subfloor aggregate
            calculation.interface.set_line_result {
                player_index = aggregate.player_index,
                floor_id = aggregate.floor_id,
                line_id = line_data.id,
                machine_count = subfloor_aggregate.machine_count,
                energy_consumption = subfloor_aggregate.energy_consumption,
                pollution = subfloor_aggregate.pollution,
                production_ratio = subfloor_aggregate.production_ratio,
                uncapped_production_ratio = subfloor_aggregate.uncapped_production_ratio,
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
        if desired_products[product.type][product.name] == nil then
            structures.aggregate.add(aggregate, "Ingredient", product)
            structures.aggregate.subtract(aggregate, "Product", product)
        end
    end
end

function model.update_line(line_data, aggregate)
    -- Determine relevant products
    local relevant_products, byproducts = {}, {}
    for _, product in pairs(line_data.recipe_proto.products) do
        if aggregate.Product[product.type][product.name] ~= nil then
            table.insert(relevant_products, product)
        else
            table.insert(byproducts, product)
        end
    end

    -- Determine production ratio
    local production_ratio, uncapped_production_ratio = 0, 0

    -- Determines the production ratio that would be needed to fully satisfy the given product
    local function determine_production_ratio(relevant_product)
        local demand = aggregate.Product[relevant_product.type][relevant_product.name]
        return ((demand * (line_data.percentage / 100)) / relevant_product.net_amount)
    end

    local relevant_product_count = table_size(relevant_products)
    if relevant_product_count == 1 then
        local relevant_product = relevant_products[1]
        production_ratio = determine_production_ratio(relevant_product)

    elseif relevant_product_count >= 2 then
        local priority_proto = line_data.priority_product_proto

        for _, relevant_product in pairs(relevant_products) do
            -- Use the priority product to determine the production ratio, if it's set
            if priority_proto ~= nil then
                if relevant_product.type == priority_proto.type and relevant_product.name == priority_proto.name then
                    production_ratio = determine_production_ratio(relevant_product)
                    break
                end

            -- Otherwise, determine the highest production ratio needed to fulfill every demand
            else
                local ratio = determine_production_ratio(relevant_product)
                production_ratio = math.max(production_ratio, ratio)
            end
        end
    end
    uncapped_production_ratio = production_ratio  -- retain the uncapped ratio for line_data

    -- Limit the machine_count by reducing the production_ratio, if necessary
    if line_data.machine_limit.limit ~= nil then
        local capped_production_ratio = calculation.util.determine_production_ratio(line_data.machine_proto, 
          line_data.recipe_proto, line_data.total_effects, line_data.machine_limit.limit, line_data.timescale)
        production_ratio = line_data.machine_limit.hard_limit and 
          capped_production_ratio or math.min(production_ratio, capped_production_ratio)
    end

    -- Set the production ratio of the current aggregate to the one of the first line (relevant for subfloors)
    aggregate.production_ratio = aggregate.production_ratio or production_ratio
    aggregate.uncapped_production_ratio = aggregate.uncapped_production_ratio or uncapped_production_ratio


    -- Determines the amount of the given item, considering productivity
    local function determine_amount_with_productivity(item)
        if (item.proddable_amount > 0) and (line_data.total_effects.productivity > 0) then
            return (calculation.util.determine_prodded_amount(item, line_data.total_effects) * production_ratio)
        else
            return (item.amount * production_ratio)
        end
    end
    
    -- Determine byproducts
    local Byproduct = structures.class.init()
    for _, byproduct in pairs(byproducts) do
        local byproduct_amount = determine_amount_with_productivity(byproduct)

        structures.class.add(Byproduct, byproduct, byproduct_amount)
        structures.aggregate.add(aggregate, "Byproduct", byproduct, byproduct_amount)
    end

    -- Determine products
    local Product = structures.class.init()
    for _, product in pairs(relevant_products) do
        local product_amount = determine_amount_with_productivity(product)

        -- Don't include net negative relevant products as products
        if product.net_amount <= 0 then
            structures.class.add(Byproduct, product, product_amount)
            structures.aggregate.add(aggregate, "Byproduct", product, product_amount)

        else
            local product_demand = aggregate.Product[product.type][product.name] or 0
            if product_amount > product_demand then
                local overflow_amount = product_amount - product_demand
                structures.class.add(Byproduct, product, overflow_amount)
                structures.aggregate.add(aggregate, "Byproduct", product, overflow_amount)
                product_amount = product_demand  -- desired amount
            end
            
            structures.class.add(Product, product, product_amount)
            structures.aggregate.subtract(aggregate, "Product", product, product_amount)
        end
    end

    -- Determine ingredients
    local Ingredient = structures.class.init()
    for _, ingredient in pairs(line_data.recipe_proto.ingredients) do
        local ingredient_amount = determine_amount_with_productivity(ingredient)
        
        structures.class.add(Ingredient, ingredient, ingredient_amount)

        -- Reduce the line-byproducts and -ingredients so only the net amounts remain
        local byproduct_amount = Byproduct[ingredient.type][ingredient.name]
        if byproduct_amount ~= nil then
            structures.class.subtract(Byproduct, ingredient, ingredient_amount)
            structures.class.subtract(Ingredient, ingredient, byproduct_amount)
        end

        -- Ingredients should be taken out of byproducts as much as possible for the aggregate
        local available_byproduct = aggregate.Byproduct[ingredient.type][ingredient.name]
        if available_byproduct ~= nil then
            if available_byproduct == ingredient_amount then
                structures.aggregate.subtract(aggregate, "Byproduct", ingredient, ingredient_amount)

            elseif available_byproduct < ingredient_amount then
                structures.aggregate.subtract(aggregate, "Byproduct", ingredient, ingredient_amount)
                structures.aggregate.add(aggregate, "Product", ingredient, (ingredient_amount - available_byproduct))

            elseif available_byproduct > ingredient_amount then
                structures.aggregate.subtract(aggregate, "Byproduct", ingredient, ingredient_amount)
            end
        else
            structures.aggregate.add(aggregate, "Product", ingredient, ingredient_amount)
        end
    end


    -- Determine machine count
    local machine_count = calculation.util.determine_machine_count(line_data.machine_proto, line_data.recipe_proto,
      line_data.total_effects, production_ratio, line_data.timescale)
    -- Set the machine count of the current aggregate to the one of the first line (relevant for subfloors)
    aggregate.machine_count = aggregate.machine_count or machine_count


    -- Determine energy consumption (including potential fuel needs) and pollution
    local energy_consumption = calculation.util.determine_energy_consumption(line_data.machine_proto,
      machine_count, line_data.total_effects)
    local pollution = calculation.util.determine_pollution(line_data.machine_proto, line_data.recipe_proto,
      line_data.fuel_proto, line_data.total_effects, energy_consumption)
    
    local Fuel = structures.class.init()
    local burner = line_data.machine_proto.burner

    if burner ~= nil and burner.categories["chemical"] then  -- only handles chemical fuels for now
        local fuel_proto = line_data.fuel_proto  -- Lines without subfloors will always have a fuel_proto attached
        local fuel_amount = calculation.util.determine_fuel_amount(energy_consumption, burner, 
          fuel_proto.fuel_value, line_data.timescale)
        
        local fuel = {type=fuel_proto.type, name=fuel_proto.name, amount=fuel_amount}
        structures.class.add(Fuel, fuel)
        structures.aggregate.add(aggregate, "Fuel", fuel)

        -- This is to work around the fuel not being detected as a possible product
        structures.aggregate.add(aggregate, "Product", fuel)
        structures.aggregate.subtract(aggregate, "Ingredient", fuel)

        energy_consumption = 0  -- set electrical consumption to 0 when fuel is used
    end

    -- Include beacon energy consumption
    energy_consumption = energy_consumption + line_data.beacon_consumption

    aggregate.energy_consumption = aggregate.energy_consumption + energy_consumption
    aggregate.pollution = aggregate.pollution + pollution

    
    -- Update the actual line with the calculated results
    calculation.interface.set_line_result {
        player_index = aggregate.player_index,
        floor_id = aggregate.floor_id,
        line_id = line_data.id,
        machine_count = machine_count,
        energy_consumption = energy_consumption,
        pollution = pollution,
        production_ratio = production_ratio,
        uncapped_production_ratio = uncapped_production_ratio,
        Product = Product,
        Byproduct = Byproduct,
        Ingredient = Ingredient,
        Fuel = Fuel
    }
end