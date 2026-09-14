local structures = require("backend.calculation.structures")

-- Contains the 'meat and potatoes' calculation model that struggles with some more complex setups
local sequential_engine = {}

---@class SolverItemWithConstant: SolverItem
---@field constant boolean?

-- ** LOCAL UTIL **
--- A producing line is paced by the outstanding demand for the products it makes
---@param line_data LineData
---@param aggregate SolverAggregate
---@param demanded_products SolverItem[]
---@return number
local function determine_producing_ratio(line_data, aggregate, demanded_products)
    ---@param product SolverItem
    ---@return number
    local function demanded_ratio(product)
        local demand = aggregate.ingredients[structures.pack_item(product)]
        return demand / product.amount
    end

    if #demanded_products == 1 then return demanded_ratio(demanded_products[1]) end
    local production_ratio = 0  ---@type number

    for _, product in ipairs(demanded_products) do
        if not line_data.priority_item then  -- satisfy every demand, so take the highest ratio
            production_ratio = math.max(production_ratio, demanded_ratio(product))
        elseif structures.pack_item(product) == structures.pack_item(line_data.priority_item) then
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
        return available / ingredient.amount
    end

    local production_ratio = 0  ---@type number

    for _, ingredient in pairs(ingredients) do
        local ingredient_key = structures.pack_item(ingredient)
        local available = aggregate.byproducts[ingredient_key]  ---@type number?

        if line_data.priority_item then
            -- The priority ingredient paces the line by itself, importing the others as needed
            if ingredient_key == structures.pack_item(line_data.priority_item) then
                if available == nil then return 0 end  -- nothing of it left to consume
                return available_ratio(ingredient, available)
            end

        elseif available == nil then
            -- Avoid importing additional ingredients if they are a consumed byproduct further up
            if aggregate.known_byproducts[structures.pack_item(ingredient)] then return 0 end

        else  -- stay within every byproduct's availability, so take the lowest ratio
            local ratio = available_ratio(ingredient, available)
            production_ratio = (production_ratio == 0) and ratio or math.min(production_ratio, ratio)
        end
    end

    return production_ratio
end


---@param line_data LineData
---@param aggregate SolverAggregate
local function update_line(line_data, aggregate)
    local products = structures.map.list(line_data.products)
    local ingredients = structures.map.list(line_data.ingredients)  ---@as SolverItemWithConstant[]
    local consuming = (line_data.production_type == "consume")

    -- Split the recipe's products by whether this floor has a demand for them
    local demanded_products, byproducts = {}, {}  ---@type SolverItem[], SolverItem[]
    for _, product in pairs(products) do
        local demanded = (aggregate.ingredients[structures.pack_item(product)] ~= nil)
        table.insert((demanded) and demanded_products or byproducts, product)
    end

    -- Determine machine count
    -- Line data assumes a machine amount of 1, so production_ratio == machine_amount
    local machine_amount = (consuming) and determine_consuming_ratio(line_data, aggregate, ingredients)
        or determine_producing_ratio(line_data, aggregate, demanded_products)

    -- Limit the machine amount
    if line_data.machine_limit then
        machine_amount = line_data.machine_force_limit and line_data.machine_limit
            or math.min(machine_amount, line_data.machine_limit)
    end

    -- Determine crafts per second
    local crafts_per_second = machine_amount * line_data.crafts_per_second

    -- Determine byproducts
    local line_byproducts = {}  ---@type SolverMap

    ---@param item SolverItem
    ---@param amount number
    local function add_byproduct(item, amount)
        structures.map.add(line_byproducts, item, amount)
        structures.map.add(aggregate.byproducts, item, amount)
        aggregate.known_byproducts[structures.pack_item(item)] = true
    end

    for _, byproduct in pairs(byproducts) do
        local amount = byproduct.amount * machine_amount
        add_byproduct(byproduct, amount)
    end

    -- Determine products
    local line_products = {}  ---@type SolverMap
    for _, product in ipairs(demanded_products) do
        local amount = product.amount * machine_amount
        local demand = aggregate.ingredients[structures.pack_item(product)] or 0

        if amount > demand then
            local overflow_amount = amount - demand
            add_byproduct(product, overflow_amount)
            amount = demand  -- desired amount
        end

        structures.map.add(line_products, product, amount)
        structures.map.subtract(aggregate.ingredients, product, amount)
    end

    -- Determine ingredients
    local line_ingredients = {}  ---@type SolverMap
    for _, ingredient in pairs(ingredients) do
        local ingredient_amount = ingredient.amount * machine_amount

        structures.map.add(line_ingredients, ingredient, ingredient_amount)

        -- Reduce line-byproducts and -ingredients so only the net amounts remain
        local byproduct_amount = line_byproducts[structures.pack_item(ingredient)]  ---@as number?
        if byproduct_amount then
            structures.map.subtract(line_byproducts, ingredient, ingredient_amount)
            structures.map.subtract(line_ingredients, ingredient, byproduct_amount)
        end
    end
    structures.map.balance_items(line_ingredients, aggregate.byproducts, aggregate.ingredients)

    -- Determine fuel
    local fuel_amount
    if line_data.fuel_item then
        local fuel_key = structures.pack_item(line_data.fuel_item)
        fuel_amount = line_data.fuel_item.amount * machine_amount
        local ingredient_amount = line_ingredients[fuel_key] or 0
        if fuel_amount <= ingredient_amount then
            structures.map.subtract(line_ingredients, line_data.fuel_item, fuel_amount)
        else
            structures.map.add(line_products, line_data.fuel_item, fuel_amount - ingredient_amount)
            line_ingredients[fuel_key] = nil
        end
    end

    -- Add the integer machine count to the aggregate so it can be displayed on the origin_line
    aggregate.machine_amount = aggregate.machine_amount + math.ceil(machine_amount - MAGIC_NUMBERS.margin_of_error)

    -- Update the actual line with the calculated results
    solver.set_line_result {
        floor_id = aggregate.floor_id,
        line_id = line_data.line_id,
        machine_amount = machine_amount,
        crafts_per_second = crafts_per_second,
        products = line_products,
        byproducts = line_byproducts,
        ingredients = line_ingredients,
        fuel_amount = fuel_amount
    }
end


---@param factory_data FactoryData
---@param floor_id ObjectID
---@param aggregate SolverAggregate
local function update_floor(factory_data, floor_id, aggregate)
    local desired_products = structures.map.list(aggregate.ingredients)
    local floor_data = factory_data.floor_data_map[floor_id]

    for _, line_object_id in ipairs(floor_data.line_ids) do
        local subfloor_data = factory_data.floor_data_map[line_object_id]
        if subfloor_data then
            -- Determine the products that are relevant for this subfloor
            local subfloor_aggregate = structures.aggregate.init(line_object_id)
           for _, product in pairs(subfloor_data.products) do
                local ingredient_amount = aggregate.ingredients[structures.pack_item(product)]  ---@type number?
                if ingredient_amount then
                    structures.map.add(subfloor_aggregate.ingredients, product, ingredient_amount)
                end
            end

            local floor_products = structures.map.list(subfloor_aggregate.ingredients)
            update_floor(factory_data, line_object_id, subfloor_aggregate)  -- updates aggregate

            for _, desired_product in pairs(floor_products) do
                local ingredient_amount = aggregate.products[structures.pack_item(desired_product)] or 0
                local produced_amount = desired_product.amount - ingredient_amount
                structures.map.subtract(aggregate.ingredients, desired_product, produced_amount)
            end

            structures.map.balance_items(subfloor_aggregate.ingredients, aggregate.byproducts, aggregate.ingredients)
            -- Byproducts coming out of a subfloor are consumable on this floor like any other
            for item_key, _ in pairs(subfloor_aggregate.byproducts) do
                aggregate.known_byproducts[item_key] = true
            end
            structures.map.balance_items(subfloor_aggregate.byproducts, aggregate.products, aggregate.byproducts)

            aggregate.machine_amount = aggregate.machine_amount + subfloor_aggregate.machine_amount

            -- Unproduced requests remain on the parent, but aren't ingredients of this subfloor
            for _, desired_product in pairs(floor_products) do
                local ingredient_amount = subfloor_aggregate.ingredients[structures.pack_item(desired_product)] or 0
                structures.map.subtract(subfloor_aggregate.ingredients, desired_product, ingredient_amount)
            end

            -- Update the parent line of the subfloor with the results from the subfloor aggregate
            solver.set_line_result {
                floor_id = aggregate.floor_id,
                line_id = line_object_id,
                machine_amount = subfloor_aggregate.machine_amount,
                crafts_per_second = nil,
                products = subfloor_aggregate.products,
                byproducts = subfloor_aggregate.byproducts,
                ingredients = subfloor_aggregate.ingredients,
                fuel_amount = nil
            }
        else
            -- Update aggregate according to the current line, which also adjusts the respective line object
            local line_data = factory_data.line_data_map[line_object_id]
            update_line(line_data, aggregate)  -- updates aggregate
        end
    end

    -- Desired products that aren't ingredients anymore have been produced
    for _, desired_product in pairs(desired_products) do
        local ingredient_amount = aggregate.ingredients[structures.pack_item(desired_product)] or 0
        local produced_amount = desired_product.amount - ingredient_amount
        structures.map.add(aggregate.products, desired_product, produced_amount)
    end
end


-- ** TOP LEVEL **
---@param factory_data FactoryData
function sequential_engine.update_factory(factory_data)
    -- Initialize aggregate with the top level items
    local aggregate = structures.aggregate.init(factory_data.top_floor_id)
    local top_floor_data = factory_data.floor_data_map[factory_data.top_floor_id]
    for _, product in pairs(top_floor_data.products) do
        structures.map.add(aggregate.ingredients, product)
    end

    update_floor(factory_data, factory_data.top_floor_id, aggregate)  -- updates aggregate

    -- Remove any top level items that are still ingredients, meaning unproduced
    for _, product in pairs(top_floor_data.products) do
        local ingredient_amount = aggregate.ingredients[structures.pack_item(product)] or 0  ---@type number
        structures.map.subtract(aggregate.ingredients, product, ingredient_amount)
    end

    -- Fuels are combined with ingredients for top-level purposes
    solver.set_factory_result {
        player_index = factory_data.player_index,
        factory_id = factory_data.factory_id,
        products = aggregate.products,
        byproducts = aggregate.byproducts,
        ingredients = aggregate.ingredients
    }
end

return sequential_engine
