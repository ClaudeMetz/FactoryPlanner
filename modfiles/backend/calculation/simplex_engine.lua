local SimplexTableau = require("backend.calculation.SimplexTableau")
local structures = require("backend.calculation.structures")

--- Matrix solver based on the simplex method
local simplex_engine = {}


---@alias PrototypeKey string  "`<proto.name>`_`<proto.type>`"
---@alias SimplexItemList table<PrototypeKey, number>
---@alias SimplexItemSet table<PrototypeKey, true>
---@alias LineMetadataTable table<ObjectID, LineMetadata>

---@class LineMetadata
---@field line_id ObjectID
---@field floor_id ObjectID
---@field products SimplexItemList
---@field ingredients SimplexItemList
---@field total_crafts number
---@field machine_limit number?
---@field machine_force_limit boolean?
---@field fuel_ratio number?  how much of an ingredient is for fuel (treat as 1 if nil)


---@TODO: Move this to a better place. Maybe let the user configure it
-- The objective function is maximized, so positive values indicate a score,
-- and negative values indicate a cost
local objective_vector = {
    target_product = 1e9,
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


---@param key PrototypeKey
---@return number
local function item_cost(key)
    if string.sub(key, -6, -1) == "_fluid" then return objective_vector.fluid_modifier end
    if string.sub(key, -7, -1) == "_entity" then return objective_vector.special_modifier end
    return 1
end


---@param factory_data FactoryData
function simplex_engine.solve(factory_data)
    -- Get floor metadata
    local line_metadata_table = simplex_engine.get_floor_metadata(factory_data.top_floor)

    -- Create the simplex tableau of the factory
    local tableau = simplex_engine.create_tableau( factory_data.top_floor, line_metadata_table, true)

    -- Solve the tableau
    local result = tableau and tableau:solve()

    -- Update GUI
    simplex_engine.update_factory(factory_data, line_metadata_table, result)
end


---@param floor_data FloorData
---@param line_metadata_table LineMetadataTable
---@param is_top_level boolean?
---@return SimplexTableau? tableau
---@return SimplexItemSet? products
---@return SimplexItemSet? ingredients
function simplex_engine.create_tableau(floor_data, line_metadata_table, is_top_level)
    local relevant_line_metadata = {}  ---@type LineMetadataTable
    local tableau_table = {}  ---@type table<ObjectID, SimplexTableau>
    local products = {}  ---@type SimplexItemSet
    local ingredients = {}  ---@type SimplexItemSet
    local product_subfloors = {}  ---@type table<PrototypeKey, ObjectID[]>
    local ingredient_subfloors = {}  ---@type table<PrototypeKey, ObjectID[]>

    -- Recursively solve subfloors and add their results to the line data
    for _, line_object_data in pairs(floor_data.lines) do
        if line_object_data.subfloor then
            local subfloor_tableau, subfloor_products, subfloor_ingredients = simplex_engine.create_tableau(line_object_data.subfloor, line_metadata_table)
            if subfloor_tableau then tableau_table[line_object_data.id] = subfloor_tableau end
            if subfloor_products then
                for item_key, _ in pairs(subfloor_products) do
                    product_subfloors[item_key] = product_subfloors[item_key] or {}
                    table.insert(product_subfloors[item_key], line_object_data.id)
                end
            end
            if subfloor_ingredients then
                for item_key, _ in pairs(subfloor_ingredients) do
                    ingredient_subfloors[item_key] = ingredient_subfloors[item_key] or {}
                    table.insert(ingredient_subfloors[item_key], line_object_data.id)
                end
            end
        else
            relevant_line_metadata[line_object_data.id] = line_metadata_table[line_object_data.id]
        end
    end

    -- Populate the item sets based on the line data
    for _, line_data in pairs(relevant_line_metadata) do
        for item_key, value in pairs(line_data.products) do
            if value > 0 then products[item_key] = true end
        end
        for item_key, value in pairs(line_data.ingredients) do
            if value > 0 then ingredients[item_key] = true end
        end
    end

    -- Add subfloor products if they are used on this floor
    for item_key, floor_ids in pairs(product_subfloors) do
        if products[item_key] or ingredients[item_key] or #floor_ids >= 2 or #(ingredient_subfloors[item_key] or {}) >= 2 then
            products[item_key] = true
            product_subfloors[item_key] = nil
        end
    end

    -- Add subfloor ingredients if they are used on this floor
    for item_key, floor_ids in pairs(ingredient_subfloors) do
        if products[item_key] or ingredients[item_key] or #floor_ids >= 2 or #(product_subfloors[item_key] or {}) >= 2 then
            ingredients[item_key] = true
            ingredient_subfloors[item_key] = nil
        end
    end

    -- Add items that transfer between subfloors
    for item_key, floor_ids in pairs(product_subfloors) do
        if ingredient_subfloors[item_key] and floor_ids[1] ~= ingredient_subfloors[item_key][1] then
            products[item_key] = true
            ingredients[item_key] = true
            product_subfloors[item_key] = nil
            ingredient_subfloors[item_key] = nil
        end
    end

    local intermediates = lib.table.intersection(products, ingredients)  ---@type SimplexItemSet

    -- Do not continue if the floor can't produce anything.
    if not next(products) and not next(product_subfloors) then return end

    -- Create the simplex tableau
    local tableau = SimplexTableau:init()

    -- Add line variables to the tableau
    for _, line_data in pairs(relevant_line_metadata) do
        tableau:add_line_variable(line_data)
    end

    -- Add slack variables for products
    for item_key, _ in pairs(products) do
        if not intermediates[item_key] then
            local objective = item_cost(item_key) * objective_vector.product
            tableau:add_item_variable(item_key, floor_data.id, "out", objective)
        end
    end

    -- Add slack variables for intermediates
    for item_key, _ in pairs(intermediates) do
        local c = item_cost(item_key)
        tableau:add_item_variable(item_key, floor_data.id, "in", c * objective_vector.intermediate_in)
        tableau:add_item_variable(item_key, floor_data.id, "out", c * objective_vector.intermediate_out)
    end

    -- Add slack variables for ingredients
    for item_key, _ in pairs(ingredients) do
        if not intermediates[item_key] then
            local objective = item_cost(item_key) * objective_vector.ingredient
            tableau:add_item_variable(item_key, floor_data.id, "in", objective)
        end
    end

    for subfloor_id, subfloor_tableau in pairs(tableau_table) do
        -- Merge the subfloor tableau into this one
        tableau:merge(subfloor_tableau)

        -- Allow importing from the subfloor
        for item_key, _ in pairs(products) do
            local objective = item_cost(item_key) * objective_vector.floor_transfer_out
            tableau:add_item_transfer(item_key, floor_data.id, subfloor_id, "out", objective)
        end

        -- Allow exporting to the subfloor
        for item_key, _ in pairs(ingredients) do
            local objective = item_cost(item_key) * objective_vector.floor_transfer_in
            tableau:add_item_transfer(item_key, floor_data.id, subfloor_id, "in", objective)
        end
    end

    -- Add direct floor transfers without adding additional constraints to the tableau
    for item_key, floor_ids in pairs(product_subfloors) do
        local objective = item_cost(item_key) * (objective_vector.floor_transfer_out +
                ((ingredient_subfloors[item_key] and objective_vector.intermediate_out) or objective_vector.product))
        tableau:mark_equality(item_key, floor_ids[1]--[[@cast -nil]], floor_data.id, "out", objective)
    end
    for item_key, floor_ids in pairs(ingredient_subfloors) do
        local objective = item_cost(item_key) * (objective_vector.floor_transfer_in +
                ((product_subfloors[item_key] and objective_vector.intermediate_in) or objective_vector.ingredient))
        tableau:mark_equality(item_key, floor_ids[1]--[[@cast -nil]], floor_data.id, "in", objective)
    end

    -- Add additional constraint to target products, so we get a bounded solution
    if is_top_level then
        for _, item in pairs(floor_data.products) do  ---@cast item SolverItem
            local item_key = item.name .. "_" .. item.type
            local objective = item_cost(item_key) * objective_vector.target_product
            tableau:add_item_constraint(item_key, floor_data.id, "out", "<=", item.amount, objective)
        end
    end

    -- Add additional constraint for limited ingredients
    ---@TODO: implement limited ingredients
    for _, item in pairs({}) do  ---@cast item SolverItem
        local item_key = item.name .. "_" .. item.type
        local objective = item_cost(item_key) * objective_vector.limited_ingredient
        tableau:add_item_constraint(item_key, floor_data.id, "in", "<=", item.amount, objective)
    end

    -- Add aditional constraint for machine limits
    for line_id, line_data in pairs(relevant_line_metadata) do
        if line_data.machine_limit then
            local type = line_data.machine_force_limit and "==" or "<="
            tableau:add_line_constraint(line_id, type, line_data.machine_limit, objective_vector.machine_limit)
        end
    end

    -- Add subfloor items to the item lists
    for item_key, _ in pairs(product_subfloors) do products[item_key] = true end
    for item_key, _ in pairs(ingredient_subfloors) do ingredients[item_key] = true end

    return tableau, products, ingredients
end


-- Iterate through lines and subfloors collecting line data
---@param floor_data FloorData
---@return LineMetadataTable
function simplex_engine.get_floor_metadata(floor_data)
    local line_data_table = {}  ---@type LineMetadataTable

    for _, line_object_data in pairs(floor_data.lines) do
        if line_object_data.subfloor then
            local subfloor_data = simplex_engine.get_floor_metadata(line_object_data.subfloor)
            if subfloor_data then line_data_table = lib.table.union(line_data_table, subfloor_data) end
        else
            local line_data = simplex_engine.get_line_data(line_object_data, floor_data.id)
            if line_data then line_data_table[line_data.line_id] = line_data end
        end
    end

    return line_data_table
end


--- Applies all effects on the machine of the line and returns how many
--- products/ingredients are produced/consumed per second by one machine.
--- Positive values represent products, while negative values represent ingredients.
--- Emmisions, fuel, power and heat are also included.
---@param line_data LineData
---@param floor_id ObjectID
---@return LineMetadata?
function simplex_engine.get_line_data(line_data, floor_id)
    local products = {}  ---@type SimplexItemList
    local ingredients = {}  ---@type SimplexItemList

    -- Get amount of crafts in 1 second
    local speed_multiplier = line_data.machine_speed * (1 + (line_data.total_effects.speed / MAGIC_NUMBERS.effect_precision))
    local energy = (line_data.recipe_energy > MAGIC_NUMBERS.minimum_energy) and line_data.recipe_energy or MAGIC_NUMBERS.minimum_energy
    local total_crafts = speed_multiplier / energy

    -- Get simple products
    if line_data.recipe_proto.products then
        for _, item in pairs(line_data.recipe_proto.products) do
            local amount = total_crafts * solver.util.determine_prodded_amount(item, line_data.total_effects)
            lib.table.add(products, item.name .. "_" .. item.type, amount)
        end
    end

    -- Get simple ingredients
    for _, item in pairs(line_data.ingredients) do
        local amount = item.amount * total_crafts * (item.type ~= "fluid" and line_data.resource_drain_rate or 1)
        lib.table.add(ingredients, item.name .. "_" .. item.type, amount)
    end

    -- Get power and emissions
    local power, emissions = solver.util.determine_power_and_emissions(line_data, 1, total_crafts)

    -- Get fuel/power/heat energy requirements
    local fuel_amount = 0.0
    local power_amount = 0.0
    local heat_amount = 0.0
    if line_data.machine_proto.energy_type == "burner" and line_data.fuel_proto then
        ---@cast line_data.machine_proto.burner -nil
        fuel_amount = fuel_amount + solver.util.determine_fuel_amount(line_data, power, 1)
    elseif line_data.machine_proto.energy_type == "electric" then
        power_amount = power_amount + power
    elseif line_data.machine_proto.energy_type == "heat" then
        heat_amount = heat_amount + power
    end

    -- Get beacon power
    power_amount = power_amount + (line_data.beacon_power or 0)

    -- Get heat requirements (frozen surfaces e.g. Aquillo)
    if line_data.entities_require_heating then
        heat_amount = heat_amount + line_data.machine_proto.heating_energy
    end

    -- Add fuel to the ingredients
    local fuel_ratio = nil
    if line_data.fuel_proto then
        local fuel_key = line_data.fuel_proto.name .. "_" .. line_data.fuel_proto.type
        local fuel_as_ingredient = ingredients[fuel_key] or 0
        lib.table.add(ingredients, fuel_key, fuel_amount)

        -- Add burnt result
        if line_data.fuel_proto.burnt_result then
            local burnt_result_key = line_data.fuel_proto.burnt_result .. "_item"
            lib.table.add(products, burnt_result_key, fuel_amount)
        end

        -- Add spent fluid
        if line_data.fuel_proto.spent_fluid then
            local spent_fluid_key = line_data.fuel_proto.spent_fluid.name .. "-" ..
                    line_data.fuel_proto.spent_fluid.temperature .. "_fluid"
            local spent_fluid_amount = fuel_amount * line_data.fuel_proto.spent_fluid.amount
            lib.table.add(products, spent_fluid_key, spent_fluid_amount)
        end

        -- Handle special case where fuel is also an ingredient
        if fuel_as_ingredient > 0 then
            fuel_ratio = fuel_amount / (fuel_amount + fuel_as_ingredient)
        end
    end

    -- Add other special categories
    if power_amount > 0 then lib.table.add(ingredients, "custom-electric-power_entity", power_amount) end
    if heat_amount > 0 then lib.table.add(ingredients, "custom-heat-power_entity", heat_amount) end
    if line_data.pollutant_type and emissions ~= 0 then
        if emissions > 0 then
            lib.table.add(products, "custom-" .. line_data.pollutant_type .. "_entity", emissions)
        else
            lib.table.add(ingredients, "custom-" .. line_data.pollutant_type .. "_entity", -emissions)
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


---@param key PrototypeKey
---@param amount number?
---@return SolverItem
local function string_to_item(key, amount)
    local split = string.find(key, "_", 1, true) or 0

    return {
        name = string.sub(key, 1, split - 1),
        type = split and string.sub(key, split + 1, -1) or "",
        amount = amount or 0
    }
end


---@param factory_data FactoryData
---@param line_metadata_table LineMetadataTable
---@param result SimplexResult?
function simplex_engine.update_factory(factory_data, line_metadata_table, result)
    local top_products = {}  ---@type SimplexItemSet
    local top_byproducts = {}  ---@type SimplexItemList

    local product_result = structures.class.init()
    local byproduct_result = structures.class.init()
    local ingredient_result = structures.class.init()

    for _, product in pairs(factory_data.top_floor.products) do
        top_products[product.name .. "_" .. product.type] = true
    end

    if result and result.floor_results[factory_data.top_floor.id] then
        -- Update the products
        for item_key, amount in pairs(result.floor_results[factory_data.top_floor.id].products) do
            if top_products[item_key] then
                -- Update product amount
                structures.class.add(product_result, string_to_item(item_key, amount))
            else
                -- Add to byproducts
                top_byproducts[item_key] = amount
                structures.class.add(byproduct_result, string_to_item(item_key, amount))
            end
        end

        -- Update the ingredients
        for item_key, amount in pairs(result.floor_results[factory_data.top_floor.id].ingredients) do
            structures.class.add(ingredient_result, string_to_item(item_key, amount))
        end
    end

    simplex_engine.update_floor(factory_data.player_index, factory_data.top_floor, top_byproducts, line_metadata_table, result)

    solver.set_factory_result{
        player_index = factory_data.player_index,
        factory_id = factory_data.factory_id,
        Product = product_result,
        Byproduct = byproduct_result,
        Ingredient = ingredient_result
    }
end


---@param player_index integer
---@param floor_data FloorData
---@param byproducts SimplexItemList
---@param line_metadata_table LineMetadataTable
---@param result SimplexResult?
---@return integer machine_amount
function simplex_engine.update_floor(player_index, floor_data, byproducts, line_metadata_table, result)
    local machine_amount = 0.0

    for _, line_object_data in pairs(floor_data.lines) do
        local line_result = result and result.line_results[line_object_data.id]
        if not line_object_data.subfloor then
            machine_amount = machine_amount + simplex_engine.update_line(player_index, floor_data.id,
                    line_object_data, byproducts, line_metadata_table, line_result)
        else
            local floor_result = result and result.floor_results[line_object_data.id] or {
                floor_id = line_object_data.id,
                products = {},
                ingredients = {},
            }

            local product_result, byproduct_result, ingredient_result, floor_byproducts =
                    simplex_engine.update_line_object_common(1, floor_result.products, byproducts, floor_result.ingredients)
            local floor_machine_amount = simplex_engine.update_floor(player_index,
                    line_object_data.subfloor, floor_byproducts, line_metadata_table, result)

            solver.set_line_result{
                player_index = player_index,
                floor_id = floor_data.id,
                line_id = line_object_data.id,
                machine_amount = floor_machine_amount,
                Product = product_result,
                Byproduct = byproduct_result,
                Ingredient = ingredient_result
            }

            machine_amount = machine_amount + floor_machine_amount
        end
    end

    return math.ceil(machine_amount - MAGIC_NUMBERS.margin_of_error)
end


---@param player_index integer
---@param floor_id ObjectID
---@param line_data LineData
---@param byproducts SimplexItemList
---@param line_metadata_table LineMetadataTable
---@param result SimplexLineResult?
---@return number machine_amount
function simplex_engine.update_line(player_index, floor_id, line_data, byproducts, line_metadata_table, result)
    local data = line_metadata_table[line_data.id]
    if not data then return 0 end
    local products = lib.flib.shallow_copy(data.products)
    local ingredients = lib.flib.shallow_copy(data.ingredients)

    -- Update the machine
    local machine_amount = result and result.machine_amount or 0
    local production_ratio = machine_amount > 0 and data.total_crafts or 0
    local fuel_amount = 0.0

    -- Update the fuel
    if line_data.fuel_proto then
        for item_key, amount in pairs(ingredients) do
            if item_key == line_data.fuel_proto.name .. "_" .. line_data.fuel_proto.type then
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
        Product = product_result,
        Byproduct = byproduct_result,
        Ingredient = ingredient_result,
        fuel_amount = fuel_amount,
    }

    return machine_amount
end


---@param machine_amount number
---@param products SimplexItemList
---@param byproducts SimplexItemList
---@param ingredients SimplexItemList
---@return SolverClass products
---@return SolverClass byproducts
---@return SolverClass ingredients
---@return SimplexItemList floor_byproducts
function simplex_engine.update_line_object_common(machine_amount, products, byproducts, ingredients)
    local floor_byproducts = {}  ---@type SimplexItemList

    local product_result = structures.class.init()
    local byproduct_result = structures.class.init()
    local ingredient_result = structures.class.init()

    -- Update the products and byproducts
    for item_key, v in pairs(products) do
        local amount = v * machine_amount
        local item = string_to_item(item_key, amount)
        if not byproducts[item_key] then
            structures.class.add(product_result, item)
        else
            -- Add as byproduct
            local min_amount = math.min(byproducts[item_key], amount)
            item.amount = min_amount
            structures.class.add(byproduct_result, item)
            floor_byproducts[item_key] = min_amount

            -- Calculate item remainder
            local product_amount = lib.math.safe_sub(amount, min_amount)
            if product_amount > 0 then
                item.amount = product_amount
                structures.class.add(product_result, item)
            end

            -- Calculate byproduct remainder
            byproducts[item_key] = lib.math.safe_sub(byproducts[item_key], min_amount)
            if byproducts[item_key] == 0 then byproducts[item_key] = nil end
        end
    end

    -- Update the ingredients
    for item_key, v in pairs(ingredients) do
        local amount = v * machine_amount
        local item = string_to_item(item_key, amount)

        structures.class.add(ingredient_result, item)
    end

    return product_result, byproduct_result, ingredient_result, floor_byproducts
end


return simplex_engine
