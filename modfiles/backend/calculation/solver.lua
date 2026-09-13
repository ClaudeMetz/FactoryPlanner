local sequential_engine = require("backend.calculation.sequential_engine")
local matrix_engine = require("backend.calculation.matrix_engine")
local simplex_engine = require("backend.calculation.simplex_engine")
local structures = require("backend.calculation.structures")
local SimpleItem = require("backend.data.SimpleItem")

---@alias SolverName "sequential" | "simplex" | "gaussian"

solver = {
    util = require("backend.calculation.solver_util"),
    choices = {"sequential", "simplex", "gaussian"}  ---@type SolverName[]
}

-- ** LOCAL UTIL **
---@param floor Floor
---@param line LineObject
function solver.set_blank_line(floor, line)
    solver.set_line_result {
        floor_id = floor.id,
        line_id = line.id,
        machine_amount = 0,
        crafts_per_second = (line.class == "Line") and 0 or nil,
        products = {},
        byproducts = {},
        ingredients = {},
        fuel_amount = 0
    }
end

---@param floor Floor
function solver.set_blank_floor(floor)
    for line in floor:iterator() do
        if line.class == "Floor" then
            solver.set_blank_line(floor, line)
            solver.set_blank_floor(line)
        else
            solver.set_blank_line(floor, line)
        end
    end
end

---@param player LuaPlayer
---@param factory Factory
function solver.set_blank_factory(player, factory)
    solver.set_factory_result {
        player_index = player.index,
        factory_id = factory.id,
        products = {},
        byproducts = {},
        ingredients = {},
        matrix_free_items = factory.matrix_free_items  ---@as FPItemPrototype[]
    }

    solver.set_blank_floor(factory.top_floor)
end


---@param factory Factory
---@return SolverItem[]
local function factory_products(factory)
    local products = {}
    for product in factory:iterator() do
        local product_data = {
            name = product.proto.name,
            type = product.proto.type,
            amount = product:get_required_amount()
        }
        table.insert(products, product_data)
    end
    return products
end

---@param recipe Recipe
---@return SolverItem[]
local function line_ingredients(recipe)
    local ingredients = {}
    for _, ingredient in pairs(recipe.ingredients) do
        table.insert(ingredients, {
            name = recipe:get_name_with_temperature(ingredient),
            type = ingredient.type,
            amount = ingredient.amount,
            temperature = recipe:get_temperature(ingredient)
        })  -- don't need min/max temperatures here
    end
    return ingredients
end

---@class FloorData
---@field id ObjectID
---@field products (FormattedProduct | SolverItem)[]
---@field lines (LineData | SubfloorLineData)[]

---@class SubfloorLineData
---@field id ObjectID
---@field recipe_proto FPRecipePrototype
---@field products FormattedProduct[]
---@field subfloor FloorData?

---@class LineData
---@field id ObjectID
---@field recipe_proto FPRecipePrototype
---@field recipe_energy double
---@field ingredients SolverItem[]
---@field products FormattedProduct[]
---@field percentage number
---@field production_type RecipeProductionType
---@field priority_item_proto FPItemPrototype
---@field machine_proto FPMachinePrototype
---@field machine_limit MachineLimit
---@field machine_speed double
---@field energy_usage double
---@field resource_drain_rate double
---@field pollutant_type string?
---@field entities_require_heating boolean
---@field total_effects IntegerModuleEffects
---@field beacon_power double?
---@field fuel_proto AnyFPFuelPrototype?
---@field fuel_name string?
---@field fuel_value number?
---@field fuel_performance number
---@field wasted_share number
---@field fluid_usage_per_tick number?

---@alias MachineLimit {limit: number?, force_limit: boolean}

--- Generates structured data of the given floor for calculation
---@param player LuaPlayer
---@param factory Factory
---@param floor Floor
---@param calculate_emissions boolean
---@return FloorData
---@return AggregateMap
local function generate_floor_data(player, factory, floor, calculate_emissions)
    local floor_data = {
        id = floor.id,
        products = (floor.level == 1) and factory_products(factory)
            or floor.first--[[@as Line]].recipe.products,
        lines = {}
    }  ---@type FloorData

    local aggregate_map = {}  ---@type AggregateMap
    local relevant_line_active = true

    for line in floor:iterator() do
        local line_data = { id = line.id }

        if line.class == "Floor" then  ---@cast line Floor
            local subfloor_aggregate_map
            line_data.recipe_proto = line.first--[[@as Line]].recipe.proto
            line_data.products = line.first--[[@as Line]].recipe.products
            line_data.subfloor, subfloor_aggregate_map = generate_floor_data(player, factory, line, calculate_emissions)
            table.insert(floor_data.lines, line_data)
            for k, v in pairs (subfloor_aggregate_map) do aggregate_map[k] = v end
        else  ---@cast line Line
            if line:get_blocker() ~= nil then
                -- Useless lines don't need to run through the solver
                solver.set_blank_line(floor, line)
                if line == floor.first and floor.level > 1 then relevant_line_active = false end
            elseif relevant_line_active then
                local machine = line.machine
                local recipe_proto = line.recipe.proto  ---@as FPRecipePrototype

                line_data.recipe_proto = recipe_proto
                line_data.recipe_energy = recipe_proto.energy
                line_data.ingredients = line_ingredients(line.recipe)  -- bakes in temperatures
                line_data.products = line.recipe.products
                line_data.percentage = line.percentage  -- non-zero
                line_data.production_type = line.recipe.production_type
                line_data.priority_item_proto = line.recipe.priority_item  ---@as FPItemPrototype
                line_data.machine_proto = machine.proto  ---@as FPMachinePrototype
                line_data.machine_limit = {limit=machine.limit, force_limit=machine.force_limit}
                line_data.energy_usage = machine:get_energy_usage()
                line_data.fluid_usage_per_tick = machine:get_fluid_usage_per_tick()
                line_data.resource_drain_rate = machine:get_resource_drain_rate()
                line_data.pollutant_type = (calculate_emissions) and factory.parent.location_proto.pollutant_type or nil
                line_data.entities_require_heating = factory.parent.location_proto.entities_require_heating or false

                local force = player.force  ---@as LuaForce
                local mod_changed = machine:update_mod_effects(force)
                local recipe_changed = line.recipe:update_effects(force, factory)
                if mod_changed or recipe_changed then machine:summarize_effects() end
                line_data.total_effects = line.total_effects

                if machine.fuel ~= nil then
                    line_data.fuel_proto = machine.fuel.proto  ---@as AnyFPFuelPrototype
                    line_data.fuel_name = machine.fuel:get_name_with_temperature()
                    line_data.fuel_value = machine.fuel:get_fuel_value()
                end

                -- The machine needs to potentially run slower if fuel is insufficient
                line_data.fuel_performance, line_data.wasted_share = machine:get_fuel_performance()
                line_data.machine_speed = machine:get_speed() * line_data.fuel_performance

                -- Lab speed bonus is multiplicative, not additive to effects
                if machine.proto.prototype_category == "lab" then
                    line_data.machine_speed = line_data.machine_speed
                        * (1 + force.laboratory_speed_modifier)
                end

                if machine.proto.prototype_category == "boiler" then
                    local goal_temperature = recipe_proto.products[1]--[[@cast -nil]].temperature  ---@as float
                    local input_temperature = line.recipe:get_temperature(
                        recipe_proto.ingredients[1]--[[@cast -nil]])  ---@as float
                    line_data.recipe_energy = (goal_temperature - input_temperature)
                        * recipe_proto.heat_capacity--[[@as double]]
                end

                -- Beacon total - can be calculated here, which is faster and simpler
                if line.beacon ~= nil and line.beacon.total_amount ~= nil then
                    line_data.beacon_power = line.beacon:get_total_power()
                end

                table.insert(floor_data.lines, line_data)
                aggregate_map[line.id] = solver.get_line_aggregate(line_data  --[[@as LineData]], floor.id, 1)
            else
                solver.set_blank_line(floor, line)
            end
        end
    end

    return floor_data, aggregate_map
end


---@alias SolverItemCategory "products" | "byproducts" | "ingredients"

---@param a SimpleItem
---@param b SimpleItem
---@return boolean
local function item_comparator(a, b)
    local a_type, b_type = a.proto.type, b.proto.type
    if a_type < b_type then return false
    elseif a_type > b_type then return true
    elseif a.amount < b.amount then return false
    elseif a.amount > b.amount then return true end
    return false
end

---@param object LineObject
---@param item_category SolverItemCategory
---@param item_results SolverMap
local function update_object_items(object, item_category, item_results)
    local item_list = {}

    for _, item_result in pairs(structures.map.list(item_results)) do
        local item_proto = prototyper.util.find("items", item_result.name, item_result.type)  ---@as FPItemPrototype

        -- Floor items keep their temperature, since they can't be configured from there
        if object.class ~= "Floor" and item_category == "ingredients" and item_proto.base_name then
            item_proto = prototyper.util.find("items", item_proto.base_name, "fluid")  ---@as FPItemPrototype
        end

        if object.class ~= "Floor" or item_proto.type ~= "entity" or item_proto.special then
            table.insert(item_list, SimpleItem.init(object, item_proto, item_result.amount))
        end
    end

    table.sort(item_list, item_comparator)
    object[item_category] = item_list
end

---@param line Line
---@param item_category SolverItemCategory
---@param items FormattedProduct[] | Ingredient[]
local function set_zeroed_items(line, item_category, items)
    local item_list = {}

    for _, item in pairs(items) do
        local item_proto = prototyper.util.find("items", item.name, item.type)  ---@as FPItemPrototype
        table.insert(item_list, SimpleItem.init(line, item_proto))
    end

    line[item_category] = item_list
end


---@param floor Floor
local function update_ingredient_satisfaction(floor)
    local ingredient_deficit = {}  ---@type SolverMap
    for _, item in pairs(floor.ingredients) do
        if floor.level == 1 then item.satisfied_amount = 0 end
        structures.map.add(ingredient_deficit, item, item.amount - (item.satisfied_amount or 0))
    end

    ---@param item SimpleItem | Fuel
    ---@param item_name string
    local function calculate_satisfation(item, item_name)
        ---@cast item.proto -FPPackedPrototype
        local solver_item = { name = item_name, type = item.proto.type, amount = 0 }  ---@type SolverItem
        local unsatisfied_amount = ingredient_deficit[structures.pack_item(solver_item)] ---@as number?
        local deficit = math.min(unsatisfied_amount or 0, item.amount)

        item.satisfied_amount = item.amount - deficit
        if item.satisfied_amount < MAGIC_NUMBERS.margin_of_error then item.satisfied_amount = 0 end

        if deficit > 0 then
            structures.map.subtract(ingredient_deficit, solver_item, deficit)
        end
    end

    for line_object in floor:iterator(nil, floor:find_last(), "previous") do
        for _, item in pairs(line_object.ingredients) do
            local name = line_object.class == "Line" and line_object.recipe:get_name_with_temperature(item.proto)
                    or item.proto.name
            calculate_satisfation(item, name)
        end

        if line_object.class == "Line" and line_object.machine.fuel then
            local name = line_object.machine.fuel:get_name_with_temperature()
            calculate_satisfation(line_object.machine.fuel, name)
        end

        if line_object.class == "Floor" then update_ingredient_satisfaction(line_object) end
    end
end


-- ** TOP LEVEL **
--- Updates the whole factory calculations from top to bottom
---@param player LuaPlayer
---@param factory Factory?
function solver.update(player, factory)
    factory = factory or lib.context.get(player, "Factory")  ---@as Factory
    if factory and factory.valid then
        -- Cancel any pending update as it'll be running right now
        if factory.tick_of_solver_update then
            lib.nth_tick.cancel(factory.tick_of_solver_update)
            factory.tick_of_solver_update = nil
        end

        local factory_data = solver.generate_factory_data(player, factory)

        if factory.solver == "sequential" then
            sequential_engine.update_factory(factory_data)

        elseif factory.solver == "simplex" then
            simplex_engine.solve(factory_data)

        else  -- "gaussian"
            matrix_engine.solve(factory_data)
        end
    end
end

---@param factory Factory
function solver.determine_ingredient_satisfaction(factory)
    if not factory.valid then return end
    update_ingredient_satisfaction(factory.top_floor)
end


-- ** INTERFACE **
---@class FactoryData
---@field player_index uint32
---@field factory_id ObjectID
---@field line_data AggregateMap
---@field top_floor FloorData
---@field matrix_free_items FPItemPrototype[]
---@field simplex_basis table<ConstraintKey, VariableKey>

--- Returns a table containing all the data needed to run the calculations for the given factory
---@param player LuaPlayer
---@param factory Factory
---@return FactoryData
function solver.generate_factory_data(player, factory)
    local calculate_emissions = lib.globals.preferences(player).calculate_emissions
    local free_items = factory.matrix_free_items  ---@as FPItemPrototype[]
    local top_floor_data, line_data = generate_floor_data(player, factory, factory.top_floor, calculate_emissions)

    local factory_data = {
        player_index = player.index,
        factory_id = factory.id,
        line_data = line_data,
        top_floor = top_floor_data,
        matrix_free_items = free_items,
        simplex_basis = factory.simplex_basis or {}
    }

    return factory_data
end


--- Applies all effects on the machine of the line and returns how many
--- products/ingredients are produced/consumed per second by the nuber of given machines.
--- Emmisions, fuel, power and heat are also included.
---@param line_data LineData
---@param floor_id ObjectID
---@param machine_amount number
---@return SolverAggregate
function solver.get_line_aggregate(line_data, floor_id, machine_amount)
    local products = {}  ---@type SolverMap
    local ingredients = {}  ---@type SolverMap

    -- Get amount of crafts in 1 second
    local speed_multiplier = line_data.machine_speed * (1 + (line_data.total_effects.speed / MAGIC_NUMBERS.effect_precision))
    local energy = math.max(line_data.recipe_energy, MAGIC_NUMBERS.minimum_energy)
    local crafts_per_second = machine_amount * speed_multiplier / energy

    -- Get simple products
    for _, item in pairs(line_data.products) do
        local amount = crafts_per_second * solver.util.determine_prodded_amount(item, line_data.total_effects)
        structures.map.add(products, item, amount)
    end

    -- Get simple ingredients
    for _, item in pairs(line_data.ingredients) do
        local amount = item.amount * crafts_per_second * (item.type ~= "fluid" and line_data.resource_drain_rate or 1)
        structures.map.add(ingredients, item, amount)
    end

    local power = 0.0
    local emissions = 0.0

    local fuel_amount = 0.0
    local power_amount = 0.0
    local heat_amount = 0.0
    local heating_amount = 0.0

    if energy > MAGIC_NUMBERS.minimum_energy then
        -- Get power and emissions
        power, emissions = solver.util.determine_power_and_emissions(line_data, machine_amount, crafts_per_second)

        -- Get fuel/power/heat energy requirements
        if line_data.machine_proto.energy_type == "burner" and line_data.fuel_proto then
            ---@cast line_data.machine_proto.burner -nil
            fuel_amount = fuel_amount + solver.util.determine_fuel_amount(line_data, power, machine_amount)
        elseif line_data.machine_proto.energy_type == "electric" then
            power_amount = power_amount + power
        elseif line_data.machine_proto.energy_type == "heat" then
            heat_amount = heat_amount + power
        end
    end

    -- Get beacon power
    local beacon_power = line_data.beacon_power or 0

    -- Get heat requirements (frozen surfaces e.g. Aquillo)
    if line_data.entities_require_heating then
        heating_amount = line_data.machine_proto.heating_energy
    end

    -- Add fuel to the ingredients
    local fuel = nil  ---@type SolverItem?
    local burner = line_data.machine_proto.burner
    if burner then
        ---@cast line_data.fuel_proto -nil
        ---@cast line_data.fuel_name -nil
        fuel = {
            name = line_data.fuel_name,
            type = line_data.fuel_proto.type,
            amount = fuel_amount
        }  ---@type SolverItem
        structures.map.add(ingredients, fuel)

        -- Add burnt result
        if line_data.fuel_proto.burnt_result then
            local burnt_result = {
                name = line_data.fuel_proto.burnt_result,
                type = "item",
                amount = fuel_amount
            }  ---@type SolverItem
            structures.map.add(products, burnt_result)
        end

        -- Add spent fluid
        local spent_fluid = burner.produces_spent_fluid and (burner.spent_fluid or line_data.fuel_proto.spent_fluid)
        if spent_fluid then
            local spent_fluid_item = {
                name = lib.temperature.name_with(spent_fluid.name, spent_fluid.temperature),
                type = "fluid",
                amount = fuel_amount * spent_fluid.amount
            }  ---@type SolverItem
            structures.map.add(products, spent_fluid_item)
        end
    end

    -- Add other special categories
    if power_amount > 0 then
        local item = {name="custom-electric-power", type="entity", amount=0}
        structures.map.add(ingredients, item, power_amount)
    end
    if heat_amount > 0 then
        local item = {name="custom-heat-power", type="entity", amount=0}
        structures.map.add(ingredients, item, heat_amount)
    end
    if heating_amount > 0 then
        local item = {name="custom-heating-power", type="entity", amount=0}
        local item_key = structures.pack_item(item)
        structures.map.add(ingredients, item, heating_amount)
    end
    if line_data.pollutant_type and emissions ~= 0 then
        local item = {name="custom-"..line_data.pollutant_type, type="entity", amount=math.abs(emissions)}
        if emissions > 0 then
            structures.map.add(products, item)
        else
            structures.map.add(ingredients, item)
        end
    end

    return {
        line_id = line_data.id,
        floor_id = floor_id,
        machine_amount = machine_amount,
        crafts_per_second = crafts_per_second,
        products = products,
        byproducts = {},
        ingredients = ingredients,
        known_byproducts = {},
        recipe_name = line_data.recipe_proto.name,
        beacon_power = beacon_power,
        fuel = fuel,
        machine_limit = line_data.machine_limit.limit,
        machine_force_limit = line_data.machine_limit.force_limit,
    }
end

---@class FactoryResult
---@field player_index uint32
---@field factory_id ObjectID
---@field matrix_free_items FPItemPrototype[]?
---@field simplex_basis table<ConstraintKey, VariableKey>?
---@field products SolverMap
---@field byproducts SolverMap
---@field ingredients SolverMap

--- Updates the active factories top-level data with the given result
---@param result FactoryResult
function solver.set_factory_result(result)
    local factory = OBJECT_INDEX[result.factory_id]  ---@as Factory

    if factory.parent then factory.parent.needs_refresh = true end

    factory.matrix_free_items = result.matrix_free_items or {}
    factory.simplex_basis = result.simplex_basis or {}

    for product in factory:iterator() do
        local product_result_amount = result.products[structures.pack_item(product)]
        product.amount = product_result_amount or 0
    end

    update_object_items(factory.top_floor, "byproducts", result.byproducts)
    update_object_items(factory.top_floor, "ingredients", result.ingredients)

    -- Determine satisfaction-amounts for all line ingredients
    local player = game.players[result.player_index]
    if lib.globals.preferences(player).ingredient_satisfaction then
        solver.determine_ingredient_satisfaction(factory)
    end
end

---@class LineResult
---@field floor_id ObjectID
---@field line_id ObjectID
---@field machine_amount number
---@field crafts_per_second number?
---@field products SolverMap
---@field byproducts SolverMap
---@field ingredients SolverMap
---@field fuel_amount number?

--- Updates the given line of the given floor of the active factory
---@param result LineResult
function solver.set_line_result(result)
    local line = OBJECT_INDEX[result.line_id]  ---@as LineObject

    if line.class == "Floor" then  ---@cast line Floor
        line.machine_amount = result.machine_amount  ---@as integer
    else  ---@cast line Line
        line.machine.amount = result.machine_amount
        if line.machine.fuel ~= nil then line.machine.fuel.amount = result.fuel_amount end

        line.production_ratio = result.crafts_per_second

        -- Workaround for recipes with 0 energy
        if line.recipe.proto.energy <= MAGIC_NUMBERS.minimum_energy then line.machine.amount = 0 end
    end

    if line.production_ratio == 0 then  ---@cast line Line
        set_zeroed_items(line, "products", line.recipe.products)
        line.byproducts = {}
        set_zeroed_items(line, "ingredients", line.recipe.ingredients)
    else
        update_object_items(line, "products", result.products)
        update_object_items(line, "byproducts", result.byproducts)
        update_object_items(line, "ingredients", result.ingredients)
    end
end


-- ** EVENTS **
local listeners = {}  ---@type ListenerDefinitions

listeners.global = {
    update_solver = function(metadata)
        ---@cast metadata UpdateSolverMetadata
        local player = game.get_player(metadata.player_index)  ---@as LuaPlayer
        local factory = OBJECT_INDEX[metadata.factory_id]
        solver.update(player, factory)

        -- Scheduled updates run without user interaction, so the interface needs a refresh
        if lib.context.get(player, "Factory") == factory then
            local compact_view = lib.globals.ui_state(player).compact_view
            lib.gui.run_refresh(player, (compact_view) and "compact_factory" or "production")
        end
    end
}

return { listeners }
