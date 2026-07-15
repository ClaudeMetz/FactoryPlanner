---@namespace Simplex
local SimplexTableau = require("backend.calculation.SimplexTableau")

--- Matrix solver based on the simplex method
local simplex_engine = {}


---@alias PrototypeKey string  "`<proto.name>`_`<proto.type>`"
---@alias ItemList table<PrototypeKey, number>
---@alias ItemSet table<PrototypeKey, true>
---@alias LineDataTable table<ObjectID, LineData>

---@class LineData
---@field line_id ObjectID
---@field floor_id ObjectID
---@field total_crafts number
---@field products ItemList
---@field ingredients ItemList
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
    special_modifier = 0  -- no penalty for emissions, power and heat
}


---@param player LuaPlayer
---@param factory Factory
function simplex_engine.solve(player, factory)
    -- Get floor data
    local line_data_table = simplex_engine.get_floor_data(player, factory, factory.top_floor, true)
    if not line_data_table then return end  -- sanity check

    -- Get user-defined top-level products
    local target_products = {}  ---@type ItemList
    for item in factory:iterator() do
        target_products[item.proto.name .. "_" .. item.proto.type] = item.required_amount
    end

    -- Get user-defined top-level ingredients
    local limited_ingredients = {}  ---@type ItemList
    ---@TODO: implement ingredient limits in GUI

    -- Create the simplex tableau of the factory
    local tableau = simplex_engine.create_tableau( factory.top_floor, line_data_table, target_products, limited_ingredients)

    -- Solve the tableau
    local result = tableau and tableau:solve()

    -- Update GUI
    simplex_engine.update_factory(factory, line_data_table, result)
end


---@param floor Floor
---@param line_data_table LineDataTable
---@param target_products ItemList?
---@param limited_ingredients ItemList?
---@return SimplexTableau? tableau
---@return ItemSet? products
---@return ItemSet? ingredients
function simplex_engine.create_tableau(floor, line_data_table, target_products, limited_ingredients)
    local relevant_line_data = {}  ---@type LineDataTable
    local tableau_table = {}  ---@type table<ObjectID, SimplexTableau>

    local products = {}  ---@type ItemSet
    local ingredients = {}  ---@type ItemSet

    -- Recursively solve subfloors and add their results to the line data
    for line_object in floor:iterator() do
        if line_object.class == "Line" then
            local line_data = line_data_table[line_object.id]
            if line_data and line_data.total_crafts > 0 then
                relevant_line_data[line_data.line_id] = line_data
            end
        elseif line_object.class == "Floor" then
            local subfloor_tableau, subfloor_products, subfloor_ingredients = simplex_engine.create_tableau(line_object, line_data_table)
            if subfloor_tableau then tableau_table[line_object.id] = subfloor_tableau end
            if subfloor_products then products = lib.table.union(products, subfloor_products) end
            if subfloor_ingredients then ingredients = lib.table.union(ingredients, subfloor_ingredients) end
        end
    end

    -- Populate the item sets based on the line data
    for _, line_data in pairs(relevant_line_data) do
        for item_key, value in pairs(line_data.products) do
            if value > 0 then products[item_key] = true end
        end
        for item_key, value in pairs(line_data.ingredients) do
            if value > 0 then ingredients[item_key] = true end
        end
    end

    local intermediates = lib.table.intersection(products, ingredients)  ---@type ItemSet

    -- Do not continue if the floor can't produce anything.
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
            local c = string.sub(item_key, -7, -1) == "_entity" and objective_vector.special_modifier or 1
            tableau:add_item_variable(item_key, floor.id, "out", c * objective_vector.product)
        end
    end

    -- Add slack variables for intermediates
    for item_key, _ in pairs(intermediates) do
        local c = string.sub(item_key, -7, -1) == "_entity" and objective_vector.special_modifier or 1
        tableau:add_item_variable(item_key, floor.id, "in", c * objective_vector.intermediate_in)
        tableau:add_item_variable(item_key, floor.id, "out", c * objective_vector.intermediate_out)
    end

    -- Add slack variables for ingredients
    for item_key, _ in pairs(ingredients) do
        if not intermediates[item_key] then
            local c = string.sub(item_key, -7, -1) == "_entity" and objective_vector.special_modifier or 1
            tableau:add_item_variable(item_key, floor.id, "in", c * objective_vector.ingredient)
        end
    end

    -- Add additional constraint to target products, so we get a bounded solution
    for item_key, amount in pairs(target_products or {}) do
        tableau:add_item_constraint(item_key, floor.id, "out", "<=", amount, objective_vector.target_product)
    end

    -- Add additional constraint for limited ingredients
    for item_key, amount in pairs(limited_ingredients or {}) do
        tableau:add_item_constraint(item_key, floor.id, "in", "<=", amount, objective_vector.limited_ingredient)
    end

    for line_id, line_data in pairs(relevant_line_data) do
        if line_data.machine_limit then
            local type = line_data.machine_force_limit and "==" or "<="
            tableau:add_line_constraint(line_id, type, line_data.machine_limit, objective_vector.machine_limit)
        end
    end

    for subfloor_id, subfloor_tableau in pairs(tableau_table) do
        -- Merge the subfloor tableau into this one
        tableau:merge(subfloor_tableau)

        -- Allow importing from the subfloor
        for item_key, _ in pairs(products) do
            tableau:add_item_transfer(item_key, floor.id, subfloor_id, "out", objective_vector.floor_transfer_out)
        end

        -- Allow exporting to the subfloor
        for item_key, _ in pairs(ingredients) do
            tableau:add_item_transfer(item_key, floor.id, subfloor_id, "in", objective_vector.floor_transfer_in)
        end
    end

    return tableau, products, ingredients
end


-- Iterate through lines and subfloors collecting line data
---@param player LuaPlayer
---@param factory Factory
---@param floor Floor
---@param active boolean
---@return LineDataTable?
function simplex_engine.get_floor_data(player, factory, floor, active)
    local line_data_table = {}  ---@type LineDataTable

    -- Check if floor can function
    active = active and floor.first and (floor.level == 1 or
            (floor.first.active and floor.first:get_surface_compatibility().overall)) and true or false

    for line_object in floor:iterator() do
        if line_object.class == "Floor" then
            local subfloor_data = simplex_engine.get_floor_data(player, factory, line_object, active)
            if subfloor_data then line_data_table = lib.table.union(line_data_table, subfloor_data) end
        elseif line_object.class == "Line" then
            local line_data = simplex_engine.get_line_data(player, factory, line_object, active)
            if line_data then line_data_table[line_data.line_id] = line_data end
        end
    end

    return line_data_table
end


--- Applies all effects on the machine of the line and returns how many
--- products/ingredients are produced/consumed per second by one machine.
--- Positive values represent products, while negative values represent ingredients.
--- Emmisions, fuel, power and heat are also included.
---@param player LuaPlayer
---@param factory Factory
---@param line Line
---@param active boolean
---@return LineData?
function simplex_engine.get_line_data(player, factory, line, active)
    local products = {}  ---@type ItemList
    local ingredients = {}  ---@type ItemList

    ---@TODO: Fix surface restricions being ignored

    -- Check if line can can function
    active = active and line.active and line:get_surface_compatibility().overall and true or false

    ---@cast line.machine.proto -FPPackedPrototype
    ---@cast line.recipe.proto -FPPackedPrototype

    -- Update all line effects
    line.recipe:update_effects(player.force--[[@as LuaForce]], factory)
    local effects = line.total_effects

    -- Get amount of crafts in 1 second
    local speed_multiplier = line.machine:get_speed() * (1 + (effects.speed / MAGIC_NUMBERS.effect_precision))
    local energy = (line.recipe.proto.energy > MAGIC_NUMBERS.minimum_energy) and line.recipe.proto.energy or MAGIC_NUMBERS.minimum_energy
    if line.machine.proto.prototype_category == "boiler" then
        energy = solver.util.determine_boiler_energy(line.recipe)
    end
    local total_crafts = active and speed_multiplier / energy or 0

    -- Get simple products
    if line.recipe.proto.products then
        for _, item in pairs(line.recipe.proto.products) do
            local amount = total_crafts * solver.util.determine_prodded_amount(item, effects)
            lib.table.add(products, item.name .. "_" .. item.type, amount)
        end
    end

    -- Get catalysts
    if line.recipe.proto.catalysts then
        for _, item in pairs(line.recipe.proto.catalysts.products) do
            local amount = total_crafts * solver.util.determine_prodded_amount(item, effects)
            lib.table.add(products, item.name .. "_" .. item.type, amount)
            lib.table.add(ingredients, item.name .. "_" .. item.type, amount)
        end
        for _, item in pairs(line.recipe.proto.catalysts.ingredients) do
            local name = line.recipe:get_name_with_temperature(item)
            local amount = total_crafts * item.amount * line.machine:get_resource_drain_rate()
            if not line.recipe:is_temperature_configured(item) then amount = 0 end
            lib.table.add(products, name .. "_" .. item.type, amount)
            lib.table.add(ingredients, name .. "_" .. item.type, amount)
        end
    end

    -- Get simple ingredients
    if line.recipe.proto.ingredients then
        for _, item in pairs(line.recipe.proto.ingredients) do
            local name = line.recipe:get_name_with_temperature(item)
            local amount = total_crafts * item.amount * line.machine:get_resource_drain_rate()
            if not line.recipe:is_temperature_configured(item) then amount = 0 end
            lib.table.add(ingredients, name .. "_" .. item.type, amount)
        end
    end

    -- Get emissions
    local fuel_proto = line.machine.fuel and line.machine.fuel.proto  ---@as FPFuelPrototype?
    local energy_usage = line.machine:get_energy_usage()
    local pollutant_type = lib.globals.preferences(player).calculate_emissions and factory.parent.location_proto.pollutant_type or nil
    local power, emissions = solver.util.determine_power_and_emissions(line.machine.proto, line.recipe.proto,
    fuel_proto, 1, energy_usage, effects, pollutant_type)

    -- Get fuel/power/heat energy requirements
    local fuel_amount = 0.0
    local power_amount = 0.0
    local heat_amount = 0.0
    if line.machine.proto.energy_type == "burner" and fuel_proto then
        ---@cast line.machine.proto.burner -nil
        fuel_amount = fuel_amount + solver.util.determine_fuel_amount(power, line.machine.proto.burner, fuel_proto.fuel_value)
    elseif line.machine.proto.energy_type == "electric" then
        power_amount = power_amount + power
    elseif line.machine.proto.energy_type == "heat" then
        heat_amount = heat_amount + power
    end

    -- Get beacon power
    local beacon_power = line.beacon and line.beacon:get_total_power() or 0
    if beacon_power > 0 then
        power_amount = power_amount + beacon_power
    end

    -- Get heat requirements (frozen surfaces e.g. Aquillo)
    if factory.parent.location_proto.entities_require_heating and line.machine.proto.heating_energy > 0 then
        heat_amount = heat_amount + line.machine.proto.heating_energy
    end

    -- Add fuel to the ingredients
    local fuel_ratio = nil
    if fuel_proto then
        local fuel_key = fuel_proto.name .. "_" .. fuel_proto.type
        local fuel_as_ingredient = ingredients[fuel_key] or 0
        lib.table.add(ingredients, fuel_key, active and fuel_amount or 0)

        -- Handle special case where fuel is also an ingredient
        if active and fuel_as_ingredient > 0 then
            fuel_ratio = fuel_amount / (fuel_amount + fuel_as_ingredient)
        end
    end

    -- Add other special categories
    if active and power_amount > 0 then lib.table.add(ingredients, "custom-electric-power_entity", power_amount) end
    if active and heat_amount > 0 then lib.table.add(ingredients, "custom-heat-power_entity", heat_amount) end
    if active and pollutant_type and emissions ~= 0 then
        if emissions > 0 then
            lib.table.add(products, "custom-" .. pollutant_type .. "_entity", emissions)
        else
            lib.table.add(ingredients, "custom-" .. pollutant_type .. "_entity", -emissions)
        end
    end

    -- Get machine limit
    local machine_limit = line.machine.limit
    local machine_force_limit = machine_limit and line.machine.force_limit

    return {
        line_id = line.id,
        floor_id = line.parent.id,
        total_crafts = active and total_crafts or 0,
        products = products,
        ingredients = ingredients,
        machine_limit = machine_limit,
        machine_force_limit = machine_force_limit,
        fuel_ratio = fuel_ratio
    }  ---@type LineData
end


---@param factory Factory
---@param line_data_table LineDataTable
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
---@param line_data_table LineDataTable
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
            line_object.machine_amount = 0

            local floor_byproducts, floor_ingredients = simplex_engine.update_line_object_common(
                line_object, 1, floor_result.products, floor_result.ingredients, top_byproducts, top_ingredients)
            simplex_engine.update_floor(line_object, floor_byproducts, floor_ingredients, line_data_table, result)
        end
    end

    -- Calculate machine amount after everything on the floor has been updated
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
---@param line_data_table LineDataTable
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
    local products = lib.flib.deep_copy(data.products)
    local ingredients = lib.flib.deep_copy(data.ingredients)

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