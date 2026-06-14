local sequential_engine = require("backend.calculation.sequential_engine")
local matrix_engine = require("backend.calculation.matrix_engine")
local structures = require("backend.calculation.structures")

solver, solver_util = {}, {}

-- ** LOCAL UTIL **
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

local function get_temperature_name(line, ingredient)
    local name, temperature = ingredient.name, nil
    if ingredient.type == "fluid" then
        temperature = line.recipe.temperatures[ingredient.name]
        name = (temperature ~= nil) and (ingredient.name .. "-" .. temperature) or nil
    end

    return name, temperature
end

local function line_ingredients(line)
    local ingredients = {}
    for _, ingredient in pairs(line.recipe.proto.ingredients) do
        local name, temperature = get_temperature_name(line, ingredient)
        -- If any relevant ingredient has no temperature set, this line is invalid
        if name == nil then return nil end

        table.insert(ingredients, {
            name = name,
            type = ingredient.type,
            amount = ingredient.amount,
            temperature = temperature
        })  -- don't need min/max temperatures here
    end
    return ingredients
end


-- Generates structured data of the given floor for calculation
local function generate_floor_data(player, factory, floor, calculate_emissions)
    local floor_data = {
        id = floor.id,
        products = (floor.level == 1) and factory_products(factory)
            or floor.first.recipe.proto.products,
        lines = {}
    }

    for line in floor:iterator() do
        local line_data = { id = line.id }

        if line.class == "Floor" then
            line_data.recipe_proto = line.first.recipe.proto
            line_data.subfloor = generate_floor_data(player, factory, line, calculate_emissions)
            table.insert(floor_data.lines, line_data)
        else
            local relevant_line = (line.parent.level > 1) and line.parent.first or nil  --[[@as Line]]
            local ingredients = line_ingredients(line)  -- builds in chosen temperatures

            local fuel = line.machine.fuel
            local missing_fuel_temp = (fuel and fuel.proto.type == "fluid" and not fuel.temperature)

            -- If a line has a percentage of zero or is inactive, it is not useful to the result of the factory
            -- Alternatively, if this line is on a subfloor and the top line of the floor is useless, it is useless too
            if (relevant_line and (relevant_line.percentage == 0 or not relevant_line.active))
                    or line.percentage == 0 or not line.active or not line:get_surface_compatibility().overall
                    or (not factory.matrix_solver_active and line.recipe.production_type == "consume")
                    or ingredients == nil or missing_fuel_temp == true then
                set_blank_line(player, floor, line)  -- useless lines don't need to run through the solver
            else
                local machine = line.machine
                line_data.recipe_proto = line.recipe.proto
                line_data.recipe_energy = line.recipe.proto.energy
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

                -- Boiler recipe energy
                if machine.proto.prototype_category == "boiler" then
                    local goal_temperature = line.recipe.proto.products[1].temperature
                    local fluid_name = line.recipe.proto.ingredients[1].name
                    local heat_capacity = prototypes.fluid[fluid_name].heat_capacity
                    local input_temperature = ingredients[1].temperature
                    line_data.recipe_energy = (goal_temperature - input_temperature) * heat_capacity
                end

                -- Effects - update line with recipe effects here if applicable
                line.recipe:update_effects(player.force, factory)
                line_data.total_effects = line.total_effects

                -- Beacon total - can be calculated here, which is faster and simpler
                if line.beacon ~= nil and line.beacon.total_amount ~= nil then
                    line_data.beacon_consumption = line.beacon:get_total_consumption()
                end

                if machine.fuel then
                    line_data.fuel_proto = machine.fuel.proto
                    line_data.fuel_name = (fuel.proto.type ~= "fluid") and fuel.proto.name
                        or (fuel.proto.name .. "-" .. fuel.temperature)
                end

                table.insert(floor_data.lines, line_data)
            end
        end
    end

    return floor_data
end


---@class SimpleItem
---@field proto FPItemPrototype
---@field amount number
---@field satisfied_amount number?

local function item_comparator(a, b)
    local a_type, b_type = a.proto.type, b.proto.type
    if a_type < b_type then return false
    elseif a_type > b_type then return true
    elseif a.amount < b.amount then return false
    elseif a.amount > b.amount then return true end
    return false
end

local function update_object_items(object, item_category, item_results)
    local item_list = {}

    for _, item_result in pairs(structures.class.list(item_results)) do
        local item_proto = prototyper.util.find("items", item_result.name, item_result.type)  --[[@as FPItemPrototype]]

        -- Floor items keep their temperature, since they can't be configured from there
        if object.class ~= "Floor" and item_category == "ingredients" and item_proto.base_name then
            item_proto = prototyper.util.find("items", item_proto.base_name, "fluid")
        end

        if object.class ~= "Floor" or item_proto.type ~= "entity" or item_proto.special then
            table.insert(item_list, {proto=item_proto, amount=item_result.amount})
        end
    end

    table.sort(item_list, item_comparator)
    object[item_category] = item_list
end

local function set_zeroed_items(line, item_category, items)
    local item_list = {}

    for _, item in pairs(items) do
        local item_proto = prototyper.util.find("items", item.name, item.type)
        table.insert(item_list, {proto=item_proto, amount=0})
    end

    line[item_category] = item_list
end


-- Goes through every line and setting their satisfied_amounts appropriately
local function update_ingredient_satisfaction(floor, product_class)
    product_class = product_class or structures.class.init()

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
            local subfloor_product_class = util.flib.deep_copy(product_class)
            update_ingredient_satisfaction(line, subfloor_product_class)
        elseif line.machine.fuel then
            local fuel = line.machine.fuel
            local name = (fuel.temperature) and (fuel.proto.name .. "-" .. fuel.temperature) or fuel.proto.name
            determine_satisfaction(fuel, name)
        end

        for _, ingredient in pairs(line.ingredients) do
            if ingredient.proto.type ~= "entity" or ingredient.proto.special then
                local name = ingredient.proto.name
                if line.class ~= "Floor" then name, _ = get_temperature_name(line, ingredient.proto) end
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
-- Updates the whole factory calculations from top to bottom
function solver.update(player, factory)
    factory = factory or util.context.get(player, "Factory")
    if factory and factory.valid then
        -- Cancel any pending update as it'll be running right now
        if factory.tick_of_solver_update then
            util.nth_tick.cancel(factory.tick_of_solver_update)
            factory.tick_of_solver_update = nil
        end

        local factory_data = solver.generate_factory_data(player, factory)

        if factory.matrix_solver_active then
            local matrix_metadata = matrix_engine.get_matrix_solver_metadata(factory_data)

            if matrix_metadata.num_cols > matrix_metadata.num_rows and #factory.matrix_free_items > 0 then
                factory.matrix_free_items = {}
                factory_data = solver.generate_factory_data(player, factory)
                matrix_metadata = matrix_engine.get_matrix_solver_metadata(factory_data)
            end

            if matrix_metadata.num_rows ~= 0 then  -- don't run calculations if the factory has no lines
                local linear_dependence_data = matrix_engine.get_linear_dependence_data(factory_data, matrix_metadata)
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

-- Updates the given factory's ingredient satisfactions
function solver.determine_ingredient_satisfaction(factory)
    if not factory.valid then return end
    update_ingredient_satisfaction(factory.top_floor, nil)
end


-- ** INTERFACE **
-- Returns a table containing all the data needed to run the calculations for the given factory
function solver.generate_factory_data(player, factory)
    local calculate_emissions = util.globals.preferences(player).calculate_emissions
    local factory_data = {
        player_index = player.index,
        factory_id = factory.id,
        top_floor = generate_floor_data(player, factory, factory.top_floor, calculate_emissions),
        matrix_free_items = factory.matrix_free_items
    }

    return factory_data
end

-- Updates the active factories top-level data with the given result
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
    if util.globals.preferences(player).ingredient_satisfaction then
        solver.determine_ingredient_satisfaction(factory)
    end
end

-- Updates the given line of the given floor of the active factory
function solver.set_line_result(result)
    local line = OBJECT_INDEX[result.line_id]  --[[@as LineObject]]

    if line.class == "Floor" then
        line.machine_amount = result.machine_amount
    else
        line.machine.amount = result.machine_amount
        if line.machine.fuel ~= nil then line.machine.fuel.amount = result.fuel_amount end

        line.production_ratio = result.production_ratio
    end

    if line.production_ratio == 0 then
        local recipe_proto = line.recipe.proto
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
-- Calculates the product amount after applying productivity bonuses
function solver_util.determine_prodded_amount(item, total_effects, maximum_productivity)
    -- No negative productivity, and none above the recipe-determined cap
    local productivity = math.min(math.max(total_effects.productivity, 0), maximum_productivity)
    if productivity == 0 then return item.amount end

    -- Return formula is a simplification of the following formula:
    -- item.amount - item.proddable_amount + (item.proddable_amount *
    --   (1 + (productivity / MAGIC_NUMBERS.effect_precision)))
    return item.amount + (item.proddable_amount * (productivity / MAGIC_NUMBERS.effect_precision))
end

-- Determines the amount of energy needed for a machine and the emissions that produces
function solver_util.determine_energy_consumption_and_emissions(machine_proto, recipe_proto,
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

-- Determines the amount of fuel needed in the given context
function solver_util.determine_fuel_amount(energy_consumption, burner, fuel_value)
    return (energy_consumption / burner.effectivity) / fuel_value
end


-- ** EVENTS **
local listeners = {}

listeners.global = {
    update_solver = (function(metadata)
        local player = game.get_player(metadata.player_index)
        local factory = OBJECT_INDEX[metadata.factory_id]
        solver.update(player, factory)
    end)
}

return { listeners }
