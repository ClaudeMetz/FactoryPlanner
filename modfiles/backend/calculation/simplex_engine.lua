local SimplexTableau = require("backend.calculation.SimplexTableau")
local structures = require("backend.calculation.structures")
local util = require("__core__.lualib.util")

--- Matrix solver based on the simplex method
local simplex_engine = {}

---@alias SimplexItemList table<SolverItemKey, number>
---@alias SimplexItemSet table<SolverItemKey, true>
---@alias LineMetadataTable table<ObjectID, LineMetadata>

---@class LineMetadata
---@field line_id ObjectID
---@field floor_id ObjectID
---@field products SimplexItemList
---@field ingredients SimplexItemList
---@field total_crafts number?
---@field machine_limit number?
---@field machine_force_limit boolean?
---@field fuel_ratio number?  how much of an ingredient is for fuel (treat as 1 if nil)


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
    special_modifier = 1e-12,
}


---@param key SolverItemKey
---@return number
local function item_cost(key)
    local item = structures.unpack_item(key)
    if item.type == "fluid" then return objective_vector.fluid_modifier end
    if item.type == "entity" then return objective_vector.special_modifier end
    return 1
end

---@param factory_data FactoryData
function simplex_engine.solve(factory_data)
    -- Get floor metadata
    local line_metadata_table = simplex_engine.get_floor_metadata(factory_data.top_floor)

    -- Invalidate the floor in context cache
    local cache_invalid_map = {}  ---@type table<ObjectID, true>
    local player = game.get_player(factory_data.player_index)  ---@as LuaPlayer
    local context_floor = lib.context.get(player, "Floor")
    if context_floor then cache_invalid_map[context_floor.id] = true end

    -- Solve each floor recursively
    local result = simplex_engine.solve_floor( factory_data.top_floor, line_metadata_table, 1, factory_data.simplex_basis, cache_invalid_map)

    -- Update GUI
    simplex_engine.update_factory(factory_data, line_metadata_table, result)
end

---@param floor_data FloorData
---@param line_metadata_table LineMetadataTable
---@param level integer
---@param previous_basis table<ConstraintKey, VariableKey>
---@param cache_invalid_map table<ObjectID, true>
---@return SimplexResult?
function simplex_engine.solve_floor(floor_data, line_metadata_table, level, previous_basis, cache_invalid_map)
    local relevant_line_metadata = {}  ---@type LineMetadata[]
    local products = {}  ---@type SimplexItemSet
    local ingredients = {}  ---@type SimplexItemSet
    local cycled_intermediates = {}  ---@type SimplexItemSet
    local cache_invalid = cache_invalid_map[floor_data.id]
    local result  ---@type SimplexResult?

    -- Recursively solve subfloors and add their results to the line data
    for _, line_object_data in pairs(floor_data.lines) do
        if line_object_data.subfloor then
            local partial_result = simplex_engine.solve_floor(line_object_data.subfloor, line_metadata_table, level + 1, previous_basis, cache_invalid_map)
            result = util.merge({result or {}, partial_result})  ---@as SimplexResult?
            cache_invalid = cache_invalid or (result and result.cache_invalid)

            -- Add line metadata for this floor based on the results
            local floor_result = partial_result and partial_result.floor_results[line_object_data.id]
            if floor_result then
                line_metadata_table[line_object_data.id] = {
                    floor_id = floor_data.id,
                    line_id = line_object_data.id,
                    products = floor_result.products,
                    ingredients = floor_result.ingredients
                }
            end
        end

        table.insert(relevant_line_metadata, line_metadata_table[line_object_data.id])
    end

    -- Do not continue if the floor is empty (sanity check)
    if not next(relevant_line_metadata) then return end

    -- Populate the item sets based on the line data
    for _, line_data in pairs(relevant_line_metadata) do
        for item_key, _ in pairs(line_data.products) do
            products[item_key] = true
        end
        for item_key, _ in pairs(line_data.ingredients) do
            ingredients[item_key] = true
            if products[item_key] then cycled_intermediates[item_key] = true end
        end
    end

    local intermediates = solver.util.table.intersection(products, ingredients)  ---@type SimplexItemSet

    -- Do not continue if the floor can't produce anything (sanity check)
    if not next(products) then return end

    -- Create the simplex tableau
    local tableau = SimplexTableau:init()

    -- Add line variables to the tableau
    for _, line_metadata in pairs(relevant_line_metadata) do
        tableau:add_line_variable(line_metadata)
    end

    -- Add slack variables for products
    for item_key, _ in pairs(products) do
        if not intermediates[item_key] then
            local objective = item_cost(item_key) * objective_vector.product
            tableau:add_item_variable(item_key, floor_data.id, "out", objective)
        end
    end

    -- Add exporty slack variables for intermediates
    for item_key, _ in pairs(intermediates) do
        local c = item_cost(item_key)
        tableau:add_item_variable(item_key, floor_data.id, "out", c * objective_vector.intermediate_out)
    end

    -- Add import slack variables for cycled intermediates
    for item_key, _ in pairs(cycled_intermediates) do
        local c = item_cost(item_key)
        tableau:add_item_variable(item_key, floor_data.id, "in", c * objective_vector.intermediate_in)
    end

    -- Add slack variables for ingredients
    for item_key, _ in pairs(ingredients) do
        if not intermediates[item_key] then
            local objective = item_cost(item_key) * objective_vector.ingredient
            tableau:add_item_variable(item_key, floor_data.id, "in", objective)
        end
    end

    if level == 1 then
        -- Add additional constraint to target products, so we get a bounded solution
        for _, item in pairs(floor_data.products) do  ---@cast item SolverItem
            local item_key = structures.pack_item(item)
            local objective = item_cost(item_key) * objective_vector.target_product
            tableau:add_item_constraint(item_key, floor_data.id, "out", "==", item.amount, objective)
        end

        -- Add additional constraint for limited ingredients
        -- TODO: implement limited ingredients
        for _, item in pairs({}) do  ---@cast item SolverItem
            local item_key = structures.pack_item(item)
            local objective = item_cost(item_key) * objective_vector.limited_ingredient
            tableau:add_item_constraint(item_key, floor_data.id, "in", "==", item.amount, objective)
        end

        -- Add aditional constraint for machine limits
        for line_id, line_metadata in pairs(relevant_line_metadata) do
            if line_metadata.machine_limit then
                local type = line_metadata.machine_force_limit and "==" or "<="
                tableau:add_line_constraint(line_id, type, line_metadata.machine_limit, objective_vector.machine_limit)
            end
        end
        for _, line_object_data in pairs(floor_data.lines) do
            if line_object_data.subfloor then
                local top_line_data = line_object_data.subfloor.lines[1]
                if top_line_data and top_line_data.machine_limit and top_line_data.machine_limit.limit then
                    local type = top_line_data.machine_limit.force_limit and "==" or "<="
                    tableau:add_line_constraint(line_object_data.id, type, top_line_data.machine_limit.limit, objective_vector.machine_limit)
                end
            end
        end
    else
        -- Artificially limit the top line to one machine so we get a solution for this subfloor
        local _, line_metadata = next(relevant_line_metadata)  ---@cast line_metadata -nil
        tableau:add_line_constraint(line_metadata.line_id, "==", 1, objective_vector.target_machine)
    end

    -- Solve the tableau
    local tableau_result = tableau:solve(not cache_invalid and previous_basis or {})

    return util.merge({result or {}, tableau_result})  ---@as SimplexResult?
end

-- Iterate through lines and subfloors collecting line data
---@param floor_data FloorData
---@return LineMetadataTable
function simplex_engine.get_floor_metadata(floor_data)
    local line_metadata_table = {}  ---@type LineMetadataTable

    for _, line_object_data in pairs(floor_data.lines) do
        if line_object_data.subfloor then
            local subfloor_data = simplex_engine.get_floor_metadata(line_object_data.subfloor)
            if subfloor_data then line_metadata_table = solver.util.table.union(line_metadata_table, subfloor_data) end
        else
            local line_metadata = simplex_engine.get_line_metadata(line_object_data, floor_data.id)
            if line_metadata then line_metadata_table[line_metadata.line_id] = line_metadata end
        end
    end

    return line_metadata_table
end

--- Applies all effects on the machine of the line and returns how many
--- products/ingredients are produced/consumed per second by one machine.
--- Positive values represent products, while negative values represent ingredients.
--- Emmisions, fuel, power and heat are also included.
---@param line_data LineData
---@param floor_id ObjectID
---@return LineMetadata?
function simplex_engine.get_line_metadata(line_data, floor_id)
    local products = {}  ---@type SimplexItemList
    local ingredients = {}  ---@type SimplexItemList

    -- Get amount of crafts in 1 second
    local speed_multiplier = line_data.machine_speed * (1 + (line_data.total_effects.speed / MAGIC_NUMBERS.effect_precision))
    local energy = math.max(line_data.recipe_energy, MAGIC_NUMBERS.minimum_energy)
    local total_crafts = speed_multiplier / energy

    -- Get simple products
    for _, item in pairs(line_data.products) do
        local amount = total_crafts * solver.util.determine_prodded_amount(item, line_data.total_effects)
        solver.util.table.add(products, structures.pack_item(item), amount)
    end

    -- Get simple ingredients
    for _, item in pairs(line_data.ingredients) do
        local amount = item.amount * total_crafts * (item.type ~= "fluid" and line_data.resource_drain_rate or 1)
        solver.util.table.add(ingredients, structures.pack_item(item), amount)
    end

    local power = 0.0
    local emissions = 0.0

    local fuel_amount = 0.0
    local power_amount = 0.0
    local heat_amount = 0.0

    if energy > MAGIC_NUMBERS.minimum_energy then
        -- Get power and emissions
        power, emissions = solver.util.determine_power_and_emissions(line_data, 1, total_crafts)

        -- Get fuel/power/heat energy requirements
        if line_data.machine_proto.energy_type == "burner" and line_data.fuel_proto then
            ---@cast line_data.machine_proto.burner -nil
            fuel_amount = fuel_amount + solver.util.determine_fuel_amount(line_data, power, 1)
        elseif line_data.machine_proto.energy_type == "electric" then
            power_amount = power_amount + power
        elseif line_data.machine_proto.energy_type == "heat" then
            heat_amount = heat_amount + power
        end
    end

    -- Get beacon power
    power_amount = power_amount + (line_data.beacon_power or 0)

    -- Get heat requirements (frozen surfaces e.g. Aquillo)
    if line_data.entities_require_heating then
        heat_amount = heat_amount + line_data.machine_proto.heating_energy
    end

    -- Add fuel to the ingredients
    local fuel_ratio = nil
    local burner = line_data.machine_proto.burner
    if burner then
        ---@cast line_data.fuel_proto -nil
        ---@cast line_data.fuel_name -nil
        local fuel = {
            name = line_data.fuel_proto.name,
            type = line_data.fuel_proto.type,
            amount = 0
        }  ---@type SolverItem
        local fuel_key = structures.pack_item(fuel)
        local fuel_as_ingredient = ingredients[fuel_key] or 0
        solver.util.table.add(ingredients, fuel_key, fuel_amount)

        -- Add burnt result
        if line_data.fuel_proto.burnt_result then
            local burnt_result = {
                name = line_data.fuel_proto.burnt_result,
                type = "item",
                amount = 0
            }  ---@type SolverItem
            local burnt_result_key = structures.pack_item(burnt_result)
            solver.util.table.add(products, burnt_result_key, fuel_amount)
        end

        -- Add spent fluid
        local spent_fluid = burner.produces_spent_fluid and (burner.spent_fluid or line_data.fuel_proto.spent_fluid)
        if spent_fluid then
            local spent_fluid = {
                name = spent_fluid.name,
                type = "fluid",
                temperature = spent_fluid.temperature,
                amount = 0
            }  ---@type SolverItem
            local spent_fluid_key = structures.pack_item(spent_fluid)
            local spent_fluid_amount = fuel_amount * spent_fluid.amount
            solver.util.table.add(products, spent_fluid_key, spent_fluid_amount)
        end

        -- Handle special case where fuel is also an ingredient
        if fuel_as_ingredient > 0 then
            fuel_ratio = fuel_amount / (fuel_amount + fuel_as_ingredient)
        end
    end

    -- Add other special categories
    if power_amount > 0 then
        local item = { name = "custom-electric-power", type = "entity", amount = 0 }  ---@as SolverItem
        local item_key = structures.pack_item(item)
        solver.util.table.add(ingredients, item_key, power_amount)
    end
    if heat_amount > 0 then
        local item = { name = "custom-heat-power", type = "entity", amount = 0 }  ---@as SolverItem
        local item_key = structures.pack_item(item)
        solver.util.table.add(ingredients, item_key, heat_amount)
    end
    if line_data.pollutant_type and emissions ~= 0 then
        local item = { name = "custom-" .. line_data.pollutant_type, type = "entity", amount = 0 }  ---@as SolverItem
        local item_key = structures.pack_item(item)
        if emissions > 0 then
            solver.util.table.add(products, item_key, emissions)
        else
            solver.util.table.add(ingredients, item_key, -emissions)
        end
    end

    return {
        line_id = line_data.id,
        floor_id = floor_id,
        products = products,
        ingredients = ingredients,
        total_crafts = total_crafts,
        machine_limit = line_data.machine_limit.limit,
        machine_force_limit = line_data.machine_limit.force_limit,
        fuel_ratio = fuel_ratio
    }  ---@type LineMetadata
end

---@param factory_data FactoryData
---@param line_metadata_table LineMetadataTable
---@param result SimplexResult?
function simplex_engine.update_factory(factory_data, line_metadata_table, result)
    local top_products = {}  ---@type SimplexItemSet
    local top_byproducts = {}  ---@type SimplexItemList

    local product_result = {}  ---@type SolverMap
    local byproduct_result = {}  ---@type SolverMap
    local ingredient_result = {}  ---@type SolverMap

    for _, product in pairs(factory_data.top_floor.products) do
        top_products[structures.pack_item(product)] = true
    end

    if result and result.floor_results[factory_data.top_floor.id] then
        -- Update the products
        for item_key, amount in pairs(result.floor_results[factory_data.top_floor.id].products) do
            if top_products[item_key] then
                -- Update product amount
                structures.map.add(product_result, structures.unpack_item(item_key, amount))
            else
                -- Add to byproducts
                top_byproducts[item_key] = amount
                structures.map.add(byproduct_result, structures.unpack_item(item_key, amount))
            end
        end

        -- Update the ingredients
        for item_key, amount in pairs(result.floor_results[factory_data.top_floor.id].ingredients) do
            structures.map.add(ingredient_result, structures.unpack_item(item_key, amount))
        end
    end

    simplex_engine.update_floor(factory_data.player_index, factory_data.top_floor, 1, top_byproducts, line_metadata_table, result)

    solver.set_factory_result{
        player_index = factory_data.player_index,
        factory_id = factory_data.factory_id,
        products = product_result,
        byproducts = byproduct_result,
        ingredients = ingredient_result,
        simplex_basis = result and result.basis
    }
end

---@param player_index integer
---@param floor_data FloorData
---@param scale_factor number
---@param byproducts SimplexItemList
---@param line_metadata_table LineMetadataTable
---@param result SimplexResult?
---@return integer machine_amount
function simplex_engine.update_floor(player_index, floor_data, scale_factor, byproducts, line_metadata_table, result)
    local machine_amount = 0

    for _, line_object_data in pairs(floor_data.lines) do
        if not line_object_data.subfloor then
            local line_result = result and result.line_results[line_object_data.id]
            local line_machines = simplex_engine.update_line(player_index, floor_data.id,
                    line_object_data, scale_factor, byproducts, line_metadata_table, line_result)
            machine_amount = machine_amount + math.ceil(line_machines - MAGIC_NUMBERS.margin_of_error)
        else
            local subfloor_result = result and result.floor_results[line_object_data.id] or {
                floor_id = line_object_data.id,
                products = {},
                ingredients = {},
            }
            local line_result = result and result.line_results[line_object_data.id]
            local subfloor_scale_factor = (line_result and line_result.machine_amount or 0) * scale_factor

            local product_result, byproduct_result, ingredient_result, floor_byproducts =
                    simplex_engine.update_line_object_common(subfloor_scale_factor, subfloor_result.products, byproducts, subfloor_result.ingredients)
            local floor_machines = simplex_engine.update_floor(player_index,
                    line_object_data.subfloor, subfloor_scale_factor, floor_byproducts, line_metadata_table, result)

            solver.set_line_result{
                player_index = player_index,
                floor_id = floor_data.id,
                line_id = line_object_data.id,
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

---@param player_index integer
---@param floor_id ObjectID
---@param line_data LineData
---@param scale_factor number
---@param byproducts SimplexItemList
---@param line_metadata_table LineMetadataTable
---@param result SimplexLineResult?
---@return number machine_amount
function simplex_engine.update_line(player_index, floor_id, line_data, scale_factor, byproducts, line_metadata_table, result)
    local data = line_metadata_table[line_data.id]
    if not data then return 0 end
    local products = lib.flib.shallow_copy(data.products)
    local ingredients = lib.flib.shallow_copy(data.ingredients)

    -- Update the machine
    local machine_amount = result and scale_factor * result.machine_amount or 0
    local production_ratio = machine_amount * (data.total_crafts or 0)
    local fuel_amount = 0.0

    -- Update the fuel
    if line_data.fuel_proto then  ---@cast line_data.fuel_name -nil
        for item_key, amount in pairs(ingredients) do
            local fuel = {
                name = line_data.fuel_proto.name,
                type = line_data.fuel_proto.type,
                amount = 0
            }  ---@type SolverItem

            if item_key == structures.pack_item(fuel) then
                if data.fuel_ratio then
                    fuel_amount = machine_amount * amount * data.fuel_ratio
                    ingredients[item_key] = ingredients[item_key] * (1 - data.fuel_ratio)
                else
                    fuel_amount = machine_amount * amount
                    ingredients[item_key] = nil
                end
            end
        end
    end

    local product_result, byproduct_result, ingredient_result =
            simplex_engine.update_line_object_common(machine_amount, products, byproducts, ingredients)

    solver.set_line_result{
        player_index = player_index,
        line_id = line_data.id,
        floor_id = floor_id,
        machine_amount = machine_amount,
        production_ratio = production_ratio,
        products = product_result,
        byproducts = byproduct_result,
        ingredients = ingredient_result,
        fuel_amount = fuel_amount,
    }

    return machine_amount
end

---@param machine_amount number
---@param products SimplexItemList
---@param byproducts SimplexItemList
---@param ingredients SimplexItemList
---@return SolverMap products
---@return SolverMap byproducts
---@return SolverMap ingredients
---@return SimplexItemList floor_byproducts
function simplex_engine.update_line_object_common(machine_amount, products, byproducts, ingredients)
    local floor_byproducts = {}  ---@type SimplexItemList

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
            floor_byproducts[item_key] = min_amount

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
