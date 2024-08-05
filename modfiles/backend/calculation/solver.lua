local sequential_engine = require("backend.calculation.sequential_engine")
local matrix_engine = require("backend.calculation.matrix_engine")
local structures = require("backend.calculation.structures")
local SimpleItems = require("backend.data.SimpleItems")

solver, solver_util = {}, {}

-- ** LOCAL UTIL **
local function set_blank_line(player, floor, line)
    local blank_class = structures.class.init()
    solver.set_line_result{
        player_index = player.index,
        floor_id = floor.id,
        line_id = line.id,
        machine_count = 0,
        energy_consumption = 0,
        emissions = {},
        production_ratio = (line.class == "Line") and 0 or nil,
        uncapped_production_ratio = (line.class == "Line") and 0 or nil,
        Product = blank_class,
        Byproduct = blank_class,
        Ingredient = blank_class,
        fuel_amount = 0
    }
end

local function set_blank_factory(player, factory)
    local blank_class = structures.class.init()
    local product_class = structures.class.init()

    -- Need to treat products differently because they work differently under the hood
    for product in factory:iterator() do structures.class.add(product_class, product, product:get_required_amount()) end

    solver.set_factory_result {
        player_index = player.index,
        energy_consumption = 0,
        emissions = {},
        Product = product_class,
        Byproduct = blank_class,
        Ingredient = blank_class,
        matrix_free_items = factory.matrix_free_items
    }

    local function set_blank_floor(floor)
        for line in floor:iterator() do
            if line.class == "Floor" then
                set_blank_floor(line)
            else
                set_blank_line(player, floor, line)
            end
        end
    end
    set_blank_floor(factory.top_floor)
end


-- Generates structured data of the given floor for calculation
local function generate_floor_data(player, factory, floor)
    local floor_data = {
        id = floor.id,
        lines = {}
    }

    for line in floor:iterator() do
        local line_data = { id = line.id }

        if line.class == "Floor" then
            line_data.recipe_proto = line.first.recipe_proto
            line_data.subfloor = generate_floor_data(player, factory, line)
            table.insert(floor_data.lines, line_data)
        else
            local relevant_line = (line.parent.level > 1) and line.parent.first or nil
            -- If a line has a percentage of zero or is inactive, it is not useful to the result of the factory
            -- Alternatively, if this line is on a subfloor and the top line of the floor is useless, it is useless too
            if (relevant_line and (relevant_line.percentage == 0 or not relevant_line.active))
                    or line.percentage == 0 or not line.active then
                set_blank_line(player, floor, line)  -- useless lines don't need to run through the solver
            else
                local machine = line.machine
                line_data.recipe_proto = line.recipe_proto
                line_data.timescale = factory.timescale
                line_data.percentage = line.percentage  -- non-zero
                line_data.production_type = line.production_type
                line_data.priority_product_proto = line.priority_product
                line_data.machine_proto = machine.proto
                line_data.machine_limit = {limit=machine.limit, force_limit=machine.force_limit}
                line_data.fuel_proto = machine.fuel and machine.fuel.proto or nil

                -- Quality effects
                local machine_speed = machine.proto.speed
                local quality_category = machine.proto.quality_category
                if quality_category == "assembling-machine" then
                    machine_speed = machine_speed * machine.quality_proto.multiplier
                elseif quality_category == "mining-drill" then
                    -- TBI
                end
                line_data.machine_speed = machine_speed

                -- Effects - update line with recipe effects here if applicable
                machine:update_recipe_effects(player.force)
                line_data.total_effects = line.total_effects

                -- Beacon total - can be calculated here, which is faster and simpler
                if line.beacon ~= nil and line.beacon.total_amount ~= nil then
                    line_data.beacon_consumption = line.beacon.proto.energy_usage * line.beacon.total_amount * 60
                end

                table.insert(floor_data.lines, line_data)
            end
        end
    end

    return floor_data
end


local function update_object_items(object, item_category, item_results)
    local simple_items = object[item_category]
    simple_items:clear()

    for _, item_result in pairs(structures.class.to_array(item_results)) do
        local item_proto = prototyper.util.find_prototype("items", item_result.name, item_result.type)
        simple_items:insert({class="SimpleItem", proto=item_proto, amount=item_result.amount})
    end
end

local function set_zeroed_items(line, item_category, items)
    local simple_items = line[item_category]
    simple_items:clear()

    for _, item in pairs(items) do
        local item_proto = prototyper.util.find_prototype("items", item.name, item.type)
        simple_items:insert({class="SimpleItem", proto=item_proto, amount=0})
    end
end


-- Goes through every line and setting their satisfied_amounts appropriately
local function update_ingredient_satisfaction(floor, product_class)
    product_class = product_class or structures.class.init()

    local function determine_satisfaction(ingredient)
        local product_amount = product_class[ingredient.proto.type][ingredient.proto.name]

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
            local subfloor_product_class = structures.class.copy(product_class)
            update_ingredient_satisfaction(line, subfloor_product_class)
        elseif line.machine.fuel then
            determine_satisfaction(line.machine.fuel)
        end

        for _, ingredient in line.ingredients:iterator() do
            if ingredient.proto.type ~= "entity" then
                determine_satisfaction(ingredient)
            end
        end

        -- Products and byproducts just get added to the list as being produced
        for _, item_category in pairs{"products", "byproducts"} do
            for _, product in line[item_category]:iterator() do
                structures.class.add(product_class, product)
            end
        end
    end
end


-- ** TOP LEVEL **
-- Updates the whole factory calculations from top to bottom
function solver.update(player, factory, blank)
    factory = factory or util.context.get(player, "Factory")
    if factory.valid then
        local player_table = util.globals.player_table(player)
        -- Save the active factory in global so the solver doesn't have to pass it around
        player_table.active_factory = factory

        local factory_data = solver.generate_factory_data(player, factory)

        if blank then  -- sets factory to a blank state
            set_blank_factory(player, factory)
        elseif factory.matrix_free_items ~= nil then  -- meaning the matrix solver is active
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

        player_table.active_factory = nil  -- reset after calculations have been carried out
    end
end

-- Updates the given factory's ingredient satisfactions
function solver.determine_ingredient_satisfaction(factory)
    update_ingredient_satisfaction(factory.top_floor, nil)
end


-- ** INTERFACE **
-- Returns a table containing all the data needed to run the calculations for the given factory
function solver.generate_factory_data(player, factory)
    local factory_data = {
        player_index = player.index,
        top_level_products = {},
        top_floor = generate_floor_data(player, factory, factory.top_floor),
        matrix_free_items = factory.matrix_free_items
    }

    for product in factory:iterator() do
        local product_data = {
            proto = product.proto,  -- reference
            amount = product:get_required_amount()
        }
        table.insert(factory_data.top_level_products, product_data)
    end

    return factory_data
end

-- Updates the active factories top-level data with the given result
function solver.set_factory_result(result)
    local player_table = global.players[result.player_index]
    local factory = player_table.active_factory

    if factory.parent then factory.parent.needs_refresh = true end

    factory.top_floor.power = result.energy_consumption
    factory.top_floor.emissions = result.emissions
    factory.matrix_free_items = result.matrix_free_items

    -- If products are not present in the result, it means they have been produced
    for product in factory:iterator() do
        local product_result_amount = result.Product[product.proto.type][product.proto.name] or 0
        product.amount = product:get_required_amount() - product_result_amount
    end

    update_object_items(factory.top_floor, "ingredients", result.Ingredient)
    update_object_items(factory.top_floor, "byproducts", result.Byproduct)

    -- Determine satisfaction-amounts for all line ingredients
    if player_table.preferences.ingredient_satisfaction then
        solver.determine_ingredient_satisfaction(factory)
    end
end

-- Updates the given line of the given floor of the active factory
function solver.set_line_result(result)
    local factory = global.players[result.player_index].active_factory
    if factory == nil then return end
    local line = OBJECT_INDEX[result.line_id]

    if line.class == "Floor" then
        line.machine_count = result.machine_count
    else
        line.machine.amount = result.machine_count
        if line.machine.fuel ~= nil then line.machine.fuel.amount = result.fuel_amount end

        line.production_ratio = result.production_ratio
        line.uncapped_production_ratio = result.uncapped_production_ratio
    end

    line.power = result.energy_consumption
    line.emissions = result.emissions

    if line.production_ratio == 0 and line.subfloor == nil then
        local recipe_proto = line.recipe_proto
        set_zeroed_items(line, "products", recipe_proto.products)
        line.byproducts:clear()
        set_zeroed_items(line, "ingredients", recipe_proto.ingredients)
    else
        update_object_items(line, "products", result.Product)
        update_object_items(line, "byproducts", result.Byproduct)
        update_object_items(line, "ingredients", result.Ingredient)
    end
end


-- **** UTIL ****
-- Speed, consumption and pollution can't go lower than 20%, or higher than 32676% due to the engine limit
local function cap_effect(value)
    return math.min(math.max(value, MAGIC_NUMBERS.effects_lower_bound), MAGIC_NUMBERS.effects_upper_bound)
end

-- Determines the number of crafts per tick for the given data
function solver_util.determine_crafts_per_tick(machine_speed, recipe_proto, total_effects)
    return (machine_speed * (1 + cap_effect(total_effects.speed))) / recipe_proto.energy
end

-- Determine the amount of machines needed to produce the given recipe in the given context
function solver_util.determine_machine_count(crafts_per_tick, production_ratio, timescale)
    return production_ratio / (crafts_per_tick * timescale)
end

-- Calculates the production ratio that the given amount of machines would result in
-- Formula derived from determine_machine_count(), isolating production_ratio and using machine_limit as machine_count
function solver_util.determine_production_ratio(crafts_per_tick, machine_limit, timescale)
    return crafts_per_tick * machine_limit * timescale
end

-- Calculates the product amount after applying productivity bonuses
function solver_util.determine_prodded_amount(item, total_effects, maximum_productivity)
    -- No negative productivity, and none above the recipe-determined cap
    local productivity = math.min(math.max(total_effects.productivity, 0), maximum_productivity)
    if productivity == 0 then return item.amount end

    -- Return formula is a simplification of the following formula:
    -- item.amount - item.proddable_amount + (item.proddable_amount * (productivity + 1))
    return item.amount + (item.proddable_amount * productivity)
end

-- Determines the amount of energy needed for a machine and the emissions that produces
function solver_util.determine_energy_consumption_and_emissions(machine_proto, recipe_proto,
        fuel_proto, machine_count, total_effects)
    local consumption_multiplier = 1 + cap_effect(total_effects.consumption)
    local energy_consumption = machine_count * (machine_proto.energy_usage * 60) * consumption_multiplier
    local drain = math.ceil(machine_count - 0.001) * (machine_proto.energy_drain * 60)

    local fuel_multiplier = (fuel_proto ~= nil) and fuel_proto.emissions_multiplier or 1
    local pollution_multiplier = 1 + cap_effect(total_effects.pollution)
    local total_multiplier = fuel_multiplier * pollution_multiplier * recipe_proto.emissions_multiplier

    local emissions = {}  -- Emissions are per minute, so multiply everything by 60
    for type, amount in pairs(machine_proto.emissions_per_joule) do
        emissions[type] = energy_consumption * amount * total_multiplier * 60
    end
    for type, amount in pairs(machine_proto.emissions_per_second) do
        emissions[type] = (emissions[type] or 0) + (machine_count * amount * total_multiplier * 60)
    end

    return (energy_consumption + drain), emissions
end

-- Determines the amount of fuel needed in the given context
function solver_util.determine_fuel_amount(energy_consumption, burner, fuel_value, timescale)
    return ((energy_consumption / burner.effectivity) / fuel_value) * timescale
end
