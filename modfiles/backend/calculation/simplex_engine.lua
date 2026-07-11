---@namespace Simplex
local SimplexTableau = require("backend.calculation.SimplexTableau")

--- Matrix solver based on the simplex method
local simplex_engine = {}


---@alias PrototypeName string
---@alias ItemList table<PrototypeName, number>
---@alias ItemSet table<PrototypeName, true>
---@alias FloorResultTable table<ObjectID, FloorResult>
---@alias SolverState "solved" | "unbounded" | "no-solution"

---@class LineData
---@field line_id ObjectID
---@field products ItemList
---@field ingredients ItemList

---@class FloorResult

---@class LineResult


---@TODO: Move this to a better place. Maybe let the user configure it
-- Negative score represents a cost
local score_vector = {
    product = 0,
    intermediate = -1,
    ingredient = -1
}


---@param player LuaPlayer
---@param factory Factory
function simplex_engine.solve(player, factory)

    -- Solve floors
    local target_items = {}  ---@type ItemList
    for item in factory:iterator() do
        target_items[item.proto.name] = item.required_amount
    end
    simplex_engine.solve_floor(player, factory, factory.top_floor, target_items)

    -- Update GUI
    simplex_engine.update_factory(factory)
end


---@param player LuaPlayer
---@param factory Factory
---@param floor Floor
---@param target_items ItemList?
---@return FloorResultTable? result_table Containins the results of this floor and all subfloors, keyed by floor ID
function simplex_engine.solve_floor(player, factory, floor, target_items)
    local result = {}  ---@type FloorResult
    local result_table = {}  ---@type FloorResultTable
    local line_data_table = {}  ---@type LineData[]

    -- Check early exit conditions
    if not floor.first or (floor.level > 1 and
            (floor.first.valid or not floor.first.active or not floor.first:get_surface_compatibility())) then
        return nil
    end

    -- Iterate through lines and subfloors collecting line data and floor results
    for line_object in floor:iterator() do
        local data = nil

        if line_object.class == "Floor" then
            local subfloor_result_map = simplex_engine.solve_floor(player, factory, line_object)
            if subfloor_result_map then
                result_table = lib.table.union(result_table, subfloor_result_map)
                data = simplex_engine.get_line_data_from_floor(line_object, subfloor_result_map)
            end
        elseif line_object.class == "Line" then
            data = simplex_engine.get_line_data(player, factory, line_object)
        end

        if data then table.insert(line_data_table, data) end
    end

    log("\n.line_data = " .. serpent.block(line_data_table, {sortkeys = false}))  ---@TODO: remove

    -- Populate the item sets based on the line data
    local products = {}  ---@type ItemSet
    local ingredients = {}  ---@type ItemSet

    for _, line_data in pairs(line_data_table) do
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
    if not target_items then
        target_items = {}
        local k, _ = next(products)
        if not k then k = next(intermediates) end
        ---@cast k -nil
        target_items[k] = 1
    end

    -- Create the simplex tableau
    local tableau = SimplexTableau:init()

    -- Add line variables to the tableau
    for _, line_data in pairs(line_data_table) do
        tableau:add_line_variable(line_data)
    end

    -- Add slack variables for products
    for item_key, _ in pairs(products) do
        -- Target items have equality constraints. They don't need slack
        if not target_items[item_key] then
            tableau:add_item_variable(item_key, 1, score_vector.product)
        end
    end

    -- Add slack variables for intermediates
    ---@TODO: Find a way to let the user select whether an intermediate should be imported or exported
    --- For now, treat it as an ingredient (import if not enough)
    for item_key, _ in pairs(intermediates) do
        -- Target items have equality constraints. They don't need slack
        if not target_items[item_key] then
            tableau:add_item_variable(item_key, -1, score_vector.intermediate)
        end
    end

    -- Add slack variables for ingredients
    for item_key, _ in pairs(ingredients) do
        -- Target items have equality constraints. They don't need slack
        if not target_items[item_key] then
            tableau:add_item_variable(item_key, -1, score_vector.ingredient)
        end
    end

    log("\n.tableau = " .. serpent.block(tableau, {sortkeys = false}))  ---@TODO: remove

    result_table = lib.table.union({[floor.id] = result}, result_table)
    return result_table
end


---@param factory Factory
function simplex_engine.update_factory(factory)
    for item in factory:iterator() do
        item.amount = 0
    end
    simplex_engine.update_floor(factory.top_floor)
end


---@param floor Floor
function simplex_engine.update_floor(floor)
    for _, item in pairs(floor.products) do
        item.amount = 0
    end
    for _, item in pairs(floor.byproducts) do
        item.amount = 0
    end
    for _, item in pairs(floor.ingredients) do
        item.amount = 0
    end
    for line_object in floor:iterator() do
        if line_object.class == "Floor" then
            simplex_engine.update_floor(line_object)
        elseif line_object.class == "Line" then
            simplex_engine.update_line(line_object)
        end
    end
end

---@param line Line
function simplex_engine.update_line(line)
    line.machine.amount = 0
    for _, item in pairs(line.products) do
        item.amount = 0
    end
    for _, item in pairs(line.byproducts) do
        item.amount = 0
    end
    for _, item in pairs(line.ingredients) do
        item.amount = 0
    end
    if line.machine.fuel then
        line.machine.fuel.amount = 0
    end
end


--- Applies all effects on the machine of the line and returns how many
--- products/ingredients are produced/consumed per second by one machine.
--- Positive values represent products, while negative values represent ingredients.
--- Emmisions, fuel, power and heat are also included.
---@param player LuaPlayer
---@param factory Factory
---@param line Line
---@return LineData?
function simplex_engine.get_line_data(player, factory, line)
    local products = {}  ---@type ItemList
    local ingredients = {}  ---@type ItemList

    -- Check early exit conditions
    if not line.valid or not line.active or not line:get_surface_compatibility() then
        return nil
    end

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
            lib.table.add(products, item.name, amount)
        end
    end

    -- Get catalysts
    if line.recipe.proto.catalysts then
        for _, item in pairs(line.recipe.proto.catalysts.products) do
            local amount = total_crafts * solver.util.determine_prodded_amount(item, effects)
            lib.table.add(products, item.name, amount)
        end
        for _, item in pairs(line.recipe.proto.catalysts.ingredients) do
            local name = line.recipe:get_name_with_temperature(item)
            local amount = total_crafts * item.amount * line.machine:get_resource_drain_rate()
            lib.table.add(ingredients, name, amount)
        end
    end

    -- Get simple ingredients
    if line.recipe.proto.ingredients then
        for _, item in pairs(line.recipe.proto.ingredients) do
            local name = line.recipe:get_name_with_temperature(item)
            local amount = total_crafts * item.amount * line.machine:get_resource_drain_rate()
            lib.table.add(ingredients, name, amount)
        end
    end

    -- Get emissions
    local fuel_proto = line.machine.fuel and line.machine.fuel.proto  ---@as FPFuelPrototype?
    local energy_usage = line.machine:get_energy_usage()
    local pollutant_type = lib.globals.preferences(player).calculate_emissions and factory.parent.location_proto.pollutant_type or nil
    local power, emissions = solver.util.determine_power_and_emissions(line.machine.proto, line.recipe.proto,
    fuel_proto, 1, energy_usage, effects, pollutant_type)

    if pollutant_type and emissions then
        lib.table.add(products, pollutant_type, emissions)
    end

    -- Get fuel/power/heat energy requirements
    if line.machine.proto.energy_type == "burner" and fuel_proto then
        ---@cast line.machine.proto.burner -nil
        local amount = solver.util.determine_fuel_amount(power, line.machine.proto.burner, fuel_proto.fuel_value)
        lib.table.add(ingredients, fuel_proto.name, amount)
    elseif line.machine.proto.energy_type == "electric" then
        lib.table.add(ingredients, "custom-electric-power", power)
    elseif line.machine.proto.energy_type == "heat" then
        lib.table.add(ingredients, "custom-heat-power", power)
    end

    -- Get beacon power
    local beacon_power = line.beacon and line.beacon:get_total_power() or 0
    if beacon_power > 0 then
        lib.table.add(ingredients, "custom-electric-power", beacon_power)
    end

    -- Get heat requirements (frozen planets)
    if factory.parent.location_proto.entities_require_heating and line.machine.proto.heating_energy > 0 then
        lib.table.add(ingredients, "custom-heat-power", -line.machine.proto.heating_energy)
    end

    return {
        line_id = line.id,
        products = products,
        ingredients = ingredients,
    }
end


--- Converts the floor into a pseudo-machine based on the solver results
---@param floor Floor
---@param result_map FloorResultTable
---@return LineData?
function simplex_engine.get_line_data_from_floor(floor, result_map)
    if not result_map[floor.id] then return nil end
end


return simplex_engine