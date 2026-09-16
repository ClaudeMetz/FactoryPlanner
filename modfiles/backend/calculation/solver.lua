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

---@class LineData
---@field id ObjectID
---@field floor_id ObjectID
---@field crafts_per_second number
---@field products SolverMap
---@field ingredients SolverMap
---@field fuel_item SolverItem?
---@field priority_item SolverItem?
---@field recipe_name string
---@field machine_limit number?
---@field machine_force_limit boolean?
---@field production_type RecipeProductionType

--- Applies all effects on the machine of the line and returns how many
--- products/ingredients are produced/consumed per second by one machine
--- Emmisions, fuel, power and heat are also included
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
        local input_temperature = line.recipe:get_temperature(recipe_proto.ingredients[1]--[[@cast -nil]])  ---@as float
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
    power_amount = power_amount + (line.beacon and line.beacon:get_power_per_machine() or 0)

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
        id = line.id,
        floor_id = line.parent.id,
        crafts_per_second = crafts_per_second,
        products = products,
        ingredients = ingredients,
        fuel_item = fuel_item,
        priority_item = priority_item,
        recipe_name = recipe_proto.name,
        machine_limit = energy > MAGIC_NUMBERS.minimum_energy and line.machine.limit or nil,
        machine_force_limit = energy > MAGIC_NUMBERS.minimum_energy and line.machine.force_limit or nil,
        production_type = line.recipe.production_type,
    }  ---@type LineData
end

---@alias FloorResultMap table<ObjectID, FloorResult>
---@alias LineResultMap table<ObjectID, LineResult>
---@alias SolverState SequentialSolverState|SimplexSolverState|GaussianSolverState

---@class FloorResult
---@field state SolverState
---@field id ObjectID
---@field products SolverMap
---@field ingredients SolverMap
---@field line_result_map LineResultMap
---@field cache_invalid boolean?
---@field gaussian_free_items FPItemPrototype[]?  -- gaussian
---@field linear_dependence_data LinearDependanceData?
---@field simplex_basis_cache SimplexBasisCache?  -- simplex

---@class LineResult
---@field id ObjectID
---@field machine_amount number

---@param factory_data FactoryData
---@param floor_id ObjectID
---@param subfloor_result FloorResult
local function generate_line_data_from_result(factory_data, floor_id, subfloor_result)
    local subfloor_data = factory_data.floor_data_map[subfloor_result.id]
    local subfloor_line = factory_data.line_data_map[subfloor_data.line_ids[1]--[[@cast -nil]]]
    factory_data.line_data_map[subfloor_result.id] = {
        id = subfloor_result.id,
        floor_id = floor_id,
        crafts_per_second = 1,
        products = subfloor_result.products,
        ingredients = subfloor_result.ingredients,
        priority_item = subfloor_line.priority_item,
        recipe_name = subfloor_line.recipe_name,
        machine_limit = subfloor_line.machine_limit,
        machine_force_limit = subfloor_line.machine_force_limit,
        production_type = "produce"
    }
end

---@class FloorData
---@field id ObjectID
---@field level integer
---@field products SolverItem[]
---@field line_ids ObjectID[]
---@field gaussian_free_items FPItemPrototype[]
---@field simplex_basis SimplexBasisCache?

---@alias FloorDataMap table<ObjectID, FloorData>
---@alias LineDataMap table<ObjectID, LineData>

--- Generates structured data of the given floor for calculation
---@param player LuaPlayer
---@param factory Factory
---@param floor Floor
---@return FloorDataMap
---@return LineDataMap
local function generate_floor_data(player, factory, floor)
    local free_items = floor.gaussian_free_items  ---@as FPItemPrototype[]
    local floor_data = {
        id = floor.id,
        level = floor.level,
        products = floor.level == 1 and factory_products(factory) or {},
        line_ids = {},
        gaussian_free_items = free_items,
        simplex_basis = floor.simplex_basis_cache
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

---@class FactoryData
---@field player_index uint32
---@field factory_id ObjectID
---@field floor_data_map FloorDataMap
---@field line_data_map LineDataMap

--- Returns a table containing all the data needed to run the calculations for the given factory
---@param player LuaPlayer
---@param factory Factory
---@return FactoryData
local function generate_factory_data(player, factory)
    -- Intentional pass-by-reference
    local floor_data_map, line_data_map =
        generate_floor_data(player, factory, factory.top_floor)

    local factory_data = {
        player_index = player.index,
        factory_id = factory.id,
        top_floor_id = factory.top_floor.id,
        floor_data_map = floor_data_map,
        line_data_map = line_data_map,
    }

    return factory_data
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

        -- Clear solve caches on updated floors
        local floor = lib.context.get(player, "Floor")
        while floor and floor.class == "Floor" do
            floor:clear_solver_cache(true)
            floor = floor.parent
        end

        local factory_data = generate_factory_data(player, factory)
        local result_map = {}  ---@type FloorResultMap

        ---@param floor_id ObjectID
        ---@return boolean? cache_invalid
        local function solve_floor(floor_id)
            -- Recurse the floor tree from the leaves to the top floor (root)
            local floor_data = factory_data.floor_data_map[floor_id]
            for _, line_object_id in pairs(floor_data.line_ids) do
                if factory_data.floor_data_map[line_object_id] then
                    local cache_invalid = solve_floor(line_object_id)
                    if cache_invalid then
                        floor_data.simplex_basis = nil
                    end
                end
            end

            local result = nil
            if factory.solver == "sequential" then
                result = sequential_engine.solve_floor(factory_data, floor_id)
            elseif factory.solver == "simplex" then
                result = simplex_engine.solve_floor(factory_data, floor_id)
            elseif factory.solver == "gaussian" then
                result = gaussian_engine.solve_floor(factory_data, floor_id)
            end

            if result then
                result_map[floor_id] = result
                generate_line_data_from_result(factory_data, floor_id, result)
                return result.cache_invalid
            end
        end

        solve_floor(factory.top_floor.id)
        solver.update_factory(factory_data, result_map)
    end
end

---@param factory Factory
function solver.determine_ingredient_satisfaction(factory)
    if not factory.valid then return end
    update_ingredient_satisfaction(factory.top_floor)
end


-- ** INTERFACE **
---@param factory_data FactoryData
---@param result_map FloorResultMap
function solver.update_factory(factory_data, result_map)
    local factory = OBJECT_INDEX[factory_data.factory_id]  ---@as Factory

    local top_products = {}  ---@type SolverSet
    local top_byproducts = {}  ---@type SolverMap

    local product_result = {}  ---@type SolverMap
    local byproduct_result = {}  ---@type SolverMap
    local ingredient_result = {}  ---@type SolverMap

    for product in factory:iterator() do
        top_products[structures.pack_item(product)] = true
    end

    local top_floor_result = result_map[factory.top_floor.id]
    if top_floor_result then
        -- Update the products
        for item_key, amount in pairs(top_floor_result.products) do
            if top_products[item_key] then
                -- Update product amount
                structures.map.add(product_result, structures.unpack_item(item_key, amount))
            else
                -- Add to byproducts
                structures.map.add(top_byproducts, structures.unpack_item(item_key, amount))
                structures.map.add(byproduct_result, structures.unpack_item(item_key, amount))
            end
        end

        -- Update the ingredients
        for item_key, amount in pairs(top_floor_result.ingredients) do
            structures.map.add(ingredient_result, structures.unpack_item(item_key, amount))
        end
    end

    solver.update_floor(factory_data, result_map, factory.top_floor.id, 1, top_byproducts)

    if factory.parent then factory.parent.needs_refresh = true end

    for product in factory:iterator() do
        product.amount = product_result[structures.pack_item(product)] or 0
    end

    update_object_items(factory.top_floor, "byproducts", byproduct_result)
    update_object_items(factory.top_floor, "ingredients", ingredient_result)

    -- Determine satisfaction-amounts for all line ingredients
    local player = game.players[factory_data.player_index]
    if lib.globals.preferences(player).ingredient_satisfaction then
        solver.determine_ingredient_satisfaction(factory)
    end
end

---@param factory_data FactoryData
---@param result_map FloorResultMap
---@param floor_id ObjectID
---@param scale_factor number
---@param byproducts SolverMap
---@return integer machine_amount
function solver.update_floor(factory_data, result_map, floor_id, scale_factor, byproducts)
    local floor = OBJECT_INDEX[floor_id]  ---@as Floor
    local result = result_map[floor_id]
    local machine_amount = 0

    for line_object in floor:iterator(nil, floor:find_last(), "previous") do
        local line_result = result and result.line_result_map[line_object.id]
        if line_object.class == "Line" then
            local line_data = factory_data.line_data_map[line_object.id]
            local line_machines = solver.update_line(line_object.id, floor_id, line_data, line_result, scale_factor, byproducts)
            machine_amount = machine_amount + math.ceil(line_machines - MAGIC_NUMBERS.margin_of_error)
        else  -- Floor
            local blank_result = {
                state = "solved",
                id = line_object.id,
                products = {},
                ingredients = {},
                line_result_map = {}
            }  ---@type FloorResult
            local subfloor_result = result_map[line_object.id] or blank_result
            local subfloor_scale_factor = (line_result and line_result.machine_amount or 0) * scale_factor

            local product_result, byproduct_result, ingredient_result, floor_byproducts =
                    solver.update_line_object_common(subfloor_scale_factor, subfloor_result.products, byproducts, subfloor_result.ingredients)
            local floor_machines = solver.update_floor(factory_data, result_map, line_object.id, subfloor_scale_factor, floor_byproducts)

            line_object.machine_amount = floor_machines

            update_object_items(line_object, "products", product_result)
            update_object_items(line_object, "byproducts", byproduct_result)
            update_object_items(line_object, "ingredients", ingredient_result)

            machine_amount = machine_amount + floor_machines
        end
    end

    if result then
        floor.gaussian_free_items = result.gaussian_free_items or floor.gaussian_free_items
        floor.linear_dependence_data = result.linear_dependence_data
        floor.simplex_basis_cache = result.simplex_basis_cache

        -- TODO: handle solver error states (`result.state`)
    end

    return machine_amount
end

---@param line_id ObjectID
---@param floor_id ObjectID
---@param line_data LineData?
---@param result LineResult?
---@param scale_factor number
---@param byproducts SolverMap
---@return number machine_amount
function solver.update_line(line_id, floor_id, line_data, result, scale_factor, byproducts)
    local line = OBJECT_INDEX[line_id]  ---@as Line

    local machine_amount = 0.0
    local crafts_per_second = 0.0

    local product_result = {}  ---@type SolverMap
    local byproduct_result = {}  ---@type SolverMap
    local ingredient_result = {}  ---@type SolverMap

    local fuel_amount = 0.0

    if line_data and result then
        -- Update the machine
        machine_amount = scale_factor * result.machine_amount
        crafts_per_second = machine_amount * line_data.crafts_per_second

        product_result, byproduct_result, ingredient_result =
                solver.update_line_object_common(machine_amount, line_data.products, byproducts, line_data.ingredients)

        -- Update the fuel
        if line_data.fuel_item then
            local fuel_key = structures.pack_item(line_data.fuel_item)
            fuel_amount = line_data.fuel_item.amount * machine_amount
            local ingredient_amount = ingredient_result--[[@as SolverMap]][fuel_key] or 0
            if fuel_amount <= ingredient_amount then
                structures.map.subtract(ingredient_result, line_data.fuel_item, fuel_amount)
            else
                structures.map.add(product_result, line_data.fuel_item, fuel_amount - ingredient_amount)
                ingredient_result[fuel_key] = nil
            end
        end
    end

    line.machine.amount = machine_amount
    -- Workaround for recipes with 0 energy
    if line.recipe.proto.energy <= MAGIC_NUMBERS.minimum_energy then line.machine.amount = 0 end

    line.production_ratio = crafts_per_second
    if line.machine.fuel ~= nil then line.machine.fuel.amount = fuel_amount end

    if line.production_ratio == 0 then
        set_zeroed_items(line, "products", line.recipe.products)
        line.byproducts = {}
        set_zeroed_items(line, "ingredients", line.recipe.ingredients)
    else
        update_object_items(line, "products", product_result)
        update_object_items(line, "byproducts", byproduct_result)
        update_object_items(line, "ingredients", ingredient_result)
    end

    return machine_amount
end

---@param machine_amount number
---@param products SolverMap
---@param byproducts SolverMap
---@param ingredients SolverMap
---@return SolverMap products
---@return SolverMap byproducts
---@return SolverMap ingredients
---@return SolverMap floor_byproducts
function solver.update_line_object_common(machine_amount, products, byproducts, ingredients)
    local floor_byproducts = {}  ---@type SolverMap

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
            structures.map.add(floor_byproducts, item)

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
