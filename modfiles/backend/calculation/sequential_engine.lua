local structures = require("backend.calculation.structures")

-- Contains the 'meat and potatoes' calculation model that struggles with some more complex setups
local sequential_engine = {}

---@class SolverItemWithConstant: SolverItem
---@field constant boolean?

-- ** LOCAL UTIL **
--- A producing line is paced by the outstanding demand for the products it makes
---@param line_data LineData
---@param aggregate SolverAggregate
---@param demanded_products FormattedProduct[]
---@return number
local function determine_producing_ratio(line_data, aggregate, demanded_products)
    ---@param product FormattedProduct
    ---@return number
    local function demanded_ratio(product)
        local demand = aggregate.Ingredient[product.type][product.name]
        local prodded_amount = solver.util.determine_prodded_amount(product, line_data.total_effects)
        return (demand * (line_data.percentage / 100)) / prodded_amount
    end

    if #demanded_products == 1 then return demanded_ratio(demanded_products[1]) end

    local priority_proto = line_data.priority_item_proto
    local production_ratio = 0  ---@type number

    for _, product in ipairs(demanded_products) do
        if priority_proto == nil then  -- satisfy every demand, so take the highest ratio
            production_ratio = math.max(production_ratio, demanded_ratio(product))

        elseif product.type == priority_proto.type and product.name == priority_proto.name then
            return demanded_ratio(product)  -- the priority product paces the line by itself
        end
    end

    return production_ratio
end

--- A consuming line is paced by the byproducts available to its ingredients
---@param line_data LineData
---@param aggregate SolverAggregate
---@param ingredients SolverItemWithConstant[]
---@return number
local function determine_consuming_ratio(line_data, aggregate, ingredients)
    ---@param ingredient SolverItemWithConstant
    ---@param available number
    ---@return number
    local function available_ratio(ingredient, available)
        local amount = ingredient.amount
        if ingredient.type ~= "fluid" then amount = amount * line_data.resource_drain_rate end
        return (available * (line_data.percentage / 100)) / amount
    end

    local priority_proto = line_data.priority_item_proto
    local production_ratio = 0  ---@type number

    for _, ingredient in pairs(ingredients) do
        local available = aggregate.Byproduct[ingredient.type][ingredient.name]  ---@type number?

        if priority_proto ~= nil then
            -- The priority ingredient paces the line by itself, importing the others as needed
            if ingredient.type == priority_proto.type and ingredient.name == priority_proto.name then
                if available == nil then return 0 end  -- nothing of it left to consume
                return available_ratio(ingredient, available)
            end

        elseif available == nil then
            -- Avoid importing additional ingredients if they are a consumed byproduct further up
            if aggregate.known_byproducts[ingredient.type][ingredient.name] then return 0 end

        else  -- stay within every byproduct's availability, so take the lowest ratio
            local ratio = available_ratio(ingredient, available)
            production_ratio = (production_ratio == 0) and ratio or math.min(production_ratio, ratio)
        end
    end

    return production_ratio
end


---@param line_data LineData
---@param aggregate SolverAggregate
---@param looped_fuel number?
local function update_line(line_data, aggregate, looped_fuel)
    local machine_proto = line_data.machine_proto
    local total_effects = line_data.total_effects

    local ingredients = line_data.ingredients  ---@as SolverItemWithConstant[]
    local fuel_proto = line_data.fuel_proto
    local consuming = (line_data.production_type == "consume")

    -- Split the recipe's products by whether this floor has a demand for them
    local demanded_products, byproducts = {}, {}
    for _, product in pairs(line_data.products) do
        local demanded = (aggregate.Ingredient[product.type][product.name] ~= nil)
        table.insert((demanded) and demanded_products or byproducts, product)
    end

    -- Repare for the recipe producing its own fuel, which requires a second pass
    local fuel_byproduct = nil  ---@type FormattedProduct?
    local fuel_demanded = false
    if looped_fuel == nil and fuel_proto ~= nil then  -- don't loop if this already is the loop
        for _, product in pairs(line_data.products) do
            if product.type == fuel_proto.type and product.name == line_data.fuel_name then
                if aggregate.Ingredient[product.type][product.name] == nil then
                    fuel_byproduct = product
                elseif not consuming then  -- bumping demand is pointless for a consuming line
                    fuel_demanded = true
                end
                break
            end
        end
    end

    local production_ratio = (consuming) and determine_consuming_ratio(line_data, aggregate, ingredients)
        or determine_producing_ratio(line_data, aggregate, demanded_products)

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

    --- Determines the amount of the given item, considering productivity
    ---@param item FormattedProduct
    ---@return number
    local function determine_amount_with_productivity(item)
        local prodded_amount = solver.util.determine_prodded_amount(item, total_effects)
        return prodded_amount * production_ratio
    end

    -- Determine power (including potential fuel needs) and emissions
    local power, emissions = solver.util.determine_power_and_emissions(line_data, machine_amount, production_ratio)

    local fuel_amount = nil
    if machine_proto.energy_type == "burner" then
        ---@cast fuel_proto -nil
        ---@cast machine_proto.burner -nil

        local fuel_name = line_data.fuel_name  ---@as string
        fuel_amount = solver.util.determine_fuel_amount(line_data, power, machine_amount)

        -- Handle recipes producing their own machine's fuel as a main product
        if production_ratio > 0 and fuel_demanded then
            local ingredient_class = aggregate.Ingredient[fuel_proto.type]
            local initial_demand = ingredient_class[fuel_name]
            local ratio = fuel_amount / initial_demand

            if ratio + MAGIC_NUMBERS.margin_of_error < 1 then  -- a ratio >= 1 means this can't outproduce itself
                -- Need a lot of precision here, hence the exponent of 20
                local bumped_demand = initial_demand * ((1 - ratio ^ 20) / (1 - ratio))
                ingredient_class[fuel_name] = bumped_demand

                -- Run line with fuel amount bumped to account for own consumption
                update_line(line_data, aggregate, bumped_demand - initial_demand)
                return
            end
            -- The aggregate can now be modified, as it won't be needed for the redo on looped fuel
        end

        -- Looped fuel is used up right away, and never enters the aggregate
        local outstanding_amount = fuel_amount - (looped_fuel or 0)

        -- Fuel first draws on the byproducts of this floor, including from this line
        local available_amount = aggregate.Byproduct[fuel_proto.type][fuel_name] or 0
        if fuel_byproduct ~= nil then  -- consuming it shouldn't affect production
            available_amount = available_amount + determine_amount_with_productivity(fuel_byproduct)
        end
        local drawn_amount = math.min(outstanding_amount, available_amount)  ---@as number

        local fuel_item = {type=fuel_proto.type, name=fuel_name, amount=drawn_amount}  ---@type SolverItem
        structures.class.subtract(aggregate.Byproduct, fuel_item)  -- subtract from floor
        structures.class.add(aggregate.Ingredient, fuel_item, outstanding_amount - drawn_amount)
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
                    name=lib.temperature.name_with(spent_fluid.name, spent_fluid.temperature),
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
            local demanded = (aggregate.Ingredient["entity"][emission_name] ~= nil)
            table.insert((demanded) and demanded_products or byproducts, emission_item)
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
        aggregate.known_byproducts[byproduct.type][byproduct.name] = true
    end

    -- Determine products
    local Product = structures.class.init()
    for _, product in ipairs(demanded_products) do
        local product_amount = (product.constant) and product.amount
            or determine_amount_with_productivity(product)
        local product_demand = aggregate.Ingredient[product.type][product.name] or 0

        if product_amount > product_demand then
            local overflow_amount = product_amount - product_demand
            structures.class.add(Byproduct, product, overflow_amount)
            structures.class.add(aggregate.Byproduct, product, overflow_amount)
            aggregate.known_byproducts[product.type][product.name] = true
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

    -- Add the integer machine count to the aggregate so it can be displayed on the origin_line
    aggregate.machine_amount = aggregate.machine_amount + math.ceil(machine_amount - MAGIC_NUMBERS.margin_of_error)


    -- Update the actual line with the calculated results
    solver.set_line_result {
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
            local subfloor_aggregate = structures.aggregate.init(subfloor.id)
           for _, product in pairs(line_data.products) do
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
            -- Byproducts coming out of a subfloor are consumable on this floor like any other
            for type, items_of_type in pairs(subfloor_aggregate.Byproduct) do
                for name, _ in pairs(items_of_type) do
                    aggregate.known_byproducts[type][name] = true
                end
            end
            structures.class.balance_items(subfloor_aggregate.Byproduct, aggregate.Product, aggregate.Byproduct)

            aggregate.machine_amount = aggregate.machine_amount + subfloor_aggregate.machine_amount

            -- Update the parent line of the subfloor with the results from the subfloor aggregate
            solver.set_line_result {
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
    local aggregate = structures.aggregate.init(1)
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
