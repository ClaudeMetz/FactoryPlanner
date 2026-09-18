local SimplexTableau = require("backend.calculation.SimplexTableau")
local structures = require("backend.calculation.structures")
local util = require("__core__.lualib.util")

--- Matrix solver based on the simplex method
local simplex_engine = {}


-- @TODO: Move this to a better place. Maybe let the user configure it
-- The objective function is maximized, so positive values indicate a score,
-- and negative values indicate a cost
local objective_vector = {
    target_product = 1e9,
    target_machine = 1e9,
    limited_ingredient = 0,
    product = 0,
    ingredient = -0.001,
    intermediate_out = -1,
    intermediate_in = -1000,
    floor_transfer_out = 0,
    floor_transfer_in = 0,

    machine_limit = 0,
    fluid_modifier = 0.01,
    energy_modifier = 1e-9,
}


---@param key SolverItemKey
---@return number
local function item_cost(key)
    local item = structures.unpack_item(key)
    if item.type == "fluid" then return objective_vector.fluid_modifier end
    if item.type == "entity" and lib.is_special_power_item(item.name) then
        return objective_vector.energy_modifier
    end
    return 1
end

---@param factory_data FactoryData
function simplex_engine.solve(factory_data)
    -- Invalidate the floor in context cache
    local cache_invalid_map = {}  ---@type table<ObjectID, true>
    local player = game.get_player(factory_data.player_index)  ---@as LuaPlayer
    local context_floor = lib.context.get(player, "Floor")
    if context_floor then cache_invalid_map[context_floor.id] = true end

    -- Solve each floor recursively
    local result = simplex_engine.solve_floor(factory_data, factory_data.top_floor_id, cache_invalid_map)

    -- Update GUI
    simplex_engine.update_factory(factory_data, result)
end

---@param factory_data FactoryData
---@param floor_id ObjectID
---@param cache_invalid_map table<ObjectID, true>
---@return SimplexResult?
function simplex_engine.solve_floor(factory_data, floor_id, cache_invalid_map)
    local relevant_line_data = {}  ---@type LineData[]
    local products = {}  ---@type SolverSet
    local ingredients = {}  ---@type SolverSet
    local cycled_intermediates = {}  ---@type SolverSet
    local floor_data = factory_data.floor_data_map[floor_id]
    local cache_invalid = cache_invalid_map[floor_id]
    local result  ---@type SimplexResult?

    -- Recursively solve subfloors and add their results to the line data
    for _, line_object_id in pairs(floor_data.line_ids) do
        if factory_data.floor_data_map[line_object_id] then
            local partial_result = simplex_engine.solve_floor(factory_data, line_object_id, cache_invalid_map)
            result = util.merge({result or {}, partial_result})  ---@as SimplexResult?
            cache_invalid = cache_invalid or (result and result.cache_invalid)

            -- Add line data for this floor based on the results
            local floor_result = partial_result and partial_result.floor_results[line_object_id]
            if floor_result then
                local subfloor_data = factory_data.floor_data_map[line_object_id]
                local subfloor_line = factory_data.line_data_map[subfloor_data.line_ids[1]--[[@cast -nil]]]
                factory_data.line_data_map[line_object_id] = {
                    id = line_object_id,
                    floor_id = floor_id,
                    crafts_per_second = 1,
                    products = floor_result.products,
                    ingredients = floor_result.ingredients,
                    recipe_name = subfloor_line.recipe_name,
                    machine_limit = subfloor_line.machine_limit,
                    machine_force_limit = subfloor_line.machine_force_limit,
                    production_type = "produce"
                }
            end
        end

        table.insert(relevant_line_data, factory_data.line_data_map[line_object_id])
    end

    -- Do not continue if the floor is empty (sanity check)
    if not next(relevant_line_data) then return end

    -- Populate the item sets based on the line data
    for _, line_data in pairs(relevant_line_data) do
        for item_key, _ in pairs(line_data.products) do
            products[item_key] = true
        end
        for item_key, _ in pairs(line_data.ingredients) do
            ingredients[item_key] = true
            if products[item_key] then cycled_intermediates[item_key] = true end
        end
    end

    local intermediates = solver.util.set.intersection(products, ingredients)  ---@type SolverSet

    -- Do not continue if the floor can't produce anything (sanity check)
    if not next(products) then return end

    -- Create the simplex tableau
    local tableau = SimplexTableau:init()

    -- Add line variables to the tableau
    for _, line_data in pairs(relevant_line_data) do
        tableau:add_line_variable(line_data)
    end

    -- Add slack variables for products
    for item_key, _ in pairs(products) do
        if not intermediates[item_key] then
            local objective = item_cost(item_key) * objective_vector.product
            tableau:add_item_variable(item_key, floor_id, "export", objective)
        end
    end

    -- Add exporty slack variables for intermediates
    for item_key, _ in pairs(intermediates) do
        local objective = item_cost(item_key) * objective_vector.intermediate_out
        tableau:add_item_variable(item_key, floor_id, "export", objective)
    end

    -- Add import slack variables for cycled intermediates
    for item_key, _ in pairs(cycled_intermediates) do
        local objective = item_cost(item_key) * objective_vector.intermediate_in
        tableau:add_item_variable(item_key, floor_id, "import", objective)
    end

    -- Add slack variables for ingredients
    for item_key, _ in pairs(ingredients) do
        if not intermediates[item_key] then
            local objective = item_cost(item_key) * objective_vector.ingredient
            tableau:add_item_variable(item_key, floor_id, "import", objective)
        end
    end

    if floor_data.level == 1 then
        -- Add additional variable and constraint to target products, so we get a bounded solution
        for _, item in pairs(floor_data.products) do  ---@cast item SolverItem
            local item_key = structures.pack_item(item)
            if products[item_key] then
                local objective = item_cost(item_key) * objective_vector.target_product
                tableau:add_item_variable(item_key, floor_id, "output", objective)
                tableau:add_item_constraint(item_key, floor_id, "output", "<=", item.amount, objective)
            end
        end

        -- Add additional variable and constraint for limited ingredients
        -- TODO: implement limited ingredients
        for _, item in pairs({}) do  ---@cast item SolverItem
            local item_key = structures.pack_item(item)
            if ingredients[item_key] then
                local objective = item_cost(item_key) * objective_vector.limited_ingredient
                tableau:add_item_variable(item_key, floor_id, "input", objective)
                tableau:add_item_constraint(item_key, floor_id, "input", "<=", item.amount, objective)
            end
        end

        -- Add aditional constraint for machine limits
        for _, line_data in pairs(relevant_line_data) do
            if line_data.machine_limit then
                local type = line_data.machine_force_limit and "==" or "<="
                tableau:add_line_constraint(line_data.id, type, line_data.machine_limit, objective_vector.machine_limit)
            end
        end
    else
        -- Artificially limit the top line to one machine so we get a solution for this subfloor
        local _, line_data = next(relevant_line_data)  ---@cast line_data -nil
        tableau:add_line_constraint(line_data.id, "==", 1, objective_vector.target_machine)
    end

    -- Solve the tableau
    local tableau_result = tableau:solve(not cache_invalid and factory_data.simplex_basis or {})

    return util.merge({result or {}, tableau_result})  ---@as SimplexResult?
end

---@param factory_data FactoryData
---@param result SimplexResult?
function simplex_engine.update_factory(factory_data, result)
    local top_products = {}  ---@type SolverSet
    local top_byproducts = {}  ---@type SolverMap

    local product_result = {}  ---@type SolverMap
    local byproduct_result = {}  ---@type SolverMap
    local ingredient_result = {}  ---@type SolverMap

    local top_floor_data = factory_data.floor_data_map[factory_data.top_floor_id]
    for _, product in pairs(top_floor_data.products) do
        top_products[structures.pack_item(product)] = true
    end

    if result and result.floor_results[factory_data.top_floor_id] then
        -- Update the products
        for item_key, amount in pairs(result.floor_results[factory_data.top_floor_id].products) do
            if top_products[item_key] then
                -- Update product amount
                structures.map.add(product_result, structures.unpack_item(item_key, amount))
            else
                -- Add to byproducts
                structures.map.add(top_byproducts, structures.unpack_item(item_key, amount))
                structures.map.add(byproduct_result, structures.unpack_item(item_key, amount))
            end
        end

        -- Update the ingredients
        for item_key, amount in pairs(result.floor_results[factory_data.top_floor_id].ingredients) do
            structures.map.add(ingredient_result, structures.unpack_item(item_key, amount))
        end
    end

    simplex_engine.update_floor(factory_data, factory_data.top_floor_id, 1, top_byproducts, result)

    solver.set_factory_result{
        player_index = factory_data.player_index,
        factory_id = factory_data.factory_id,
        products = product_result,
        byproducts = byproduct_result,
        ingredients = ingredient_result,
        simplex_basis = result and result.basis
    }
end

---@param factory_data FactoryData
---@param floor_id ObjectID
---@param scale_factor number
---@param byproducts SolverMap
---@param result SimplexResult?
---@return integer machine_amount
function simplex_engine.update_floor(factory_data, floor_id, scale_factor, byproducts, result)
    local floor_data = factory_data.floor_data_map[floor_id]
    local machine_amount = 0

    for _, line_object_id in pairs(floor_data.line_ids) do
        if not factory_data.floor_data_map[line_object_id] then  -- Line
            local line_result = result and result.line_results[line_object_id]
            local line_data = factory_data.line_data_map[line_object_id]
            local line_machines = simplex_engine.update_line(floor_id, line_data, scale_factor, byproducts, line_result)
            machine_amount = machine_amount + math.ceil(line_machines - MAGIC_NUMBERS.margin_of_error)
        else  -- Floor
            local subfloor_result = result and result.floor_results[line_object_id] or {
                floor_id = line_object_id,
                products = {},
                ingredients = {},
            }
            local line_result = result and result.line_results[line_object_id]
            local subfloor_scale_factor = (line_result and line_result.machine_amount or 0) * scale_factor

            local product_result, byproduct_result, ingredient_result, floor_byproducts =
                    simplex_engine.update_line_object_common(subfloor_scale_factor, subfloor_result.products, byproducts, subfloor_result.ingredients)
            local floor_machines = simplex_engine.update_floor(factory_data, line_object_id, subfloor_scale_factor, floor_byproducts, result)

            solver.set_line_result{
                floor_id = floor_id,
                line_id = line_object_id,
                machine_amount = floor_machines,
                products = product_result,
                byproducts = byproduct_result,
                ingredients = ingredient_result
            }

            machine_amount = machine_amount + floor_machines
        end
    end

    return machine_amount
end

---@param floor_id ObjectID
---@param line_data LineData
---@param scale_factor number
---@param byproducts SolverMap
---@param result SimplexLineResult?
---@return number machine_amount
function simplex_engine.update_line(floor_id, line_data, scale_factor, byproducts, result)
    -- Update the machine
    local machine_amount = result and scale_factor * result.machine_amount or 0
    local production_ratio = machine_amount * line_data.crafts_per_second

    local product_result, byproduct_result, ingredient_result =
            simplex_engine.update_line_object_common(machine_amount, line_data.products, byproducts, line_data.ingredients)

    -- Update the fuel
    local fuel_amount
    if line_data.fuel_item then
        local fuel_key = structures.pack_item(line_data.fuel_item)
        fuel_amount = line_data.fuel_item.amount * machine_amount
        local ingredient_amount = ingredient_result[fuel_key] or 0
        if fuel_amount <= ingredient_amount then
            structures.map.subtract(ingredient_result, line_data.fuel_item, fuel_amount)
        else
            structures.map.add(product_result, line_data.fuel_item, fuel_amount - ingredient_amount)
            ingredient_result[fuel_key] = nil
        end
    end

    solver.set_line_result{
        line_id = line_data.id,
        floor_id = floor_id,
        machine_amount = machine_amount,
        crafts_per_second = production_ratio,
        products = product_result,
        byproducts = byproduct_result,
        ingredients = ingredient_result,
        fuel_amount = fuel_amount,
    }

    return machine_amount
end

---@param machine_amount number
---@param products SolverMap
---@param byproducts SolverMap
---@param ingredients SolverMap
---@return SolverMap products
---@return SolverMap byproducts
---@return SolverMap ingredients
---@return SolverMap floor_byproducts
function simplex_engine.update_line_object_common(machine_amount, products, byproducts, ingredients)
    local floor_byproducts = {}  ---@type SolverMap

    local product_result = {}  ---@type SolverMap
    local byproduct_result = {}  ---@type SolverMap
    local ingredient_result = {}  ---@type SolverMap

    -- Update the products and byproducts
    for item_key, v in pairs(products) do
        local amount = v * machine_amount
        local item = structures.unpack_item(item_key, amount)
        if not byproducts[item_key] then
            structures.map.add(product_result, item)
        else
            -- Add as byproduct
            local min_amount = math.min(byproducts[item_key], amount)
            item.amount = min_amount
            structures.map.add(byproduct_result, item)
            structures.map.add(floor_byproducts, item)

            -- Calculate item remainder
            local product_amount = solver.util.safe_sub(amount, min_amount)
            if product_amount > 0 then
                item.amount = product_amount
                structures.map.add(product_result, item)
            end

            -- Calculate byproduct remainder
            byproducts[item_key] = solver.util.safe_sub(byproducts[item_key], min_amount)
            if byproducts[item_key] == 0 then byproducts[item_key] = nil end
        end
    end

    -- Update the ingredients
    for item_key, v in pairs(ingredients) do
        local amount = v * machine_amount
        local item = structures.unpack_item(item_key, amount)

        structures.map.add(ingredient_result, item)
    end

    return product_result, byproduct_result, ingredient_result, floor_byproducts
end

return simplex_engine
