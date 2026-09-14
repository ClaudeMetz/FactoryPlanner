local sequential_engine = require("backend.calculation.sequential_engine")
local gaussian_engine = require("backend.calculation.gaussian_engine")
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
    local products = {}  ---@type SolverItem[]
    for product in factory:iterator() do
        ---@cast product.proto.type -nil
        local item = {
            name = product.proto.name,
            type = product.proto.type,
            amount = product:get_required_amount()
        }  ---@type SolverItem
        table.insert(products, item)
    end
    return products
end

---@param floor Floor
---@return SolverItem[]
local function floor_products(floor)
    local products = {}  ---@type SolverItem[]
    for _, product in pairs(floor.first--[[@as Line]].recipe.products) do
        local item = {
            name = product.name,
            type = product.type,
            amount = 0
        }  ---@type SolverItem
        table.insert(products, item)
    end
    return products
end

---@param recipe Recipe
---@return SolverItem[]
local function line_ingredients(recipe)
    local ingredients = {}  ---@type SolverItem[]
    for _, ingredient in pairs(recipe.ingredients) do
        local item = {
            name = recipe:get_name_with_temperature(ingredient),
            type = ingredient.type,
            amount = ingredient.amount,
            temperature = recipe:get_temperature(ingredient)  -- don't need min/max temperatures here
        }  ---@as SolverItem
        table.insert(ingredients, item)
    end
    return ingredients
end

---@alias FloorDataMap table<ObjectID, FloorData>
---@alias LineDataMap table<ObjectID, LineData>

---@class FloorData
---@field floor_id ObjectID
---@field level integer
---@field products SolverItem[]
---@field line_ids ObjectID[]

---@class LineData
---@field line_id ObjectID
---@field floor_id ObjectID
---@field crafts_per_second number
---@field products SolverMap
---@field ingredients SolverMap
---@field fuel_item SolverItem?
---@field priority_item SolverItem?
---@field beacon_power double?
---@field recipe_name string
---@field machine_limit number?
---@field machine_force_limit boolean?
---@field production_type RecipeProductionType

--- Applies all effects on the machine of the line and returns how many
--- products/ingredients are produced/consumed per second by one machine.
--- Emmisions, fuel, power and heat are also included.
---@param player LuaPlayer
---@param factory Factory
---@param line Line
---@return LineData
local function generate_line_data(player, factory, line)
    local products = {}  ---@type SolverMap
    local ingredients = {}  ---@type SolverMap
    local machine_amount = 1

    local machine_proto = line.machine.proto  ---@as FPMachinePrototype
    local recipe_proto = line.recipe.proto  ---@as FPRecipePrototype
    local machine_speed = line.machine:get_speed()
    local recipe_energy = recipe_proto.energy  ---@as number

    -- Update line effects
    local force = player.force  ---@as LuaForce
    local mod_changed = line.machine:update_mod_effects(force)
    local recipe_changed = line.recipe:update_effects(force, factory)
    if mod_changed or recipe_changed then line.machine:summarize_effects() end

    -- Lab speed bonus is multiplicative, not additive to effects
    if machine_proto.prototype_category == "lab" then
        machine_speed = machine_speed * (1 + force.laboratory_speed_modifier)
    end

    -- Get boiler energy
    if machine_proto.prototype_category == "boiler" then
        local goal_temperature = recipe_proto.products[1]--[[@cast -nil]].temperature  ---@as float
        local input_temperature = line.recipe:get_temperature( recipe_proto.ingredients[1]--[[@cast -nil]])  ---@as float
        recipe_energy = (goal_temperature - input_temperature) * recipe_proto.heat_capacity  ---@as number
    end

    -- Get amount of crafts in 1 second
    local fuel_performance, wasted_share = line.machine:get_fuel_performance()
    local speed_multiplier = machine_speed * fuel_performance * (1 + (line.total_effects.speed / MAGIC_NUMBERS.effect_precision))
    local energy = math.max(recipe_energy, MAGIC_NUMBERS.minimum_energy)
    local crafts_per_second = machine_amount * speed_multiplier / energy

    -- Get simple products
    for _, item in pairs(line.recipe.products) do
        local amount = crafts_per_second * solver.util.determine_prodded_amount(item, line.total_effects)
        structures.map.add(products, item, amount)
    end

    -- Get simple ingredients
    for _, item in pairs(line_ingredients(line.recipe)) do
        local amount = item.amount * crafts_per_second * (item.type ~= "fluid" and line.machine:get_resource_drain_rate() or 1)
        structures.map.add(ingredients, item, amount)
    end

    -- Get fuel
    local fuel_proto = nil
    local fuel_name = nil
    local fuel_value = nil
    if machine_proto.burner then
        ---@cast line.machine.fuel -nil
        fuel_proto = line.machine.fuel.proto  ---@as AnyFPFuelPrototype
        fuel_name = line.machine.fuel:get_name_with_temperature()
        fuel_value = line.machine.fuel:get_fuel_value()
    end

    local power = 0.0
    local emissions = 0.0
    local calculate_emissions = lib.globals.preferences(player).calculate_emissions
    local pollutant_type = (calculate_emissions) and factory.parent.location_proto.pollutant_type

    local fuel_amount = 0.0
    local power_amount = 0.0
    local heat_amount = 0.0
    local heating_amount = 0.0

    if energy > MAGIC_NUMBERS.minimum_energy then
        -- Get power
        local consumption_multiplier = 1 + (line.total_effects.consumption / MAGIC_NUMBERS.effect_precision)
        -- A fuel-starved machine only draws what it can get, and pollutes proportionally less
        local machine_power = machine_amount * (line.machine:get_energy_usage() * 60) * consumption_multiplier * fuel_performance
        -- Drain follows the exact machine count rather than the whole machines that'd actually be
        -- built, so that power stays proportional to it. The matrix solver relies on that to balance
        -- power against the machines producing it, since it works in amounts for a single machine.
        local machine_drain = machine_amount * (machine_proto.energy_drain * 60)
        power = machine_power + machine_drain

        -- Get emissions
        if pollutant_type then

            local fuel_multiplier = fuel_proto and fuel_proto.emissions_multiplier or 1
            local pollution_multiplier = 1 + (line.total_effects.pollution / MAGIC_NUMBERS.effect_precision)
            local total_multiplier = fuel_multiplier * pollution_multiplier * recipe_proto.emissions_multiplier

            -- Pollution comes from the fuel that's burned, not the energy the machine puts to use: an
            -- effectivity below 1 burns extra, and a source that doesn't scale its usage burns its full
            -- amount even when the machine can't use all of it
            local burned_energy = machine_power
            if machine_proto.burner then
                burned_energy = burned_energy / machine_proto.burner.effectivity
                if wasted_share > 0 and wasted_share < 1 then burned_energy = burned_energy / (1 - wasted_share) end
            end

            local emissions_per_joule = burned_energy * (machine_proto.emissions_per_joule[pollutant_type] or 0)
            local emissions_per_second = machine_amount * (machine_proto.emissions_per_second[pollutant_type] or 0)
            local emissions_per_craft = (recipe_proto.emissions_per_craft) and
                crafts_per_second * (recipe_proto.emissions_per_craft[pollutant_type] or 0) or 0
            emissions = (emissions_per_joule + emissions_per_second + emissions_per_craft) * total_multiplier * 60
        end

        -- Get fuel/power/heat energy requirements
        if machine_proto.burner then
            local fluid_usage_per_tick = line.machine:get_fluid_usage_per_tick()

            if fluid_usage_per_tick and not machine_proto.burner.scale_fluid_usage then
                -- Without scaling, the source always moves its full usage, wasting any energy beyond demand
                fuel_amount = machine_amount * fluid_usage_per_tick * 60
            else
                -- Power is already reduced by the fuel performance, so this collapses to the usage per tick
                -- when the source can't keep up, and to the demanded amount when it can
                fuel_amount = (power / machine_proto.burner.effectivity) / fuel_value  ---@as number
            end
        elseif machine_proto.energy_type == "electric" then
            power_amount = power
        elseif machine_proto.energy_type == "heat" then
            heat_amount = power
        end  -- else "void", but we don't care
    end

    -- Get beacon power
    local beacon_power = line.beacon and line.beacon:get_total_power()

    -- Get heat requirements (frozen surfaces e.g. Aquillo)
    if factory.parent.location_proto.entities_require_heating then
        heating_amount = machine_proto.heating_energy
    end

    -- Add fuel to the ingredients
    local fuel_item = nil  ---@type SolverItem?
    if machine_proto.burner then
        ---@cast fuel_name -nil
        ---@cast fuel_proto -nil
        fuel_item = {
            name = fuel_name,
            type = fuel_proto.type,
            amount = fuel_amount
        }  ---@type SolverItem
        structures.map.add(ingredients, fuel_item)

        -- Add burnt result
        if fuel_proto.burnt_result then
            local burnt_item = {
                name = fuel_proto.burnt_result,
                type = "item",
                amount = fuel_amount
            }  ---@type SolverItem
            structures.map.add(products, burnt_item)
        end

        -- Add spent fluid
        local spent_fluid = machine_proto.burner.produces_spent_fluid and (machine_proto.burner.spent_fluid or fuel_proto.spent_fluid)
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
        local item = {name="custom-electric-power", type="entity", amount=power_amount}
        structures.map.add(ingredients, item)
    end
    if heat_amount > 0 then
        local item = {name="custom-heat-power", type="entity", amount=heat_amount}
        structures.map.add(ingredients, item)
    end
    if heating_amount > 0 then
        local item = {name="custom-heating-power", type="entity", amount=heating_amount}
        structures.map.add(ingredients, item)
    end
    if pollutant_type and emissions ~= 0 then
        local item = {name="custom-"..pollutant_type, type="entity", amount=math.abs(emissions)}
        if emissions > 0 then
            structures.map.add(products, item)
        else
            structures.map.add(ingredients, item)
        end
    end

    -- Get the priority product
    local priority_item = nil
    if line.recipe.priority_item then
        priority_item = {
            name = line.recipe.priority_item.name,
            type = line.recipe.priority_item.type--[[@cast -nil]],
            amount = 0
        }  ---@type SolverItem
    end

    -- Needed to reduce looped fuel + safeguard
    structures.map.reduce_items(products, ingredients)

    return {
        line_id = line.id,
        floor_id = line.parent.id,
        crafts_per_second = crafts_per_second,
        products = products,
        ingredients = ingredients,
        fuel_item = fuel_item,
        priority_item = priority_item,
        beacon_power = beacon_power,
        recipe_name = recipe_proto.name,
        machine_limit = energy > MAGIC_NUMBERS.minimum_energy and line.machine.limit or nil,
        machine_force_limit = energy > MAGIC_NUMBERS.minimum_energy and line.machine.force_limit or nil,
        production_type = line.recipe.production_type,
    }
end

--- Generates structured data of the given floor for calculation
---@param player LuaPlayer
---@param factory Factory
---@param floor Floor
---@return FloorDataMap
---@return LineDataMap
local function generate_floor_data(player, factory, floor)
    local floor_data = {
        floor_id = floor.id,
        level = floor.level,
        products = floor.level == 1 and factory_products(factory) or floor_products(floor),
        line_ids = {}
    }  ---@type FloorData

    local floor_data_map = {}  ---@type FloorDataMap
    local line_data_map = {}  ---@type LineDataMap
    local relevant_line_active = true

    for line in floor:iterator() do
        if line.class == "Floor" then  ---@cast line Floor
            local subfloor_floor_map, subfloor_line_map
            subfloor_floor_map, subfloor_line_map = generate_floor_data(player, factory, line)
            table.insert(floor_data.line_ids, line.id)
            for k, v in pairs (subfloor_floor_map) do floor_data_map[k] = v end
            for k, v in pairs (subfloor_line_map) do line_data_map[k] = v end
        else  ---@cast line Line
            if line:get_blocker() or not relevant_line_active then
                -- Useless lines don't need to run through the solver
                solver.set_blank_line(floor, line)
                if line == floor.first and floor.level > 1 then relevant_line_active = false end
            else
                table.insert(floor_data.line_ids, line.id)
                line_data_map[line.id] = generate_line_data(player, factory, line)
            end
        end
    end

    floor_data_map[floor.id] = floor_data
    return floor_data_map, line_data_map
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
            gaussian_engine.solve(factory_data)
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
---@field top_floor_id ObjectID
---@field floor_data_map FloorDataMap
---@field line_data_map LineDataMap
---@field matrix_free_items FPItemPrototype[]
---@field simplex_basis table<ConstraintKey, VariableKey>

--- Returns a table containing all the data needed to run the calculations for the given factory
---@param player LuaPlayer
---@param factory Factory
---@return FactoryData
function solver.generate_factory_data(player, factory)
    local free_items = factory.matrix_free_items  ---@as FPItemPrototype[]  -- intentional pass-by-reference
    local floor_data_map, line_data_map =
        generate_floor_data(player, factory, factory.top_floor)

    local factory_data = {
        player_index = player.index,
        factory_id = factory.id,
        top_floor_id = factory.top_floor.id,
        floor_data_map = floor_data_map,
        line_data_map = line_data_map,
        matrix_free_items = free_items,
        simplex_basis = factory.simplex_basis or {}
    }

    return factory_data
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
