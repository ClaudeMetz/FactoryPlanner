local structures = require("backend.calculation.structures")

-- Contains the 'meat and potatoes' calculation model that struggles with some more complex setups
local sequential_engine = {}

-- ** LOCAL UTIL **
local function update_line(line_data, aggregate)
    local recipe_proto = line_data.recipe_proto
    local machine_proto = line_data.machine_proto
    local total_effects = line_data.total_effects

    -- Determine relevant products
    local relevant_products, byproducts = {}, {}
    for _, product in pairs(recipe_proto.products) do
        local ingredient = structures.class.find(aggregate.Ingredient, product)
        if ingredient then relevant_products[product] = ingredient.amount
        else table.insert(byproducts, product) end
    end

    local production_ratio = 0

    -- Determines the production ratio that would be needed to fully satisfy the given product
    local function determine_production_ratio(relevant_product, demand)
        local prodded_amount = solver_util.determine_prodded_amount(relevant_product,
            total_effects, recipe_proto.maximum_productivity)
        return (demand * (line_data.percentage / 100)) / prodded_amount
    end

    local relevant_product_count = table_size(relevant_products)
    if relevant_product_count == 1 then
        local relevant_product, demand = next(relevant_products, nil)
        production_ratio = determine_production_ratio(relevant_product, demand)

    elseif relevant_product_count >= 2 then
        local priority_proto = line_data.priority_product_proto

        for relevant_product, demand in pairs(relevant_products) do
            if priority_proto ~= nil then  -- Use the priority product to determine the production ratio, if it's set
                if relevant_product.type == priority_proto.type and relevant_product.name == priority_proto.name then
                    production_ratio = determine_production_ratio(relevant_product, demand)
                    break
                end

            else  -- Otherwise, determine the highest production ratio needed to fulfill every demand
                local ratio = determine_production_ratio(relevant_product, demand)
                production_ratio = math.max(production_ratio, ratio)
            end
        end
    end

    local crafts_per_second = (line_data.machine_speed * (1 + total_effects.speed)) / recipe_proto.energy

    -- Limit the machine_count by reducing the production_ratio, if necessary
    local machine_limit = line_data.machine_limit
    if machine_limit.limit ~= nil then
        local capped_production_ratio = crafts_per_second * machine_limit.limit
        production_ratio = machine_limit.force_limit and capped_production_ratio
            or math.min(production_ratio, capped_production_ratio)
    end


    -- Determines the amount of the given item, considering productivity
    local function determine_amount_with_productivity(item)
        local prodded_amount = solver_util.determine_prodded_amount(item,
            total_effects, recipe_proto.maximum_productivity)
        return prodded_amount * production_ratio
    end

    -- Determine byproducts
    local Byproduct = structures.class.init()
    for _, byproduct in pairs(byproducts) do
        local byproduct_amount = determine_amount_with_productivity(byproduct)

        structures.class.add(Byproduct, byproduct, byproduct_amount)
        structures.class.add(aggregate.Byproduct, byproduct, byproduct_amount)
    end

    -- Determine products
    local Product = structures.class.init()
    for product, demand in pairs(relevant_products) do
        local product_amount = determine_amount_with_productivity(product)

        if product_amount > demand then
            local overflow_amount = product_amount - demand
            structures.class.add(Byproduct, product, overflow_amount)
            structures.class.add(aggregate.Byproduct, product, overflow_amount)
            product_amount = demand  -- desired amount
        end

        structures.class.add(Product, product, product_amount)
        structures.class.subtract(aggregate.Ingredient, product, product_amount)
    end

    -- Determine ingredients
    local Ingredient = structures.class.init()
    for _, ingredient in pairs(recipe_proto.ingredients) do
        local ingredient_amount = (ingredient.amount * production_ratio * line_data.resource_drain_rate)
        structures.class.add(Ingredient, ingredient, ingredient_amount)

        -- Reduce line-byproducts and -ingredients so only the net amounts remain
        local byproduct = structures.class.find(Byproduct, ingredient)
        if byproduct ~= nil then
            structures.class.subtract(Byproduct, ingredient, ingredient_amount)
            structures.class.subtract(Ingredient, ingredient, byproduct.amount)
        end
    end
    structures.class.balance_items(Ingredient, aggregate.Byproduct, aggregate.Ingredient)


    -- Determine machine count
    local machine_count = production_ratio / crafts_per_second
    -- Add the integer machine count to the aggregate so it can be displayed on the origin_line
    aggregate.machine_count = aggregate.machine_count + math.ceil(machine_count - 0.001)


    -- Determine energy consumption (including potential fuel needs) and emissions
    local fuel_proto = line_data.fuel_proto
    local energy_consumption, emissions = solver_util.determine_energy_consumption_and_emissions(
        machine_proto, recipe_proto, fuel_proto, machine_count, total_effects, line_data.pollutant_type)

    local fuel_amount = nil
    if fuel_proto ~= nil then
        fuel_amount = solver_util.determine_fuel_amount(energy_consumption, machine_proto.burner,
            fuel_proto.fuel_value)

        local fuel_class = structures.class.init()
        local fuel = {type=fuel_proto.type, name=fuel_proto.name, amount=fuel_amount}
        structures.class.add(fuel_class, fuel)

        -- Add fuel to the aggregate, consuming this line's byproducts first, if possible
        structures.class.balance_items(fuel_class, aggregate.Byproduct, aggregate.Ingredient)

        if fuel_proto.burnt_result then
            local burnt = {type="item", name=fuel_proto.burnt_result, amount=fuel_amount}
            structures.class.add(Byproduct, burnt)  -- add to line
            structures.class.add(aggregate.Byproduct, burnt)  -- add to floor
        end

        energy_consumption = 0  -- set electrical consumption to 0 when fuel is used

    elseif machine_proto.energy_type == "void" then
        energy_consumption = 0  -- set electrical consumption to 0 while still polluting
    end

    -- Include beacon energy consumption
    energy_consumption = energy_consumption + (line_data.beacon_consumption or 0)

    aggregate.energy_consumption = aggregate.energy_consumption + energy_consumption
    aggregate.emissions = aggregate.emissions + emissions


    -- Update the actual line with the calculated results
    solver.set_line_result {
        player_index = aggregate.player_index,
        floor_id = aggregate.floor_id,
        line_id = line_data.id,
        machine_count = machine_count,
        energy_consumption = energy_consumption,
        emissions = emissions,
        production_ratio = production_ratio,
        Product = Product,
        Byproduct = Byproduct,
        Ingredient = Ingredient,
        fuel_amount = fuel_amount
    }
end


local function update_floor(floor_data, aggregate)
    local desired_products = structures.class.list(aggregate.Ingredient, true)

    for _, line_data in ipairs(floor_data.lines) do
        local subfloor = line_data.subfloor
        if subfloor ~= nil then
            -- Determine the products that are relevant for this subfloor
            local subfloor_aggregate = structures.aggregate.init(aggregate.player_index, subfloor.id)
            for _, product in pairs(line_data.recipe_proto.products) do
                local ingredient = structures.class.find(aggregate.Ingredient, product)
                if ingredient then structures.class.add(subfloor_aggregate.Ingredient, ingredient) end
            end

            local floor_products = structures.class.list(subfloor_aggregate.Ingredient, true)
            update_floor(subfloor, subfloor_aggregate)  -- updates aggregate

            for _, desired_product in pairs(floor_products) do
                local product_match = structures.class.find(aggregate.Product, desired_product)
                local ingredient_amount = (product_match) and product_match.amount or 0
                local produced_amount = desired_product.amount - ingredient_amount
                structures.class.subtract(aggregate.Ingredient, desired_product, produced_amount)
            end

            structures.class.balance_items(subfloor_aggregate.Ingredient, aggregate.Byproduct, aggregate.Ingredient)
            structures.class.balance_items(subfloor_aggregate.Byproduct, aggregate.Product, aggregate.Byproduct)

            -- Update the main aggregate with the results
            aggregate.machine_count = aggregate.machine_count + subfloor_aggregate.machine_count
            aggregate.energy_consumption = aggregate.energy_consumption + subfloor_aggregate.energy_consumption
            aggregate.emissions = aggregate.emissions + subfloor_aggregate.emissions

            -- Update the parent line of the subfloor with the results from the subfloor aggregate
            solver.set_line_result {
                player_index = aggregate.player_index,
                floor_id = aggregate.floor_id,
                line_id = line_data.id,
                machine_count = subfloor_aggregate.machine_count,
                energy_consumption = subfloor_aggregate.energy_consumption,
                emissions = subfloor_aggregate.emissions,
                production_ratio = nil,
                Product = subfloor_aggregate.Product,
                Byproduct = subfloor_aggregate.Byproduct,
                Ingredient = subfloor_aggregate.Ingredient,
                fuel_amount = nil
            }
        else
            -- Update aggregate according to the current line, which also adjusts the respective line object
            update_line(line_data, aggregate)  -- updates aggregate
        end
    end

    -- Desired products that aren't ingredients anymore have been produced
    for _, desired_product in pairs(desired_products) do
        local ingredient_match = structures.class.find(aggregate.Ingredient, desired_product)
        local ingredient_amount = (ingredient_match) and ingredient_match.amount or 0
        local produced_amount = desired_product.amount - ingredient_amount
        structures.class.add(aggregate.Product, desired_product, produced_amount)
    end
end


-- ** TOP LEVEL **
function sequential_engine.update_factory(factory_data)
    -- Initialize aggregate with the top level items
    local aggregate = structures.aggregate.init(factory_data.player_index, 1)
    for _, product in pairs(factory_data.top_level_products) do
        structures.class.add(aggregate.Ingredient, product)
    end

    update_floor(factory_data.top_floor, aggregate)  -- updates aggregate

    -- Fuels are combined with ingredients for top-level purposes
    solver.set_factory_result {
        player_index = factory_data.player_index,
        factory_id = factory_data.factory_id,
        energy_consumption = aggregate.energy_consumption,
        emissions = aggregate.emissions,
        Product = aggregate.Product,
        Byproduct = aggregate.Byproduct,
        Ingredient = aggregate.Ingredient
    }
end

return sequential_engine
