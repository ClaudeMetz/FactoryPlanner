local sequential_engine = require("backend.calculation.sequential_engine")
local matrix_engine = require("backend.calculation.matrix_engine")
local structures = require("backend.calculation.structures")

solver = {
    util = {}
}

-- ** LOCAL UTIL **
---@param player LuaPlayer
---@param floor Floor
---@param line LineObject
local function set_blank_line(player, floor, line)
    local blank_class = structures.class.init()
    solver.set_line_result {
        player_index = player.index,
        floor_id = floor.id,
        line_id = line.id,
        machine_amount = 0,
        production_ratio = (line.class == "Line") and 0 or nil,
        Product = blank_class,
        Byproduct = blank_class,
        Ingredient = blank_class,
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
    local blank_class = structures.class.init()

    solver.set_factory_result {
        player_index = player.index,
        factory_id = factory.id,
        Product = blank_class,
        Byproduct = blank_class,
        Ingredient = blank_class,
        matrix_free_items = factory.matrix_free_items
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

---@param line Line
---@return SolverItem[]?
local function line_ingredients(line)
    local ingredients = {}
    for _, ingredient in pairs(line.recipe.proto--[[@as FPRecipePrototype]].ingredients) do
        -- If any relevant ingredient has no temperature set, this line is invalid
        if not line.recipe:is_temperature_configured(ingredient) then return nil end

        table.insert(ingredients, {
            name = line.recipe:get_name_with_temperature(ingredient),
            type = ingredient.type,
            amount = ingredient.amount,
            temperature = line.recipe:get_temperature(ingredient)
        })  -- don't need min/max temperatures here
    end
    return ingredients
end

---@class FloorData
---@field id ObjectID
---@field products FormattedProduct[] | SolverItem[]
---@field lines (LineData | SubfloorLineData)[]

---@class SubfloorLineData
---@field id ObjectID
---@field recipe_proto FPRecipePrototype
---@field subfloor FloorData?

---@class LineData
---@field id ObjectID
---@field recipe_proto FPRecipePrototype
---@field recipe_energy double
---@field ingredients SolverItem[]
---@field percentage number
---@field production_type RecipeProductionType
---@field priority_product_proto FPItemPrototype
---@field machine_proto FPMachinePrototype
---@field machine_limit MachineLimit
---@field machine_speed double
---@field energy_usage double
---@field resource_drain_rate double
---@field pollutant_type string?
---@field entities_require_heating boolean
---@field total_effects IntegerModuleEffects
---@field beacon_consumption double
---@field fuel_proto AnyFPFuelPrototype?
---@field fuel_name string?

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
            or floor.first--[[@as Line]].recipe.proto--[[@as FPRecipePrototype]].products,
        lines = {}
    }  ---@type FloorData

    for line in floor:iterator() do
        local line_data = { id = line.id }

        if line.class == "Floor" then  ---@cast line Floor
            line_data.recipe_proto = line.first--[[@as Line]].recipe.proto
            line_data.subfloor = generate_floor_data(player, factory, line, calculate_emissions)
            table.insert(floor_data.lines, line_data)
        else  ---@cast line Line
            local relevant_line = (line.parent.level > 1) and line.parent.first or nil  --[[@as Line]]
            local recipe_proto = line.recipe.proto  --[[@as FPRecipePrototype]]
            local ingredients = line_ingredients(line)  -- builds in chosen temperatures
            local fuel = line.machine.fuel

            -- If a line has a percentage of zero or is inactive, it is not useful to the result of the factory
            -- Alternatively, if this line is on a subfloor and the top line of the floor is useless, it is useless too
            if (relevant_line and (relevant_line.percentage == 0 or not relevant_line.active))
                    or line.percentage == 0 or not line.active or not line:get_surface_compatibility().overall
                    or (not factory.matrix_solver_active and line.recipe.production_type == "consume")
                    or ingredients == nil or (fuel and not fuel:is_temperature_configured()) then
                set_blank_line(player, floor, line)  -- useless lines don't need to run through the solver
            else
                local machine = line.machine
                line_data.recipe_proto = recipe_proto
                line_data.recipe_energy = recipe_proto.energy
                line_data.ingredients = ingredients
                line_data.percentage = line.percentage  -- non-zero
                line_data.production_type = line.recipe.production_type
                line_data.priority_product_proto = line.recipe.priority_product
                line_data.machine_proto = machine.proto
                line_data.machine_limit = {limit=machine.limit, force_limit=machine.force_limit}
                line_data.machine_speed = machine:get_speed()
                line_data.energy_usage = machine:get_energy_usage()
                line_data.resource_drain_rate = machine:get_resource_drain_rate()
                line_data.pollutant_type = (calculate_emissions) and factory.parent.location_proto.pollutant_type or nil
                line_data.entities_require_heating = factory.parent.location_proto.entities_require_heating

                -- Boiler recipe energy
                if machine.proto.prototype_category == "boiler" then
                    local goal_temperature = recipe_proto.products[1]--[[@cast -nil]].temperature  --[[@as float]]
                    local fluid_name = recipe_proto.ingredients[1]--[[@cast -nil]].name
                    local heat_capacity = prototypes.fluid[fluid_name].heat_capacity
                    local input_temperature = ingredients[1]--[[@cast -nil]].temperature  --[[@as float]]
                    line_data.recipe_energy = (goal_temperature - input_temperature) * heat_capacity
                end

                -- Effects - update line with recipe effects here if applicable
                line.recipe:update_effects(player.force--[[@as LuaForce]], factory)
                line_data.total_effects = line.total_effects

                -- Beacon total - can be calculated here, which is faster and simpler
                if line.beacon ~= nil and line.beacon.total_amount ~= nil then
                    line_data.beacon_consumption = line.beacon:get_total_consumption()
                end

                if fuel ~= nil then
                    line_data.fuel_proto = fuel.proto
                    line_data.fuel_name = fuel:get_name_with_temperature()
                end

                table.insert(floor_data.lines, line_data)
            end
        end
    end

    return floor_data
end


---@class SimpleItem
---@field class "SimpleItem"
---@field proto FPItemPrototype
---@field amount number
---@field satisfied_amount number?

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
---@param item_results SolverClass
local function update_object_items(object, item_category, item_results)
    local item_list = {}

    for _, item_result in pairs(structures.class.list(item_results)) do
        local item_proto = prototyper.util.find("items", item_result.name, item_result.type)  --[[@as FPItemPrototype]]

        -- Floor items keep their temperature, since they can't be configured from there
        if object.class ~= "Floor" and item_category == "ingredients" and item_proto.base_name then
            item_proto = prototyper.util.find("items", item_proto.base_name, "fluid")  --[[@as FPItemPrototype]]
        end

        if object.class ~= "Floor" or item_proto.type ~= "entity" or item_proto.special then
            table.insert(item_list, {class="SimpleItem", proto=item_proto, amount=item_result.amount})
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
        local item_proto = prototyper.util.find("items", item.name, item.type)
        table.insert(item_list, {class="SimpleItem", proto=item_proto, amount=0})
    end

    line[item_category] = item_list
end


--- Goes through every line and setting their satisfied_amounts appropriately
---@param floor Floor
---@param product_class SolverClass?
local function update_ingredient_satisfaction(floor, product_class)
    product_class = product_class or structures.class.init()

    ---@param ingredient SimpleItem | Fuel
    ---@param name string
    local function determine_satisfaction(ingredient, name)
        local product_amount = product_class[ingredient.proto.type][name]

        if product_amount ~= nil then
            if product_amount >= ingredient.amount then
                ingredient.satisfied_amount = ingredient.amount
                structures.class.subtract(product_class, ingredient)
            else  -- product_amount < ingredient.amount
                ingredient.satisfied_amount = product_amount
                structures.class.subtract(product_class, ingredient, product_amount)
            end
        else
            ingredient.satisfied_amount = 0
        end
    end

    -- Iterates the lines from the bottom up, setting satisfaction amounts along the way
    for line in floor:iterator(nil, floor:find_last(), "previous") do
        if line.class == "Floor" then
            local subfloor_product_class = lib.flib.deep_copy(product_class)
            update_ingredient_satisfaction(line, subfloor_product_class)
        elseif line.machine.fuel then
            local fuel = line.machine.fuel
            determine_satisfaction(fuel, fuel:get_name_with_temperature())
        end

        for _, ingredient in pairs(line.ingredients) do
            if ingredient.proto.type ~= "entity" or ingredient.proto.special then
                local name = ingredient.proto.name
                if line.class ~= "Floor" then name = line.recipe:get_name_with_temperature(ingredient) end
                determine_satisfaction(ingredient, name)
            end
        end

        -- Products and byproducts just get added to the list as being produced
        for _, item_category in pairs{"products", "byproducts"} do
            for _, product in pairs(line[item_category]) do
                structures.class.add(product_class, product)
            end
        end
    end
end


-- ** TOP LEVEL **
--- Updates the whole factory calculations from top to bottom
---@param player LuaPlayer
---@param factory Factory?
function solver.update(player, factory)
    factory = factory or lib.context.get(player, "Factory")
    if factory and factory.valid then
        -- Cancel any pending update as it'll be running right now
        if factory.tick_of_solver_update then
            lib.nth_tick.cancel(factory.tick_of_solver_update)
            factory.tick_of_solver_update = nil
        end

        local factory_data = solver.generate_factory_data(player, factory)

        if factory.matrix_solver_active then  ---@cast factory.matrix_free_items -nil
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

                ---@diagnostic disable-next-line: undefined-field
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
        else
            sequential_engine.update_factory(factory_data)
        end
    end
end

---@param factory Factory
function solver.determine_ingredient_satisfaction(factory)
    if not factory.valid then return end
    update_ingredient_satisfaction(factory.top_floor, nil)
end


-- ** INTERFACE **
---@class FactoryData
---@field player_index uint32
---@field factory_id ObjectID
---@field top_floor FloorData
---@field matrix_free_items FPItemPrototype[]?

--- Returns a table containing all the data needed to run the calculations for the given factory
---@param player LuaPlayer
---@param factory Factory
---@return FactoryData
function solver.generate_factory_data(player, factory)
    local calculate_emissions = lib.globals.preferences(player).calculate_emissions
    local factory_data = {
        player_index = player.index,
        factory_id = factory.id,
        top_floor = generate_floor_data(player, factory, factory.top_floor, calculate_emissions),
        matrix_free_items = factory.matrix_free_items
    }

    return factory_data
end

---@class FactoryResult
---@field player_index uint32
---@field factory_id ObjectID
---@field matrix_free_items FPItemPrototype[]?
---@field Product SolverClass
---@field Byproduct SolverClass
---@field Ingredient SolverClass

--- Updates the active factories top-level data with the given result
---@param result FactoryResult
function solver.set_factory_result(result)
    local factory = OBJECT_INDEX[result.factory_id]  --[[@as Factory]]

    if factory.parent then factory.parent.needs_refresh = true end

    factory.matrix_free_items = result.matrix_free_items or {}

    for product in factory:iterator() do
        local product_result_amount = result.Product[product.proto.type][product.proto.name] or 0
        product.amount = product_result_amount or 0
    end

    update_object_items(factory.top_floor, "byproducts", result.Byproduct)
    update_object_items(factory.top_floor, "ingredients", result.Ingredient)

    -- Determine satisfaction-amounts for all line ingredients
    local player = game.players[result.player_index]
    if lib.globals.preferences(player).ingredient_satisfaction then
        solver.determine_ingredient_satisfaction(factory)
    end
end

---@class LineResult
---@field player_index uint32
---@field floor_id ObjectID
---@field line_id ObjectID
---@field machine_amount number
---@field production_ratio number?
---@field Product SolverClass
---@field Byproduct SolverClass
---@field Ingredient SolverClass
---@field fuel_amount number?

--- Updates the given line of the given floor of the active factory
---@param result LineResult
function solver.set_line_result(result)
    local line = OBJECT_INDEX[result.line_id]  --[[@as LineObject]]

    if line.class == "Floor" then  ---@cast line Floor
        line.machine_amount = result.machine_amount  --[[@as integer]]
    else  ---@cast line Line
        line.machine.amount = result.machine_amount
        if line.machine.fuel ~= nil then line.machine.fuel.amount = result.fuel_amount end

        line.production_ratio = result.production_ratio
    end

    if line.production_ratio == 0 then  ---@cast line Line
        local recipe_proto = line.recipe.proto  --[[@as FPRecipePrototype]]
        set_zeroed_items(line, "products", recipe_proto.products)
        line.byproducts = {}
        set_zeroed_items(line, "ingredients", recipe_proto.ingredients)
    else
        update_object_items(line, "products", result.Product)
        update_object_items(line, "byproducts", result.Byproduct)
        update_object_items(line, "ingredients", result.Ingredient)
    end
end


-- ** UTIL **
--- Calculates the product amount after applying productivity bonuses
---@param item FormattedProduct
---@param total_effects IntegerModuleEffects
---@return number
function solver.util.determine_prodded_amount(item, total_effects)
    if total_effects.productivity <= 0 then return item.amount end  -- no negative productivity

    -- Return formula is a simplification of the following formula:
    -- item.amount - item.proddable_amount + (item.proddable_amount *
    --   (1 + (productivity / MAGIC_NUMBERS.effect_precision)))
    return item.amount + (item.proddable_amount * (total_effects.productivity / MAGIC_NUMBERS.effect_precision))
end

--- Determines the amount of energy needed for a machine and the emissions that produces
---@param machine_proto FPMachinePrototype
---@param recipe_proto FPRecipePrototype
---@param fuel_proto AnyFPFuelPrototype?
---@param machine_amount number
---@param energy_usage number
---@param total_effects IntegerModuleEffects
---@param pollutant_type string?
---@return number, number
function solver.util.determine_energy_consumption_and_emissions(machine_proto, recipe_proto,
        fuel_proto, machine_amount, energy_usage, total_effects, pollutant_type)
    local consumption_multiplier = 1 + (total_effects.consumption / MAGIC_NUMBERS.effect_precision)
    local energy_consumption = machine_amount * (energy_usage * 60) * consumption_multiplier
    local drain = math.ceil(machine_amount - MAGIC_NUMBERS.margin_of_error) * (machine_proto.energy_drain * 60)
    local total_consumption = energy_consumption + drain

    if pollutant_type == nil then return total_consumption, 0 end

    local fuel_multiplier = (fuel_proto ~= nil) and fuel_proto.emissions_multiplier or 1
    local pollution_multiplier = 1 + (total_effects.pollution / MAGIC_NUMBERS.effect_precision)
    local total_multiplier = fuel_multiplier * pollution_multiplier * recipe_proto.emissions_multiplier

    local emissions_per_joule = energy_consumption * (machine_proto.emissions_per_joule[pollutant_type] or 0)
    local emissions_per_second = machine_amount * (machine_proto.emissions_per_second[pollutant_type] or 0)
    local total_emissions = (emissions_per_joule + emissions_per_second) * total_multiplier * 60

    return total_consumption, total_emissions
end

--- Determines the amount of fuel needed in the given context
---@param energy_consumption number
---@param burner MachineBurner
---@param fuel_value float
---@return number
function solver.util.determine_fuel_amount(energy_consumption, burner, fuel_value)
    return (energy_consumption / burner.effectivity) / fuel_value
end


-- ** EVENTS **
local listeners = {}

listeners.global = {
    update_solver = (function(metadata)
        local player = game.get_player(metadata.player_index)  --[[@as LuaPlayer]]
        local factory = OBJECT_INDEX[metadata.factory_id]
        solver.update(player, factory)
    end)
}

return { listeners }
