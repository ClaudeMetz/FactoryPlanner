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
---@field active boolean
---@field products ItemList
---@field ingredients ItemList
---@field fuel_ratio number?  how much of an ingredient is for fuel (treat as 1 if nil)


---@TODO: Move this to a better place. Maybe let the user configure it
-- The objective function is maximized, so positive values indicate a score,
-- and negative values indicate a cost
local objective_vector = {
    target_product = 1e9,
    product = 0,
    intermediate_out = -1,
    intermediate_in = -1000,
    ingredient = 0,

    special_modifier = 1e-9  -- reduce penalty for emissions, power and heat
}


---@param player LuaPlayer
---@param factory Factory
function simplex_engine.solve(player, factory)
    -- Get floor data
    local line_data_table = simplex_engine.get_floor_data(player, factory, factory.top_floor, true)
    if not line_data_table then return end  -- sanity check

    -- Solve floors
    local target_products = {}  ---@type ItemList
    for item in factory:iterator() do
        target_products[item.proto.name .. "_" .. item.proto.type] = item.required_amount
    end
    local result_table = simplex_engine.solve_floor( factory.top_floor, line_data_table, target_products)
    result_table = result_table or {}

    -- Update GUI
    simplex_engine.update_factory(factory, line_data_table, result_table)
end


---@param floor Floor
---@param line_data_table LineDataTable
---@param target_products ItemList?
---@return FloorResultTable? result_table Containins the results of this floor and all subfloors, keyed by floor ID
function simplex_engine.solve_floor(floor, line_data_table, target_products)
    local result_table = {}  ---@type FloorResultTable
    local relevant_line_data = {}  ---@type LineDataTable

    -- Recursively solve subfloors and add their results to the line data
    for line_object in floor:iterator() do
        local line_data = nil  ---@type LineData?

        if line_object.class == "Line" then line_data = line_data_table[line_object.id]
        elseif line_object.class == "Floor" then
            local subfloor_result_map = simplex_engine.solve_floor(line_object, line_data_table)
            if subfloor_result_map then
                result_table = lib.table.union(result_table, subfloor_result_map)
                line_data = simplex_engine.get_line_data_from_floor_results(line_object.id, subfloor_result_map)
            end
        end

        if line_data and line_data.active then relevant_line_data[line_data.line_id] = line_data end
    end

    -- Populate the item sets based on the line data
    local products = {}  ---@type ItemSet
    local ingredients = {}  ---@type ItemSet

    for _, line_data in pairs(relevant_line_data) do
        for item_key, _ in pairs(line_data.products) do
            products[item_key] = true
        end
        for item_key, _ in pairs(line_data.ingredients) do
            ingredients[item_key] = true
        end
    end

    local intermediates = lib.table.intersection(products, ingredients)  ---@type ItemSet
    products = lib.table.difference(products, intermediates)  ---@as ItemSet
    ingredients = lib.table.difference(ingredients, intermediates)  ---@as ItemSet

    -- Sanity check: It shouldn't be possible for the floor to only have lines containing ingredients
    if not next(products) and not next(intermediates) then return nil end

    -- If the target items were not specified, add the first product as the target
    if not target_products then
        target_products = {}
        local k, _ = next(products)
        if not k then k = next(intermediates) end
        ---@cast k -nil
        target_products[k] = 1
    end

    -- Create the simplex tableau
    local tableau = SimplexTableau:init()

    -- Add line variables to the tableau
    for _, line_data in pairs(relevant_line_data) do
        tableau:add_line_variable(line_data)
    end

    -- Add slack variables for products
    for item_key, _ in pairs(products) do
        local c = string.sub(item_key, -7, -1) == "_entity" and objective_vector.special_modifier or 1
        tableau:add_item_variable(item_key, "out", c * objective_vector.product)
    end

    -- Add slack variables for intermediates
    for item_key, _ in pairs(intermediates) do
        local c = string.sub(item_key, -7, -1) == "_entity" and objective_vector.special_modifier or 1
        tableau:add_item_variable(item_key, "in", c * objective_vector.intermediate_in)
        tableau:add_item_variable(item_key, "out", c * objective_vector.intermediate_out)
    end

    -- Add slack variables for ingredients
    for item_key, _ in pairs(ingredients) do
        local c = string.sub(item_key, -7, -1) == "_entity" and objective_vector.special_modifier or 1
        tableau:add_item_variable(item_key, "in", c * objective_vector.ingredient)
    end

    -- Add additional constraints to target products, so we get a bounded solution
    for item_key, amount in pairs(target_products) do
        tableau:add_item_constraint(item_key, "out", "<=", amount, objective_vector.target_product)
    end

    ---@TODO: Can add more constraints on the top level, like ingredient limits and machine limits

    -- Solve the tableau
    local result = tableau:solve(floor.id)

    if result.state == "solved" then result_table[floor.id] = result end
    return result_table
end


-- Iterate through lines and subfloors collecting line data
---@param player LuaPlayer
---@param factory Factory
---@param floor Floor
---@param enabled boolean
---@return LineDataTable?
function simplex_engine.get_floor_data(player, factory, floor, enabled)
    local result = {}  ---@type LineDataTable

    -- Check if floor can function
    local active = enabled and floor.first and (floor.level == 1 or
            (floor.first.active and floor.first:get_surface_compatibility())) and true or false

    for line_object in floor:iterator() do
        if line_object.class == "Floor" then
            local subfloor_result = simplex_engine.get_floor_data(player, factory, line_object, active)
            if subfloor_result then result = lib.table.union(result, subfloor_result) end
        elseif line_object.class == "Line" then
            local line_data = simplex_engine.get_line_data(player, factory, line_object, active)
            if line_data then result[line_data.line_id] = line_data end
        end
    end
    return result
end


--- Applies all effects on the machine of the line and returns how many
--- products/ingredients are produced/consumed per second by one machine.
--- Positive values represent products, while negative values represent ingredients.
--- Emmisions, fuel, power and heat are also included.
---@param player LuaPlayer
---@param factory Factory
---@param line Line
---@param enabled boolean
---@return LineData?
function simplex_engine.get_line_data(player, factory, line, enabled)
    local products = {}  ---@type ItemList
    local ingredients = {}  ---@type ItemList

    -- Check if line can can function
    local active = enabled and line.active and line:get_surface_compatibility() and true or false

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
    local total_crafts = speed_multiplier / energy

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
        end
        for _, item in pairs(line.recipe.proto.catalysts.ingredients) do
            local name = line.recipe:get_name_with_temperature(item)
            local amount = total_crafts * item.amount * line.machine:get_resource_drain_rate()
            lib.table.add(ingredients, name .. "_" .. item.type, amount)
        end
    end

    -- Get simple ingredients
    if line.recipe.proto.ingredients then
        for _, item in pairs(line.recipe.proto.ingredients) do
            local name = line.recipe:get_name_with_temperature(item)
            local amount = total_crafts * item.amount * line.machine:get_resource_drain_rate()
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
    if fuel_amount > 0 and fuel_proto then
        local fuel_key = fuel_proto.name .. "_" .. fuel_proto.type
        lib.table.add(ingredients, fuel_key, fuel_amount)

        -- Handle special case where fuel is also an ingredient
        if fuel_amount ~= ingredients[fuel_key] then
            fuel_ratio = fuel_amount / ingredients[fuel_key]
        end
    end

    -- Add other special categories
    if power_amount > 0 then lib.table.add(ingredients, "custom-electric-power_entity", power_amount) end
    if heat_amount > 0 then lib.table.add(ingredients, "custom-heat-power_entity", heat_amount) end
    if pollutant_type and emissions ~= 0 then
        if emissions > 0 then
            lib.table.add(products, "custom-" .. pollutant_type .. "_entity", emissions)
        else
            lib.table.add(ingredients, "custom-" .. pollutant_type .. "_entity", -emissions)
        end
    end

    return {
        line_id = line.id,
        active = active,
        products = products,
        ingredients = ingredients,
        fuel_ratio = fuel_ratio
    }
end


--- Converts the floor into a pseudo-machine based on the solver results
---@param floor_id ObjectID
---@param result_map FloorResultTable
---@return LineData?
function simplex_engine.get_line_data_from_floor_results(floor_id, result_map)
    if not result_map[floor_id] then return nil end
    return {
        line_id = floor_id,
        active = true,
        products = lib.flib.deep_copy(result_map[floor_id].products),
        ingredients = lib.flib.deep_copy(result_map[floor_id].ingredients)
    }  ---@type LineData
end


---@param factory Factory
---@param line_data_table LineDataTable
---@param result_table FloorResultTable
function simplex_engine.update_factory(factory, line_data_table, result_table)
    local product_list = {}  ---@type table<PrototypeKey, TLProduct>
    local top_byproducts = {}  ---@type ItemList

    -- Reset the satisfied amount
    for product in factory:iterator() do
        product_list[product.proto.name .. "_" .. product.proto.type] = product
        product.amount = 0
    end

    -- Reset top floor UI
    factory.top_floor.products = {}
    factory.top_floor.byproducts = {}
    factory.top_floor.ingredients = {}

    if result_table[factory.top_floor.id] then
        -- Update the products
        for item_key, amount in pairs(result_table[factory.top_floor.id].products) do
            if product_list[item_key] then
                -- Update product amount
                product_list[item_key].amount = amount
            else
                -- Add to byproducts
                top_byproducts[item_key] = amount
                local item = simplex_engine.string_to_item(item_key, amount)
                if item and (not item.proto.hidden or item.proto.special) then
                    table.insert(factory.top_floor.byproducts, item)
                end
            end
        end

        -- Update the ingredients
        for item_key, amount in pairs(result_table[factory.top_floor.id].ingredients) do
            local item = simplex_engine.string_to_item(item_key, amount)
            if item and (not item.proto.hidden or item.proto.special) then
                table.insert(factory.top_floor.ingredients, item)
            end
        end
    end

    -- Sort everything
    table.sort(factory.top_floor.byproducts, solver.item_comparator)
    table.sort(factory.top_floor.ingredients, solver.item_comparator)

    simplex_engine.update_floor(factory.top_floor, 1, top_byproducts, line_data_table, result_table)
end


---@param floor Floor
---@param scale_factor number
---@param top_byproducts ItemList
---@param line_data_table LineDataTable
---@param result_table FloorResultTable
function simplex_engine.update_floor(floor, scale_factor, top_byproducts, line_data_table, result_table)
    local top_ingredients = result_table[floor.id] and lib.flib.deep_copy(result_table[floor.id].ingredients) or {}

    for line_object in floor:iterator() do
        local line_result = result_table[floor.id] and result_table[floor.id].line_results[line_object.id]
        if line_object.class == "Line" then
            simplex_engine.update_line(line_object, scale_factor, top_byproducts, top_ingredients, line_data_table, line_result)
        elseif line_object.class == "Floor" then
            local c = line_result and line_result.machine_amount * scale_factor or 0
            local floor_byproducts = {}  ---@type ItemList
            local floor_result = result_table[line_object.id] or {
                floor_id = line_object.id,
                products = {},
                ingredients = {},
                line_results = {}
            }
            
            -- Reset line UI
            line_object.products = {}
            line_object.byproducts = {}
            line_object.ingredients = {}

            -- Update the products and byproducts
            for item_key, v in pairs(floor_result.products) do
                local amount = c * v
                local item = simplex_engine.string_to_item(item_key, amount)
                if item and (not item.proto.hidden or (item.proto.special and c > 0)) then
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
                        local product_amount = amount - min_amount
                        if product_amount > MAGIC_NUMBERS.double_margin_of_error then
                            local product_item = simplex_engine.string_to_item(item_key, product_amount)
                            table.insert(line_object.products, product_item)
                        end

                        -- Calculate byproduct remainder
                        top_byproducts[item_key] = top_byproducts[item_key] - min_amount
                        if top_byproducts[item_key] < MAGIC_NUMBERS.double_margin_of_error then top_byproducts[item_key] = nil end
                    end
                end
            end

            -- Update the ingredients
            for item_key, v in pairs(floor_result.ingredients) do
                local amount = c * v
                local item = simplex_engine.string_to_item(item_key, amount, true)
                if item and (not item.proto.hidden or (item.proto.special and c > 0)) then
                    table.insert(line_object.ingredients, item)

                    -- Update ingredient satisfaction
                    if not top_ingredients[item_key] then
                        item.satisfied_amount = amount
                    else
                        local min_amount = math.min(top_ingredients[item_key], amount)
                        item.satisfied_amount = amount - min_amount
                        if item.satisfied_amount < MAGIC_NUMBERS.double_margin_of_error then item.satisfied_amount = 0 end

                        -- Calculate top ingredient remainder
                        top_ingredients[item_key] = top_ingredients[item_key] - min_amount
                        if top_ingredients[item_key] < MAGIC_NUMBERS.double_margin_of_error then top_ingredients[item_key] = nil end
                    end
                end
            end

            -- Sort everything
            table.sort(line_object.products, solver.item_comparator)
            table.sort(line_object.byproducts, solver.item_comparator)
            table.sort(line_object.ingredients, solver.item_comparator)

            simplex_engine.update_floor(line_object, c, floor_byproducts, line_data_table, result_table)
        end
    end
end


---@param line Line
---@param scale_factor number
---@param top_byproducts ItemList
---@param top_ingredients ItemList
---@param line_data_table LineDataTable
---@param line_result LineResult?
function simplex_engine.update_line(line, scale_factor, top_byproducts, top_ingredients, line_data_table, line_result)
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
        line.machine.amount = scale_factor * line_result.machine_amount
        line.production_ratio = line.machine.amount > 0 and 1 or 0
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

    -- Update the products and byproducts
    for item_key, v in pairs(products) do
        local amount = line.machine.amount * v
        local item = simplex_engine.string_to_item(item_key, amount)
        if item and (line.production_ratio > 0 or not item.proto.special) then
            if amount == 0 or not top_byproducts[item_key] then
                -- Add as product (used within the floor)
                table.insert(line.products, item)
            else
                -- Add as byproduct
                local min_amount = math.min(top_byproducts[item_key], amount)
                item.amount = min_amount
                table.insert(line.byproducts, item)

                -- Calculate item remainder
                local product_amount = amount - min_amount
                if product_amount > MAGIC_NUMBERS.double_margin_of_error then
                    local product_item = simplex_engine.string_to_item(item_key, product_amount)
                    table.insert(line.products, product_item)
                end

                -- Calculate byproduct remainder
                top_byproducts[item_key] = top_byproducts[item_key] - min_amount
                if top_byproducts[item_key] < MAGIC_NUMBERS.double_margin_of_error then top_byproducts[item_key] = nil end
            end
        end
    end

    -- Update the ingredients
    for item_key, v in pairs(ingredients) do
        local amount = line.machine.amount * v
        local item = simplex_engine.string_to_item(item_key, amount, true)
        if item and (line.production_ratio > 0 or not item.proto.special) then
            table.insert(line.ingredients, item)

            -- Update ingredient satisfaction
            if not top_ingredients[item_key] then
                item.satisfied_amount = amount
            else
                local min_amount = math.min(top_ingredients[item_key], amount)
                item.satisfied_amount = amount - min_amount
                if item.satisfied_amount < MAGIC_NUMBERS.double_margin_of_error then item.satisfied_amount = 0 end

                -- Calculate top ingredient remainder
                top_ingredients[item_key] = top_ingredients[item_key] - min_amount
                if top_ingredients[item_key] < MAGIC_NUMBERS.double_margin_of_error then top_ingredients[item_key] = nil end
            end
        end
    end

    -- Sort everything
    table.sort(line.products, solver.item_comparator)
    table.sort(line.byproducts, solver.item_comparator)
    table.sort(line.ingredients, solver.item_comparator)
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
    if proto and type == "fluid" and without_temperature then
            proto = prototyper.util.find("items", proto.base_name, "fluid")  ---@as FPItemPrototype?
    end

    if proto then
        return {class = "SimpleItem", proto = proto, amount = amount or 0}  ---@as SimpleItem
    end
end


return simplex_engine