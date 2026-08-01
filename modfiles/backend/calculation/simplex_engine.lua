---@namespace Simplex
local SimplexTableau = require("backend.calculation.SimplexTableau")

--- Matrix solver based on the simplex method
local simplex_engine = {}


---@alias PrototypeKey string  "`<proto.name>`_`<proto.type>`"
---@alias ItemList table<PrototypeKey, number>
---@alias ItemSet table<PrototypeKey, true>
---@alias LineMetadataTable table<ObjectID, LineMetadata>

---@class LineMetadata
---@field line_id ObjectID
---@field floor_id ObjectID
---@field products ItemList
---@field ingredients ItemList
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
    local factory = OBJECT_INDEX[factory_data.factory_id]  ---@type Factory

    -- Get floor metadata
    local line_metadata_table = simplex_engine.get_floor_metadata(factory_data.top_floor)
    if not line_metadata_table then return end  -- sanity check

    -- Create the simplex tableau of the factory
    local tableau = simplex_engine.create_tableau( factory_data.top_floor, line_metadata_table, true)

    -- Solve the tableau
    local result = tableau and tableau:solve()

    -- Update GUI
    simplex_engine.update_factory(factory, line_metadata_table, result)
end


---@param floor_data FloorData
---@param line_metadata_table LineMetadataTable
---@param is_top_level boolean?
---@return SimplexTableau? tableau
---@return ItemSet? products
---@return ItemSet? ingredients
function simplex_engine.create_tableau(floor_data, line_metadata_table, is_top_level)
    local relevant_line_metadata = {}  ---@type LineMetadataTable
    local tableau_table = {}  ---@type table<ObjectID, SimplexTableau>
    local products = {}  ---@type ItemSet
    local ingredients = {}  ---@type ItemSet
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

    local intermediates = lib.table.intersection(products, ingredients)  ---@type ItemSet

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
---@return LineMetadataTable?
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
    local products = {}  ---@type ItemList
    local ingredients = {}  ---@type ItemList

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


---@param factory Factory
---@param line_data_table LineMetadataTable
---@param result SimplexResult?
function simplex_engine.update_factory(factory, line_data_table, result)
    local product_list = {}  ---@type table<PrototypeKey, TLProduct>
    local top_byproducts = {}  ---@type ItemList
    local top_ingredients = {}  ---@type ItemList

    -- Reset the satisfied amount
    for product in factory:iterator() do
        product_list[product.proto.name .. "_" .. product.proto.type] = product
        product.amount = 0
    end

    -- Reset top floor UI
    factory.top_floor.products = {}
    factory.top_floor.byproducts = {}
    factory.top_floor.ingredients = {}

    if result and result.floor_results[factory.top_floor.id] then
        -- Update the products
        for item_key, amount in pairs(result.floor_results[factory.top_floor.id].products) do
            if product_list[item_key] then
                -- Update product amount
                product_list[item_key].amount = amount
            else
                -- Add to byproducts
                local item = simplex_engine.string_to_item(item_key, amount)
                top_byproducts[item_key] = amount
                if item and (not item.proto.hidden or item.proto.special) then
                    table.insert(factory.top_floor.byproducts, item)
                end
            end
        end

        -- Update the ingredients
        for item_key, amount in pairs(result.floor_results[factory.top_floor.id].ingredients) do
            local item = simplex_engine.string_to_item(item_key, amount)
            top_ingredients[item_key] = amount
            if item and (not item.proto.hidden or item.proto.special) then
                table.insert(factory.top_floor.ingredients, item)
            end
        end

        -- Sort everything
        table.sort(factory.top_floor.byproducts, solver.item_comparator)
        table.sort(factory.top_floor.ingredients, solver.item_comparator)
    end

    simplex_engine.update_floor(factory.top_floor, top_byproducts, top_ingredients, line_data_table, result)
end


---@param floor Floor
---@param top_byproducts ItemList
---@param top_ingredients ItemList
---@param line_data_table LineMetadataTable
---@param result SimplexResult?
function simplex_engine.update_floor(floor, top_byproducts, top_ingredients, line_data_table, result)
    for line_object in floor:iterator() do
        local line_result = result and result.line_results[line_object.id]
        if line_object.class == "Line" then
            simplex_engine.update_line(line_object, top_byproducts, top_ingredients, line_data_table, line_result)
        elseif line_object.class == "Floor" then
            local floor_result = result and result.floor_results[line_object.id] or {
                floor_id = line_object.id,
                products = {},
                ingredients = {},
            }
            
            -- Reset line UI
            line_object.products = {}
            line_object.byproducts = {}
            line_object.ingredients = {}

            local floor_byproducts, floor_ingredients = simplex_engine.update_line_object_common(
                line_object, 1, floor_result.products, floor_result.ingredients, top_byproducts, top_ingredients)
            simplex_engine.update_floor(line_object, floor_byproducts, floor_ingredients, line_data_table, result)
        end
    end

    -- Calculate machine amount after everything on the floor has been updated
    floor.machine_amount = 0
    for line_object in floor:iterator() do
        local amount = 0
        if line_object.class == "Floor" then
            amount = line_object.machine_amount
        elseif line_object.class == "Line" then
            amount = math.ceil(line_object.machine.amount - MAGIC_NUMBERS.margin_of_error)
        end
        floor.machine_amount = floor.machine_amount + amount
    end
end


---@param line Line
---@param top_byproducts ItemList
---@param top_ingredients ItemList
---@param line_data_table LineMetadataTable
---@param line_result LineResult?
function simplex_engine.update_line(line, top_byproducts, top_ingredients, line_data_table, line_result)
    -- Reset line UI
    line.products = {}
    line.byproducts = {}
    line.ingredients = {}
    line.machine.amount = 0
    line.production_ratio = 0
    if line.machine.fuel then
        line.machine.fuel.amount = 0
    end

    local data = line_data_table[line.id]
    if not data then return end
    local products = lib.flib.shallow_copy(data.products)
    local ingredients = lib.flib.shallow_copy(data.ingredients)

    -- Update the machine
    if line_result then
        line.machine.amount = line_result.machine_amount
        line.production_ratio = line_result.machine_amount * data.total_crafts
    end

    -- Handle catalysts
    for item_key, product_amount in pairs(products) do
        if ingredients[item_key] then
            local ingredient_amount = ingredients[item_key]
            if product_amount > ingredient_amount then
                lib.table.add(products, item_key, -ingredient_amount)
                ingredients[item_key] = nil
            else
                lib.table.add(ingredients, item_key, -product_amount)
                products[item_key] = nil
            end
        end
    end

    -- Update the fuel
    if line.machine.fuel then
        local fuel = line.machine.fuel
        for item_key, amount in pairs(ingredients) do
            if item_key == fuel.proto.name .. "_" .. fuel.proto.type then
                if data.fuel_ratio then
                    fuel.amount = line.machine.amount * amount * data.fuel_ratio
                    ingredients[item_key] = ingredients[item_key] * (1 - data.fuel_ratio)
                else
                    fuel.amount = line.machine.amount * amount
                    ingredients[item_key] = nil
                end
            end
        end
    end

    simplex_engine.update_line_object_common( line, line.machine.amount, products, ingredients, top_byproducts, top_ingredients)
end


---@param line_object LineObject
---@param machine_amount number
---@param products ItemList
---@param ingredients ItemList
---@param top_byproducts ItemList
---@param top_ingredients ItemList
---@return ItemList floor_byproducts
---@return ItemList floor_ingredients
function simplex_engine.update_line_object_common(line_object, machine_amount, products, ingredients, top_byproducts, top_ingredients)
    local floor_byproducts = {}  ---@type ItemList
    local floor_ingredients = {}  ---@type ItemList
    local is_line = line_object.class == "Line"

    -- Update the products and byproducts
    for item_key, v in pairs(products) do
        local amount = v * machine_amount
        local item = simplex_engine.string_to_item(item_key, amount)
        if item and (not item.proto.hidden or ((item.proto.special or is_line) and amount > 0)) then
            if amount == 0 or not top_byproducts[item_key] then
                -- Add as product (used within the floor)
                table.insert(line_object.products, item)
            else
                -- Add as byproduct
                local min_amount = math.min(top_byproducts[item_key], amount)
                item.amount = min_amount
                table.insert(line_object.byproducts, item)
                floor_byproducts[item_key] = min_amount

                -- Calculate item remainder
                local product_amount = lib.math.safe_sub(amount, min_amount)
                if product_amount > 0 then
                    local product_item = simplex_engine.string_to_item(item_key, product_amount)
                    table.insert(line_object.products, product_item)
                end

                -- Calculate byproduct remainder
                top_byproducts[item_key] = lib.math.safe_sub(top_byproducts[item_key], min_amount)
                if top_byproducts[item_key] == 0 then top_byproducts[item_key] = nil end
            end
        end
    end

    -- Update the ingredients
    for item_key, v in pairs(ingredients) do
        local amount = v * machine_amount
        local item = simplex_engine.string_to_item(item_key, amount, true)
        if item and (not item.proto.hidden or ((item.proto.special or is_line) and amount > 0)) then
            table.insert(line_object.ingredients, item)
            floor_ingredients[item_key] = amount

            -- Update ingredient satisfaction
            if not top_ingredients[item_key] then
                item.satisfied_amount = amount
            else
                local min_amount = math.min(top_ingredients[item_key], amount)
                item.satisfied_amount = lib.math.safe_sub(amount, min_amount)

                -- Calculate top ingredient remainder
                top_ingredients[item_key] = lib.math.safe_sub(top_ingredients[item_key], min_amount)
                if top_ingredients[item_key] == 0 then top_ingredients[item_key] = nil end
            end
        end
    end

    -- Sort everything
    table.sort(line_object.products, solver.item_comparator)
    table.sort(line_object.byproducts, solver.item_comparator)
    table.sort(line_object.ingredients, solver.item_comparator)

    return floor_byproducts, floor_ingredients
end


---@param key PrototypeKey
---@param amount number?
---@param without_temperature boolean?
---@return SimpleItem?
function simplex_engine.string_to_item(key, amount, without_temperature)
    local split = string.find(key, "_", 1, true) or 0
    local name = string.sub(key, 1, split - 1)
    local type = split and string.sub(key, split + 1, -1) or nil
    local proto = prototyper.util.find("items", name, type)  ---@as FPItemPrototype?

    -- Convert to fluid without temperature if requested
    if proto and type == "fluid" and proto.base_name and without_temperature then
            proto = prototyper.util.find("items", proto.base_name, "fluid")  ---@as FPItemPrototype?
    end

    if proto then
        return {class = "SimpleItem", proto = proto, amount = amount or 0}  ---@as SimpleItem
    end
end


return simplex_engine