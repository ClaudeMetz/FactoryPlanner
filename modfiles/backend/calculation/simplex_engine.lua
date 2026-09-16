local SimplexTableau = require("backend.calculation.SimplexTableau")
local structures = require("backend.calculation.structures")

--- Matrix solver based on the simplex method
local simplex_engine = {}


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
---@param floor_id ObjectID
---@return FloorResult?
function simplex_engine.solve_floor(factory_data, floor_id)
    local relevant_line_data = {}  ---@type LineData[]
    local products = {}  ---@type SolverSet
    local ingredients = {}  ---@type SolverSet
    local cycled_intermediates = {}  ---@type SolverSet
    local floor_data = factory_data.floor_data_map[floor_id]

    -- Consider only lines on this floor
    for _, line_object_id in ipairs(floor_data.line_ids) do
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
            tableau:add_item_variable(item_key, "export", objective)
        end
    end

    -- Add exporty slack variables for intermediates
    for item_key, _ in pairs(intermediates) do
        local objective = item_cost(item_key) * objective_vector.intermediate_out
        tableau:add_item_variable(item_key, "export", objective)
    end

    -- Add import slack variables for cycled intermediates
    for item_key, _ in pairs(cycled_intermediates) do
        local objective = item_cost(item_key) * objective_vector.intermediate_in
        tableau:add_item_variable(item_key, "import", objective)
    end

    -- Add slack variables for ingredients
    for item_key, _ in pairs(ingredients) do
        if not intermediates[item_key] then
            local objective = item_cost(item_key) * objective_vector.ingredient
            tableau:add_item_variable(item_key, "import", objective)
        end
    end

    if floor_data.level == 1 then
        -- Add additional variable and constraint to target products, so we get a bounded solution
        for _, item in pairs(floor_data.products) do  ---@cast item SolverItem
            local item_key = structures.pack_item(item)
            local objective = item_cost(item_key) * objective_vector.target_product
            tableau:add_item_variable(item_key, "desired_export", objective)
            tableau:add_item_constraint(item_key, "desired_export", "<=", item.amount, objective)
        end

        -- Add additional variable and constraint for limited ingredients
        -- TODO: implement limited ingredients
        for _, item in pairs({}) do  ---@cast item SolverItem
            local item_key = structures.pack_item(item)
            local objective = item_cost(item_key) * objective_vector.limited_ingredient
            tableau:add_item_variable(item_key, "desired_import", objective)
            tableau:add_item_constraint(item_key, "desired_import", "<=", item.amount, objective)
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
    return tableau:solve(floor_id, floor_data.simplex_basis)
end

return simplex_engine
