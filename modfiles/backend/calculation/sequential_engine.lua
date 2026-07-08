local structures = require("backend.calculation.structures")

-- Contains the 'meat and potatoes' calculation model that struggles with some more complex setups
local sequential_engine = {}

---@class SolverItemWithConstant: SolverItem
---@field constant boolean?

-- ** LOCAL UTIL **
---@param line_data LineData
---@param aggregate SolverAggregate
---@param looped_fuel number?
local function update_line(line_data, aggregate, looped_fuel)
    local recipe_proto = line_data.recipe_proto
    local machine_proto = line_data.machine_proto
    local total_effects = line_data.total_effects

    local relevant_products, byproducts = {}, {}
    local ingredients = line_data.ingredients  ---@as SolverItemWithConstant[]
    local self_feeding = false
    local fuel_byproduct = nil  ---@type FormattedProduct?
    local original_aggregate = nil  ---@type SolverAggregate?
    local fuel_proto = line_data.fuel_proto

    -- Determine relevant products
    for _, product in pairs(recipe_proto.products) do
        local is_product = (aggregate.Ingredient[product.type][product.name] ~= nil)
        table.insert((is_product) and relevant_products or byproducts, product)

        -- Prepare for this line producing its own fuel
        if looped_fuel == nil and fuel_proto ~= nil then  -- don't loop if this already is the loop
            if product.type == fuel_proto.type and product.name == line_data.fuel_name then
                self_feeding = true
                if is_product then  -- conserve aggregate reference if we'll restart the calculation
                    original_aggregate = aggregate
                    aggregate = lib.flib.deep_copy(aggregate)
                else  -- retain byproduct item for later
                    fuel_byproduct = product
                end
            end
        end
    end

    --- Determines the production ratio that would be needed to fully satisfy the given product
    ---@param relevant_product FormattedProduct
    ---@return number
    local function determine_production_ratio(relevant_product)
        local demand = aggregate.Ingredient[relevant_product.type][relevant_product.name]
        local prodded_amount = solver.util.determine_prodded_amount(relevant_product, total_effects)
        return (demand * (line_data.percentage / 100)) / prodded_amount
    end

    -- Determine production ratio
    local production_ratio = 0  ---@type number

    local relevant_product_count = #relevant_products
    if relevant_product_count == 1 then
        local relevant_product = relevant_products[1]  ---@as FormattedProduct
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

    local speed_multiplier = 1 + (total_effects.speed / MAGIC_NUMBERS.effect_precision)
    local crafts_per_second = (line_data.machine_speed * speed_multiplier) / line_data.recipe_energy

    -- Limit the machine_amount by reducing the production_ratio, if necessary
    local machine_limit = line_data.machine_limit
    if machine_limit.limit ~= nil and line_data.recipe_energy > 0 then
        local capped_production_ratio = crafts_per_second * machine_limit.limit
        production_ratio = machine_limit.force_limit and capped_production_ratio
            or math.min(production_ratio, capped_production_ratio)
    end

    -- Determine machine count
    local machine_amount = production_ratio / crafts_per_second
    -- Add the integer machine count to the aggregate so it can be displayed on the origin_line
    aggregate.machine_amount = aggregate.machine_amount + math.ceil(machine_amount - MAGIC_NUMBERS.margin_of_error)


    --- Determines the amount of the given item, considering productivity
    ---@param item FormattedProduct
    ---@return number
    local function determine_amount_with_productivity(item)
        local prodded_amount = solver.util.determine_prodded_amount(item, total_effects)
        return prodded_amount * production_ratio
    end

    -- Determine power (including potential fuel needs) and emissions
    local power, emissions = solver.util.determine_power_and_emissions(machine_proto, recipe_proto, fuel_proto,
        machine_amount, line_data.energy_usage, total_effects, line_data.pollutant_type)

    local fuel_amount = nil
    if machine_proto.energy_type == "burner" then
        ---@cast fuel_proto -nil
        ---@cast machine_proto.burner -nil

        local fuel_name = line_data.fuel_name  ---@as string
        fuel_amount = solver.util.determine_fuel_amount(power, machine_proto.burner, fuel_proto.fuel_value)

        -- Handle recipes producing their own machine's fuel
        if self_feeding and production_ratio > 0 then
            if original_aggregate ~= nil then  -- means the fuel is a main product
                local ingredient_class = original_aggregate.Ingredient[fuel_proto.type]
                local initial_demand = ingredient_class[fuel_name]
                local ratio = fuel_amount / initial_demand

                if ratio + MAGIC_NUMBERS.margin_of_error < 1 then  -- a ratio >= 1 means this can't outproduce itself
                    -- Need a lot of precision here, hence the exponent of 20
                    local bumped_demand = initial_demand * ((1 - ratio ^ 20) / (1 - ratio))
                    ingredient_class[fuel_name] = bumped_demand

                    -- Run line with fuel amount bumped to account for own consumption
                    update_line(line_data, original_aggregate, bumped_demand - initial_demand)
                    return
                end
            else  -- means the fuel is a byproduct only, which shouldn't affect production
                local byproduct_amount = determine_amount_with_productivity(fuel_byproduct--[[@cast -nil]])
                local used_amount = math.min(fuel_amount, byproduct_amount)  ---@as number

                local fuel_item = {type=fuel_proto.type, name=fuel_name, amount=used_amount}  ---@type SolverItem
                structures.class.subtract(aggregate.Byproduct, fuel_item)  -- subtract from floor
                looped_fuel = used_amount
            end
        end

        -- Removed looped fuel from main aggregate as its used right away
        local corrected_amount = fuel_amount - (looped_fuel or 0)
        local fuel_item = {type=fuel_proto.type, name=fuel_name, amount=corrected_amount}  ---@type SolverItem
        structures.class.add(aggregate.Ingredient, fuel_item)  -- add to floor
        -- Fuel itself is set via a special amount variable on the line itself

        if fuel_proto.burnt_result then
            table.insert(byproducts, {
                type="item",
                name=fuel_proto.burnt_result,
                amount=fuel_amount,
                constant=true
            })
        end

        if machine_proto.burner.produces_spent_fluid then
            local spent_fluid = machine_proto.burner.spent_fluid or fuel_proto.spent_fluid
            if spent_fluid then
                table.insert(byproducts, {
                    type="fluid",
                    name=spent_fluid.name .. "-" .. spent_fluid.temperature,
                    amount=fuel_amount * spent_fluid.amount,
                    constant=true
                })
            end
        end

        power = 0  -- set power to 0 when fuel is used

    elseif machine_proto.energy_type == "heat" then
        local heat_item = {type="entity", name="custom-heat-power", amount=power, constant=true}
        table.insert(ingredients, heat_item)

        power = 0  -- set power to 0 when heat is used

    elseif machine_proto.energy_type == "void" then
        power = 0  -- set power to 0 while still polluting
    end

    power = power + (line_data.beacon_power or 0)

    if power > 0 then
        local electric_item = {type="entity", name="custom-electric-power", amount=power, constant=true}
        table.insert(ingredients, electric_item)
    end

    if line_data.entities_require_heating and machine_proto.heating_energy > 0 then
        local heating_energy = machine_proto.heating_energy * machine_amount
        local heating_item = {type="entity", name="custom-heating-power", amount=heating_energy, constant=true}
        table.insert(ingredients, heating_item)
    end

    if emissions ~= 0 then  -- emissions are either produced or consumed
        local emission_name = "custom-" .. line_data.pollutant_type
        local emission_item = {type="entity", name=emission_name,
            amount=math.abs(emissions)--[[@as number]], constant=true}
        if emissions > 0 then
            local is_product = (aggregate.Ingredient["entity"][emission_name] ~= nil)
            table.insert((is_product) and relevant_products or byproducts, emission_item)
        elseif emissions < 0 then
            table.insert(ingredients, emission_item)
        end
    end

    -- Determine byproducts
    local Byproduct = structures.class.init()
    for _, byproduct in pairs(byproducts) do
        local byproduct_amount = (byproduct.constant) and byproduct.amount
            or determine_amount_with_productivity(byproduct)

        structures.class.add(Byproduct, byproduct, byproduct_amount)
        structures.class.add(aggregate.Byproduct, byproduct, byproduct_amount)
    end

    -- Determine products
    local Product = structures.class.init()
    for _, product in ipairs(relevant_products) do
        local product_amount = (product.constant) and product.amount
            or determine_amount_with_productivity(product)
        local product_demand = aggregate.Ingredient[product.type][product.name] or 0

        if product_amount > product_demand then
            local overflow_amount = product_amount - product_demand
            structures.class.add(Byproduct, product, overflow_amount)
            structures.class.add(aggregate.Byproduct, product, overflow_amount)
            product_amount = product_demand  -- desired amount
        end

        structures.class.add(Product, product, product_amount)
        structures.class.subtract(aggregate.Ingredient, product, product_amount)
    end

    -- Determine ingredients
    local Ingredient = structures.class.init()
    for _, ingredient in pairs(ingredients) do
        local ingredient_amount = (ingredient.constant) and ingredient.amount
            or ingredient.amount * production_ratio
        if ingredient.type ~= "fluid" then  -- doesn't apply to mining fluids
            ingredient_amount = ingredient_amount * line_data.resource_drain_rate
        end

        structures.class.add(Ingredient, ingredient, ingredient_amount)

        -- Reduce line-byproducts and -ingredients so only the net amounts remain
        local byproduct_amount = Byproduct[ingredient.type][ingredient.name]  ---@as number?
        if byproduct_amount ~= nil then
            structures.class.subtract(Byproduct, ingredient, ingredient_amount)
            structures.class.subtract(Ingredient, ingredient, byproduct_amount)
        end
    end
    structures.class.balance_items(Ingredient, aggregate.Byproduct, aggregate.Ingredient)


    -- Update the actual line with the calculated results
    solver.set_line_result {
        player_index = aggregate.player_index,
        floor_id = aggregate.floor_id,
        line_id = line_data.id,
        machine_amount = machine_amount,
        production_ratio = production_ratio,
        Product = Product,
        Byproduct = Byproduct,
        Ingredient = Ingredient,
        fuel_amount = fuel_amount
    }
end


---@param floor_data FloorData
---@param aggregate SolverAggregate
local function update_floor(floor_data, aggregate)
    local desired_products = structures.class.list(aggregate.Ingredient)

    for _, line_data in ipairs(floor_data.lines) do
        local subfloor = line_data.subfloor
        if subfloor ~= nil then
            -- Determine the products that are relevant for this subfloor
            local subfloor_aggregate = structures.aggregate.init(aggregate.player_index, subfloor.id)
           for _, product in pairs(line_data.recipe_proto.products) do
                local ingredient_amount = aggregate.Ingredient[product.type][product.name]  ---@type number?
                if ingredient_amount then
                    structures.class.add(subfloor_aggregate.Ingredient, product, ingredient_amount)
                end
            end

            local floor_products = structures.class.list(subfloor_aggregate.Ingredient)
            update_floor(subfloor, subfloor_aggregate)  -- updates aggregate

            for _, desired_product in pairs(floor_products) do
                local ingredient_amount = aggregate.Product[desired_product.type][desired_product.name] or 0
                local produced_amount = desired_product.amount - ingredient_amount
                structures.class.subtract(aggregate.Ingredient, desired_product, produced_amount)
            end

            structures.class.balance_items(subfloor_aggregate.Ingredient, aggregate.Byproduct, aggregate.Ingredient)
            structures.class.balance_items(subfloor_aggregate.Byproduct, aggregate.Product, aggregate.Byproduct)

            aggregate.machine_amount = aggregate.machine_amount + subfloor_aggregate.machine_amount

            -- Update the parent line of the subfloor with the results from the subfloor aggregate
            solver.set_line_result {
                player_index = aggregate.player_index,
                floor_id = aggregate.floor_id,
                line_id = line_data.id,
                machine_amount = subfloor_aggregate.machine_amount,
                production_ratio = nil,
                Product = subfloor_aggregate.Product,
                Byproduct = subfloor_aggregate.Byproduct,
                Ingredient = subfloor_aggregate.Ingredient,
                fuel_amount = nil
            }
        else
            -- Update aggregate according to the current line, which also adjusts the respective line object
            update_line(line_data--[[@as LineData]], aggregate, nil)  -- updates aggregate
        end
    end

    -- Desired products that aren't ingredients anymore have been produced
    for _, desired_product in pairs(desired_products) do
        local ingredient_amount = aggregate.Ingredient[desired_product.type][desired_product.name] or 0
        local produced_amount = desired_product.amount - ingredient_amount
        structures.class.add(aggregate.Product, desired_product, produced_amount)
    end
end


-- ** TOP LEVEL **
---@param factory_data FactoryData
function sequential_engine.update_factory(factory_data)
    -- Initialize aggregate with the top level items
    local aggregate = structures.aggregate.init(factory_data.player_index, 1)
    for _, product in pairs(factory_data.top_floor.products) do
        structures.class.add(aggregate.Ingredient, product)
    end

    update_floor(factory_data.top_floor, aggregate)  -- updates aggregate

    -- Remove any top level items that are still ingredients, meaning unproduced
    for _, product in pairs(factory_data.top_floor.products) do
        local ingredient_amount = aggregate.Ingredient[product.type][product.name] or 0  ---@type number
        structures.class.subtract(aggregate.Ingredient, product, ingredient_amount)
    end

    -- Fuels are combined with ingredients for top-level purposes
    solver.set_factory_result {
        player_index = factory_data.player_index,
        factory_id = factory_data.factory_id,
        Product = aggregate.Product,
        Byproduct = aggregate.Byproduct,
        Ingredient = aggregate.Ingredient
    }
end

return sequential_engine
