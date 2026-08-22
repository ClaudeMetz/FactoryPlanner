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
---@param player LuaPlayer
---@param floor Floor
---@param line LineObject
local function set_blank_line(player, floor, line)
    solver.set_line_result {
        player_index = player.index,
        floor_id = floor.id,
        line_id = line.id,
        machine_amount = 0,
        production_ratio = (line.class == "Line") and 0 or nil,
        products = {},
        byproducts = {},
        ingredients = {},
        fuel_amount = 0
    }
end

---@param player LuaPlayer
---@param floor Floor
local function set_blank_floor(player, floor)
    for line in floor:iterator() do
        if line.class == "Floor" then
            set_blank_line(player, floor, line)
            set_blank_floor(player, line)
        else
            set_blank_line(player, floor, line)
        end
    end
end

---@param player LuaPlayer
---@param factory Factory
local function set_blank_factory(player, factory)
    solver.set_factory_result {
        player_index = player.index,
        factory_id = factory.id,
        products = {},
        byproducts = {},
        ingredients = {},
        matrix_free_items = factory.matrix_free_items  ---@as FPItemPrototype[]
    }

    set_blank_floor(player, factory.top_floor)
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
---@field beacon_power double
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
local function generate_floor_data(player, factory, floor, calculate_emissions)
    local floor_data = {
        id = floor.id,
        products = (floor.level == 1) and factory_products(factory)
            or floor.first--[[@as Line]].recipe.products,
        lines = {}
    }  ---@type FloorData

    for line in floor:iterator() do
        local line_data = { id = line.id }

        if line.class == "Floor" then  ---@cast line Floor
            line_data.recipe_proto = line.first--[[@as Line]].recipe.proto
            line_data.products = line.first--[[@as Line]].recipe.products
            line_data.subfloor = generate_floor_data(player, factory, line, calculate_emissions)
            table.insert(floor_data.lines, line_data)
        else  ---@cast line Line
            if line:get_blocker() ~= nil then
                -- Useless lines don't need to run through the solver
                set_blank_line(player, floor, line)
            else
                local machine = line.machine
                local recipe_proto = line.recipe.proto  ---@as FPRecipePrototype

                line_data.recipe_proto = recipe_proto
                line_data.recipe_energy = recipe_proto.energy
                line_data.ingredients = line_ingredients(line.recipe)  -- bakes in temperatures
                line_data.products = line.recipe.products
                line_data.percentage = line.percentage  -- non-zero
                line_data.production_type = line.recipe.production_type
                line_data.priority_item_proto = line.recipe.priority_item
                line_data.machine_proto = machine.proto
                line_data.machine_limit = {limit=machine.limit, force_limit=machine.force_limit}
                line_data.energy_usage = machine:get_energy_usage()
                line_data.fluid_usage_per_tick = machine:get_fluid_usage_per_tick()
                line_data.resource_drain_rate = machine:get_resource_drain_rate()
                line_data.pollutant_type = (calculate_emissions) and factory.parent.location_proto.pollutant_type or nil
                line_data.entities_require_heating = factory.parent.location_proto.entities_require_heating

                -- Effects - update line with recipe effects here if applicable
                line.recipe:update_effects(player.force--[[@as LuaForce]], factory)
                line_data.total_effects = line.total_effects

                if machine.fuel ~= nil then
                    line_data.fuel_proto = machine.fuel.proto
                    line_data.fuel_name = machine.fuel:get_name_with_temperature()
                    line_data.fuel_value = machine.fuel:get_fuel_value()
                end

                -- The machine needs to potentially run slower if fuel is insufficient
                line_data.fuel_performance, line_data.wasted_share = machine:get_fuel_performance()
                line_data.machine_speed = machine:get_speed() * line_data.fuel_performance

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
            end
        end
    end

    return floor_data
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
            local matrix_metadata = matrix_engine.get_matrix_solver_metadata(factory_data)

            if matrix_metadata.num_rows ~= 0 then  -- don't run calculations if the factory has no lines
                local linear_dependence_data = matrix_engine.get_linear_dependence_data(factory_data, matrix_metadata)

                -- In the case of linearly dependent free items, we remove it automatically if there's only one option.
                -- Otherwise we present the user with a choice to remove problematic free items in the production box.
                local num_ld_free_items, last_ld_free_item = 0, nil
                for _, ld_free_item in pairs(linear_dependence_data.linearly_dependent_free_items) do
                    num_ld_free_items = num_ld_free_items + 1
                    last_ld_free_item = ld_free_item
                end
                if num_ld_free_items == 1 then  ---@cast last_ld_free_item FPItemPrototype
                    for index, item in pairs(factory.matrix_free_items) do
                        if item.type == last_ld_free_item.type and item.name == last_ld_free_item.name then
                            table.remove(factory.matrix_free_items, index)
                            break
                        end
                    end
                    -- Redo all these since we've changed the factory
                    factory_data = solver.generate_factory_data(player, factory)
                    matrix_metadata = matrix_engine.get_matrix_solver_metadata(factory_data)
                    linear_dependence_data = matrix_engine.get_linear_dependence_data(factory_data, matrix_metadata)
                end

                if matrix_metadata.num_rows == matrix_metadata.num_cols
                        and #linear_dependence_data.linearly_dependent_recipes == 0 then
                    matrix_engine.run_matrix_solver(factory_data, false)
                    factory.linearly_dependant = false
                else
                    set_blank_factory(player, factory)  -- reset factory by blanking everything
                    factory.linearly_dependant = true
                end
            else  -- reset top level items
                set_blank_factory(player, factory)
            end
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

    local factory_data = {
        player_index = player.index,
        factory_id = factory.id,
        top_floor = generate_floor_data(player, factory, factory.top_floor, calculate_emissions),
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
---@field production_ratio number?
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

        line.production_ratio = result.production_ratio

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
    end
}

return { listeners }
