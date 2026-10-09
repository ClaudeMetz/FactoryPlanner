local structures = require("backend.calculation.structures")

-- Contains the 'meat and potatoes' calculation model that struggles with some more complex setups
local sequential_engine = {}


-- ** LOCAL UTIL **
--- A producing line is paced by the outstanding demand for the products it makes
---@param line_data LineData
---@param aggregate SolverAggregate
---@param products SolverItem[]
---@return number
local function determine_producing_ratio(line_data, aggregate, products)
    local producing_ratio = 0  ---@type number
    local priority_key = line_data.priority_item and structures.pack_item(line_data.priority_item)

    for _, product in ipairs(products) do
        local demand = aggregate.ingredients[structures.pack_item(product)]  ---@type number?
        local ratio = (demand or 0) / product.amount

        if structures.pack_item(product) == priority_key then
            return ratio  -- the priority product paces the line by itself
        else  -- satisfy every demand, so take the highest ratio
            producing_ratio = math.max(producing_ratio, ratio)
        end
    end

    return producing_ratio
end

--- A consuming line is paced by the byproducts available to its ingredients
---@param line_data LineData
---@param aggregate SolverAggregate
---@param ingredients SolverItem[]
---@return number
local function determine_consuming_ratio(line_data, aggregate, ingredients)
    local consuming_ratio = 0  ---@type number
    local priority_key = line_data.priority_item and structures.pack_item(line_data.priority_item)

    for _, ingredient in pairs(ingredients) do
        local ingredient_key = structures.pack_item(ingredient)
        local available = aggregate.known_byproducts[ingredient_key] and aggregate.products[ingredient_key]  ---@type number?
        local fuel_key = line_data.fuel_item and structures.pack_item(line_data.fuel_item)
        local ratio = (available or 0) / ingredient.amount

        if ingredient_key == priority_key then
            -- The priority ingredient paces the line by itself, importing the others as needed
            return ratio

        elseif available == nil then
            -- Avoid importing additional ingredients if they are a consumed byproduct further up
            if aggregate.known_byproducts[structures.pack_item(ingredient)] then return 0 end

        elseif ingredient_key ~= fuel_key then
            -- stay within every byproduct's availability, so take the lowest ratio
            consuming_ratio = (consuming_ratio == 0) and ratio or math.min(consuming_ratio, ratio)
        end
    end

    return consuming_ratio
end

---@param line_data LineData
---@param aggregate SolverAggregate
---@param is_relevant_line boolean
---@return LineResult
local function solve_line(line_data, aggregate, is_relevant_line)
    local products = structures.map.list(line_data.products)
    local ingredients = structures.map.list(line_data.ingredients)

    -- Determine machine count
    -- Line data assumes a machine amount of 1, so production_ratio == machine_amount
    local machine_amount = 0.0
    if is_relevant_line then
        machine_amount = 1  -- calculate subfloors based on the demand of the relevant line
    elseif line_data.machine_requirement then
        machine_amount = line_data.machine_requirement.count
    else
        -- Determine the ratios for both production and consumption
        local producing_ratio = determine_producing_ratio(line_data, aggregate, products)
        local consuming_ratio = determine_consuming_ratio(line_data, aggregate, ingredients)

        -- The production / consumption mode can be determined by the selected priority item
        local pritority_key = line_data.priority_item and structures.pack_item(line_data.priority_item)
        local produce_priority = (pritority_key and line_data.products[pritority_key] ~= nil)
        local consume_priority = (pritority_key and line_data.ingredients[pritority_key] ~= nil)

        if produce_priority then
            machine_amount = producing_ratio
        elseif consume_priority then
            machine_amount = consuming_ratio
        else
            machine_amount = math.max(producing_ratio, consuming_ratio)
        end
    end

    -- Determine products/byproducts
    for _, product in ipairs(products) do
        local amount = product.amount * machine_amount
        local demand = aggregate.ingredients[structures.pack_item(product)] or 0

        if amount > demand then
            local overflow_amount = amount - demand
            structures.map.add(aggregate.products, product, overflow_amount)
            aggregate.known_byproducts[structures.pack_item(product)] = true
            amount = demand  -- desired amount
        end

        structures.map.subtract(aggregate.ingredients, product, amount)
    end

    -- Determine ingredients
    for _, ingredient in pairs(ingredients) do
        local amount = ingredient.amount * machine_amount
        local surplus = aggregate.products[structures.pack_item(ingredient)] or 0

        if amount > surplus then
            local requested_amount = amount - surplus
            structures.map.add(aggregate.ingredients, ingredient, requested_amount)
            amount = surplus
        end

        structures.map.subtract(aggregate.products, ingredient, amount)
    end

    -- Add the integer machine count to the aggregate so it can be displayed on the origin_line
    aggregate.machine_amount = aggregate.machine_amount + math.ceil(machine_amount - MAGIC_NUMBERS.margin_of_error)

    return {
        id = line_data.id,
        machine_amount = machine_amount
    }
end


-- ** TOP LEVEL **
---@alias SequentialSolverStatus "solved"

---@param factory_data FactoryData
---@param floor_id ObjectID
---@return FloorResult
function sequential_engine.solve_floor(factory_data, floor_id)
    -- Initialize aggregate with the top level items
    local aggregate = structures.aggregate.init(floor_id)
    local floor_data = factory_data.floor_data_map[floor_id]
    local line_results = {}  ---@type LineResultMap

    -- Add factory products/ingredients to the floor to simulate demand/supply from outside the factory
    if floor_data.level == 1 then
        for _, product in pairs(factory_data.products) do
            structures.map.add(aggregate.ingredients, product)
        end
        for _, ingredient in pairs(factory_data.ingredients) do
            structures.map.add(aggregate.products, ingredient)
        end
    end

    -- Solve the floor sequentially, top to bottom
    for i, line_object_id in ipairs(floor_data.line_ids) do
        -- Update aggregate according to the current line, which also adjusts the respective line object
        local line_data = factory_data.line_data_map[line_object_id]
        if line_data then
            local is_relevant_line = (floor_data.level > 1 and i == 1)
            line_results[line_object_id] = solve_line(line_data, aggregate, is_relevant_line)  -- updates aggregate
        end
    end

    -- Remove simulated demand/supply
    if floor_data.level == 1 then
        for _, product in pairs(factory_data.products) do
            structures.map.subtract(aggregate.ingredients, product)
        end
        for _, ingredient in pairs(factory_data.ingredients) do
            structures.map.subtract(aggregate.products, ingredient)
        end
    end

    -- Re-balance products and ingredients after tampering with simulated quantities
    structures.map.reduce_items(aggregate.products, aggregate.ingredients, true)

    return {
        status = "solved",
        id = floor_id,
        products = aggregate.products,
        ingredients = aggregate.ingredients,
        line_result_map = line_results
    }
end

return sequential_engine
