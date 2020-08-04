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
    local desired_products = structures.class.copy(aggregate.Product)

    for _, line_data in ipairs(floor_data.lines) do
        local subfloor = line_data.subfloor
        if subfloor ~= nil then
            -- Convert proto product table to class for easier and faster access
            local proto_products = structures.class.init()
            for _, product in pairs(line_data.recipe_proto.products) do
                proto_products[product.type][product.name] = true
            end

            -- Determine the products that are relevant for this subfloor
            local subfloor_aggregate = structures.aggregate.init(aggregate.player_index, subfloor.id)
            for _, product in ipairs(structures.class.to_array(aggregate.Product)) do
                local type, name = product.type, product.name
                if proto_products[type][name] ~= nil then
                    subfloor_aggregate.Product[type][name] = aggregate.Product[type][name]
                end
            end

            local floor_products = structures.class.to_array(subfloor_aggregate.Product)
            model.update_floor(subfloor, subfloor_aggregate)  -- updates aggregate


            -- Convert the internal product-format into positive products for the line and main aggregate
            for _, product in pairs(floor_products) do
                local aggregate_product_amount = subfloor_aggregate.Product[product.type][product.name] or 0
                subfloor_aggregate.Product[product.type][product.name] = product.amount - aggregate_product_amount
            end

            -- Update the main aggregate with the results
            aggregate.energy_consumption = aggregate.energy_consumption + subfloor_aggregate.energy_consumption
            aggregate.pollution = aggregate.pollution + subfloor_aggregate.pollution

            -- Subtract subfloor products as produced
            for _, item in ipairs(structures.class.to_array(subfloor_aggregate.Product)) do
                structures.aggregate.subtract(aggregate, "Product", item)
            end

            structures.class.balance_items(subfloor_aggregate.Ingredient, aggregate, "Byproduct", "Product")
            structures.class.balance_items(subfloor_aggregate.Byproduct, aggregate, "Product", "Byproduct")


            -- Update the parent line of the subfloor with the results from the subfloor aggregate
            calculation.interface.set_line_result {
                player_index = aggregate.player_index,
                floor_id = aggregate.floor_id,
                line_id = line_data.id,
                machine_count = subfloor_aggregate.machine_count,
                energy_consumption = subfloor_aggregate.energy_consumption,
                pollution = subfloor_aggregate.pollution,
                production_ratio = nil,
                uncapped_production_ratio = nil,
                Product = subfloor_aggregate.Product,
                Byproduct = subfloor_aggregate.Byproduct,
                Ingredient = subfloor_aggregate.Ingredient,
                fuel_amount = nil
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
        else
            -- Add top level products that are also ingredients to the ingredients
            local negative_amount = product.amount - desired_products[product.type][product.name]
            if negative_amount > 0 then
                structures.aggregate.add(aggregate, "Ingredient", product, negative_amount)
            end
        end
    end
end


function model.update_line(line_data, aggregate)
    local recipe_proto, machine_proto = line_data.recipe_proto, line_data.machine_proto
    local total_effects, timescale = line_data.total_effects, line_data.timescale

    -- Determine relevant products
    local relevant_products, byproducts = {}, {}
    for _, product in pairs(recipe_proto.products) do
        if aggregate.Product[product.type][product.name] ~= nil then
            table.insert(relevant_products, product)
        else
            table.insert(byproducts, product)
        end
    end

    -- Determine production ratio
    local production_ratio, uncapped_production_ratio = 0, 0
    local crafts_per_tick = calculation.util.determine_crafts_per_tick(machine_proto, recipe_proto, total_effects)

    -- Determines the production ratio that would be needed to fully satisfy the given product
    local function determine_production_ratio(relevant_product)
        local demand = aggregate.Product[relevant_product.type][relevant_product.name]
        local prodded_amount = calculation.util.determine_prodded_amount(relevant_product,
          crafts_per_tick, total_effects)
        return (demand * (line_data.percentage / 100)) / prodded_amount
    end

    local relevant_product_count = #relevant_products
    if relevant_product_count == 1 then
        local relevant_product = relevant_products[1]
        production_ratio = determine_production_ratio(relevant_product)

    elseif relevant_product_count >= 2 then
        local priority_proto = line_data.priority_product_proto

        for _, relevant_product in ipairs(relevant_products) do
            if priority_proto ~= nil then  -- Use the priority product to determine the production ratio, if it's set
                if relevant_product.type == priority_proto.type and relevant_product.name == priority_proto.name then
                    production_ratio = determine_production_ratio(relevant_product)
                    break
                end

            else  -- Otherwise, determine the highest production ratio needed to fulfill every demand
                local ratio = determine_production_ratio(relevant_product)
                production_ratio = math.max(production_ratio, ratio)
            end
        end
    end
    uncapped_production_ratio = production_ratio  -- retain the uncapped ratio for line_data

    -- Limit the machine_count by reducing the production_ratio, if necessary
    local machine_limit = line_data.machine_limit
    if machine_limit.limit ~= nil then
        local capped_production_ratio = calculation.util.determine_production_ratio(crafts_per_tick,
          machine_limit.limit, timescale, machine_proto.is_rocket_silo)
        production_ratio = machine_limit.hard_limit and
          capped_production_ratio or math.min(production_ratio, capped_production_ratio)
    end


    -- Determines the amount of the given item, considering productivity
    local function determine_amount_with_productivity(item)
        local prodded_amount = calculation.util.determine_prodded_amount(item, crafts_per_tick, total_effects)
        return prodded_amount * production_ratio
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
    for _, product in ipairs(relevant_products) do
        local product_amount = determine_amount_with_productivity(product)
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

    -- Determine ingredients
    local Ingredient = structures.class.init()
    for _, ingredient in pairs(recipe_proto.ingredients) do
        -- If productivity is to be ignored, un-apply it by applying the product-productivity to an ingredient,
        -- effectively reversing the effect (this is way simpler than doing it properly)
        local ingredient_amount = (ingredient.ignore_productivity) and
          determine_amount_with_productivity(ingredient) or (ingredient.amount * production_ratio)

        structures.class.add(Ingredient, ingredient, ingredient_amount)

        -- Reduce the line-byproducts and -ingredients so only the net amounts remain
        local byproduct_amount = Byproduct[ingredient.type][ingredient.name]
        if byproduct_amount ~= nil then
            structures.class.subtract(Byproduct, ingredient, ingredient_amount)
            structures.class.subtract(Ingredient, ingredient, byproduct_amount)
        end
    end
    structures.class.balance_items(Ingredient, aggregate, "Byproduct", "Product")


    -- Determine machine count
    local machine_count = calculation.util.determine_machine_count(crafts_per_tick, production_ratio,
      timescale, machine_proto.is_rocket_silo)

    -- Add the integer machine count to the aggregate so it can be displayed on the origin_line
    aggregate.machine_count = aggregate.machine_count + math.ceil(machine_count)


    -- Determine energy consumption (including potential fuel needs) and pollution
    local fuel_proto = line_data.fuel_proto
    local energy_consumption = calculation.util.determine_energy_consumption(machine_proto,
      machine_count, total_effects)  -- calculated in W/timescale
    local pollution = calculation.util.determine_pollution(machine_proto, recipe_proto,
      fuel_proto, total_effects, energy_consumption)  -- calculated in P/m

    local fuel_amount = nil
    if fuel_proto ~= nil then  -- Seeing a fuel_proto here means it needs to be re-calculated
        fuel_amount = calculation.util.determine_fuel_amount(energy_consumption, machine_proto.burner,
          fuel_proto.fuel_value, timescale)

        local fuel_class = structures.class.init()
        local fuel = {type=fuel_proto.type, name=fuel_proto.name, amount=fuel_amount}
        structures.class.add(fuel_class, fuel)

        -- Add fuel to the aggregate, consuming this line's byproducts first, if possible
        structures.class.balance_items(fuel_class, aggregate, "Byproduct", "Product")

        energy_consumption = 0  -- set electrical consumption to 0 when fuel is used

    elseif machine_proto.energy_type == "void" then
        energy_consumption = 0  -- set electrical consumption to 0 while still polluting
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
        fuel_amount = fuel_amount
    }
end