local structures = require("backend.calculation.structures")

-- Contains the 'meat and potatoes' calculation model that struggles with some more complex setups
local sequential_engine = {}


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
---@param ingredients SolverItem[]
---@return number
local function determine_consuming_ratio(line_data, aggregate, ingredients)
    ---@param ingredient SolverItem
    ---@param available number
    ---@return number
    local function available_ratio(ingredient, available)
        return available / ingredient.amount
    end

    local production_ratio = 0  ---@type number

    for _, ingredient in pairs(ingredients) do
        local ingredient_key = structures.pack_item(ingredient)
        local available = aggregate.known_byproducts[ingredient_key] and aggregate.products[ingredient_key]  ---@type number?
        local fuel_key = line_data.fuel_item and structures.pack_item(line_data.fuel_item)

        if line_data.priority_item then
            -- The priority ingredient paces the line by itself, importing the others as needed
            if ingredient_key == structures.pack_item(line_data.priority_item) then
                if available == nil then return 0 end  -- nothing of it left to consume
                return available_ratio(ingredient, available)
            end

        elseif available == nil then
            -- Avoid importing additional ingredients if they are a consumed byproduct further up
            if aggregate.known_byproducts[structures.pack_item(ingredient)] then return 0 end

        elseif ingredient_key ~= fuel_key then
            -- stay within every byproduct's availability, so take the lowest ratio
            local ratio = available_ratio(ingredient, available)
            production_ratio = (production_ratio == 0) and ratio or math.min(production_ratio, ratio)
        end
    end

    return production_ratio
end


---@param line_data LineData
---@param aggregate SolverAggregate
---@param is_top_floor boolean
---@param is_relevant_line boolean
---@return LineResult
local function solve_line(line_data, aggregate, is_top_floor, is_relevant_line)
    local products = structures.map.list(line_data.products)
    local ingredients = structures.map.list(line_data.ingredients)
    local consuming = (line_data.production_type == "consume")

    -- Split the recipe's products by whether this floor has a demand for them
    local demanded_products, byproducts = {}, {}  ---@type SolverItem[], SolverItem[]
    for _, product in pairs(products) do
        local demanded = (aggregate.ingredients[structures.pack_item(product)] ~= nil)
        table.insert((demanded) and demanded_products or byproducts, product)
    end

    -- Determine machine count
    -- Line data assumes a machine amount of 1, so production_ratio == machine_amount
    local machine_amount = 0.0
    if is_relevant_line then
        machine_amount = 1  -- calculate subfloors based on the demand of the relevant line
    else
        machine_amount = (consuming) and determine_consuming_ratio(line_data, aggregate, ingredients)
            or determine_producing_ratio(line_data, aggregate, demanded_products)
    end

    -- Limit the machine amount
    if is_top_floor and line_data.machine_limit then
        machine_amount = line_data.machine_force_limit and line_data.machine_limit
            or math.min(machine_amount, line_data.machine_limit)
    end

    -- Determine byproducts
    for _, byproduct in pairs(byproducts) do
        local amount = byproduct.amount * machine_amount
        structures.map.add(aggregate.products, byproduct, amount)
        aggregate.known_byproducts[structures.pack_item(byproduct)] = true
    end

    -- Determine products
    for _, product in ipairs(demanded_products) do
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
---@alias SequentialSolverState "solved"

---@param factory_data FactoryData
---@param floor_id ObjectID
---@return FloorResult
function sequential_engine.solve_floor(factory_data, floor_id)
    -- Initialize aggregate with the top level items
    local aggregate = structures.aggregate.init(floor_id)
    local floor_data = factory_data.floor_data_map[floor_id]
    local line_results = {}  ---@type LineResultMap

    -- Add products to the floor ingredients to simulate demand from outside the factory
    if floor_data.level == 1 then
        for _, product in pairs(floor_data.products) do
            structures.map.add(aggregate.ingredients, product)
        end
    end

    -- Solve the floor sequentially, top to bottom
    for i, line_object_id in ipairs(floor_data.line_ids) do
        -- Update aggregate according to the current line, which also adjusts the respective line object
        local line_data = factory_data.line_data_map[line_object_id]
        local is_top_floor = (floor_data.level == 1)
        local is_relevant_line = (floor_data.level > 1 and i == 1)
        line_results[line_object_id] = solve_line(line_data, aggregate, is_top_floor, is_relevant_line)  -- updates aggregate
    end

    -- Remove simulated product demand
    if floor_data.level == 1 then
        for _, product in pairs(floor_data.products) do
            local ingredient_amount = aggregate.ingredients[structures.pack_item(product)] or 0  ---@type number
            if ingredient_amount < product.amount then
                local produced_amount = product.amount - ingredient_amount
                structures.map.subtract(aggregate.ingredients, product, ingredient_amount)
                structures.map.add(aggregate.products, product, produced_amount)
            else
                structures.map.subtract(aggregate.ingredients, product)
            end
        end
    end

    return {
        state = "solved",
        id = floor_id,
        products = aggregate.products,
        ingredients = aggregate.ingredients,
        line_result_map = line_results
    }
end

return sequential_engine
