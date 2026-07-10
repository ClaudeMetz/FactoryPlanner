--- Matrix solver based on the simplex method
local simplex_engine = {}


---@alias PrototypeName string
---@alias ItemSet {PrototypeName: true}
---@alias SimplexItemList {PrototypeName: number}
---@alias SimplexFloorResultTable {ObjectID: SimplexFloorResult}
---@alias SimplexSolverState "solved" | "unbounded" | "no-solution"

---@class SimplexLineData
---@field line_id ObjectID
---@field items SimplexItemList

---@class SimplexFloorResult

---@class SimplexLineResult


local N = 1e100  -- big number


---@param player LuaPlayer
---@param factory Factory
function simplex_engine.solve(player, factory)

    -- Solve floors
    local target_items = {}  ---@type SimplexItemList
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
---@param target_items SimplexItemList?
---@return SimplexFloorResultTable? result_table  Containins the results of this floor and all subfloors, keyed by floor ID.
function simplex_engine.solve_floor(player, factory, floor, target_items)
    local product_set = {}  ---@type ItemSet
    local intermediate_set = {}  ---@type ItemSet
    local ingredient_set = {}  ---@type ItemSet
    local result_table = {}  ---@type SimplexFloorResultTable
    local result = {}
    local line_data_table = {}

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
                result_table = lib.table.join(result_table, subfloor_result_map)
                data = simplex_engine.get_line_data_from_floor(line_object, subfloor_result_map)
            end
        elseif line_object.class == "Line" then
            data = simplex_engine.get_line_data(player, factory, line_object)
        end

        if data then table.insert(line_data_table, data) end
    end

    log("\n.line_data = " .. serpent.block(line_data_table, {sortkeys = false}))

    result_table = lib.table.join({[floor.id] = result}, result_table)
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
--- Positive values represent products, while negative values represent ingredients
--- Emmisions, fuel, power and heat are also included.
---@param player LuaPlayer
---@param factory Factory
---@param line Line
---@return SimplexLineData?
function simplex_engine.get_line_data(player, factory, line)
    local items = {}  ---@type SimplexItemList

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
            lib.table.add(items, item.name, amount)
        end
    end

    -- Get catalysts
    if line.recipe.proto.catalysts then
        for _, item in pairs(line.recipe.proto.catalysts.products) do
            local amount = total_crafts * solver.util.determine_prodded_amount(item, effects)
            lib.table.add(items, item.name, amount)
        end
        for _, item in pairs(line.recipe.proto.catalysts.ingredients) do
            local name = line.recipe:get_name_with_temperature(item)
            local amount = total_crafts * item.amount * line.machine:get_resource_drain_rate()
            lib.table.add(items, name, -amount)
        end
    end

    -- Get simple ingredients
    if line.recipe.proto.ingredients then
        for _, item in pairs(line.recipe.proto.ingredients) do
            local name = line.recipe:get_name_with_temperature(item)
            local amount = total_crafts * item.amount * line.machine:get_resource_drain_rate()
            lib.table.add(items, name, -amount)
        end
    end

    -- Get emissions
    local fuel_proto = line.machine.fuel and line.machine.fuel.proto  ---@as FPFuelPrototype?
    local energy_usage = line.machine:get_energy_usage()
    local pollutant_type = lib.globals.preferences(player).calculate_emissions and factory.parent.location_proto.pollutant_type or nil
    local power, emissions = solver.util.determine_power_and_emissions(line.machine.proto, line.recipe.proto,
    fuel_proto, 1, energy_usage, effects, pollutant_type)

    if pollutant_type and emissions then
        lib.table.add(items, pollutant_type, -emissions)
    end

    -- Get fuel/heat
    if line.machine.proto.energy_type == "burner" and fuel_proto then
        ---@cast line.machine.proto.burner -nil
        local amount = solver.util.determine_fuel_amount(power, line.machine.proto.burner, fuel_proto.fuel_value)
        lib.table.add(items, fuel_proto.name, -amount)
    elseif line.machine.proto.energy_type == "electric" then
        lib.table.add(items, "custom-electric-power", -power)
    elseif line.machine.proto.energy_type == "heat" then
        lib.table.add(items, "custom-heat-power", -power)
    end

    -- Get beacon power
    local beacon_power = line.beacon and line.beacon:get_total_power() or 0
    if beacon_power > 0 then
        lib.table.add(items, "custom-electric-power", -beacon_power)
    end

    return {
        line_id = line.id,
        items = items
    }
end


--- Converts the floor into a pseudo-machine based on the solver results
---@param floor Floor
---@param result_map SimplexFloorResultTable
---@return SimplexLineData?
function simplex_engine.get_line_data_from_floor(floor, result_map)
    if not result_map[floor.id] then return nil end
end


return simplex_engine