local sequential_engine = require("backend.calculation.sequential_engine")
local matrix_engine = require("backend.calculation.matrix_engine")
local structures = require("backend.calculation.structures")

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
        emissions = 0,
        production_ratio = (line.class == "Line") and 0 or nil,
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
    for product in factory:iterator() do
        structures.class.add(product_class, product.proto, product:get_required_amount())
    end

    solver.set_factory_result {
        player_index = player.index,
        factory_id = factory.id,
        energy_consumption = 0,
        emissions = 0,
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
            local relevant_line = (line.parent.level > 1) and line.parent.first or nil  --[[@as Line]]
            -- If a line has a percentage of zero or is inactive, it is not useful to the result of the factory
            -- Alternatively, if this line is on a subfloor and the top line of the floor is useless, it is useless too
            if (relevant_line and (relevant_line.percentage == 0 or not relevant_line.active))
                    or line.percentage == 0 or not line.active or not line:get_surface_compatibility().overall then
                set_blank_line(player, floor, line)  -- useless lines don't need to run through the solver
            else
                local machine = line.machine
                line_data.recipe_proto = line.recipe_proto
                line_data.percentage = line.percentage  -- non-zero
                line_data.production_type = line.production_type
                line_data.priority_product_proto = line.priority_product
                line_data.machine_proto = machine.proto
                line_data.machine_limit = {limit=machine.limit, force_limit=machine.force_limit}
                line_data.fuel_proto = machine.fuel and machine.fuel.proto or nil
                line_data.pollutant_type = factory.parent.location_proto.pollutant_type

                -- Quality effects
                local machine_speed = machine.proto.speed
                local resource_drain_rate = machine.proto.resource_drain_rate or 1

                local quality_category = machine.proto.quality_category
                if quality_category == "assembling-machine" then
                    machine_speed = machine_speed * machine.quality_proto.multiplier
                elseif quality_category == "mining-drill" then
                    resource_drain_rate = resource_drain_rate
                        * machine.quality_proto.mining_drill_resource_drain_multiplier
                end
                line_data.machine_speed = machine_speed
                line_data.resource_drain_rate = resource_drain_rate

                -- Effects - update line with recipe effects here if applicable
                machine:update_recipe_effects(player.force, factory)
                line_data.total_effects = line.total_effects

                -- Beacon total - can be calculated here, which is faster and simpler
                local beacon = line.beacon
                if beacon ~= nil and beacon.total_amount ~= nil then
                    line_data.beacon_consumption = beacon.proto.energy_usage * beacon.total_amount * 60
                        * beacon.quality_proto.beacon_power_usage_multiplier
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

    for _, item_result in pairs(structures.class.list(item_results)) do
        local item_proto = prototyper.util.find("items", item_result.name, item_result.type)  --[[@as FPItemPrototype]]
        if object.class ~= "Floor" or item_proto.type ~= "entity" then
            simple_items:insert({class="SimpleItem", proto=item_proto, amount=item_result.amount})
        end
    end
end

local function set_zeroed_items(line, item_category, items)
    local simple_items = line[item_category]
    simple_items:clear()

    for _, item in pairs(items) do
        local item_proto = prototyper.util.find("items", item.name, item.type)
        simple_items:insert({class="SimpleItem", proto=item_proto, amount=0})
    end
end


-- Goes through every line and setting their satisfied_amounts appropriately
local function update_ingredient_satisfaction(floor, product_class)
    product_class = product_class or structures.class.init()

    local function determine_satisfaction(ingredient)
        local product= structures.class.find(product_class, ingredient.proto)

        if product ~= nil then
            if product.amount >= ingredient.amount then
                ingredient.satisfied_amount = ingredient.amount
                structures.class.subtract(product_class, ingredient.proto, ingredient.amount)
            else  -- product_amount < ingredient.amount
                ingredient.satisfied_amount = product.amount
                structures.class.subtract(product_class, ingredient.proto, product.amount)
            end
        else
            ingredient.satisfied_amount = 0
        end
    end

    -- Iterates the lines from the bottom up, setting satisfaction amounts along the way
    for line in floor:iterator(nil, floor:find_last(), "previous") do
        if line.class == "Floor" then
            local subfloor_product_class = ftable.deep_copy(product_class)
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
                structures.class.add(product_class, product.proto, product.amount)
            end
        end
    end
end


-- ** TOP LEVEL **
-- Updates the whole factory calculations from top to bottom
function solver.update(player, factory, blank)
    factory = factory or util.context.get(player, "Factory")
    if factory.valid then
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
        factory_id = factory.id,
        top_level_products = {},
        top_floor = generate_floor_data(player, factory, factory.top_floor),
        matrix_free_items = factory.matrix_free_items
    }

    for product in factory:iterator() do
        local product_data = {
            name = product.proto.name,
            type = product.proto.type,
            amount = product:get_required_amount()
        }
        table.insert(factory_data.top_level_products, product_data)
    end

    return factory_data
end

-- Updates the active factories top-level data with the given result
function solver.set_factory_result(result)
    local factory = OBJECT_INDEX[result.factory_id]  --[[@as Factory]]

    if factory.parent then factory.parent.needs_refresh = true end

    factory.top_floor.power = result.energy_consumption
    factory.top_floor.emissions = result.emissions
    factory.matrix_free_items = result.matrix_free_items

    -- If products are not present in the result, it means they have been produced
    for product in factory:iterator() do
        local result_product = structures.class.find(result.Product, product.proto)
        local result_amount = (result_product) and result_product.amount or 0
        product.amount = product:get_required_amount() - result_amount
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
        line.machine_count = result.machine_count
    else
        line.machine.amount = result.machine_count
        if line.machine.fuel ~= nil then line.machine.fuel.amount = result.fuel_amount end

        line.production_ratio = result.production_ratio
    end

    line.power = result.energy_consumption
    line.emissions = result.emissions

    if line.production_ratio == 0 then
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
        fuel_proto, machine_count, total_effects, pollutant_type)
    local energy_consumption = machine_count * (machine_proto.energy_usage * 60) * (1 + total_effects.consumption)
    local drain = math.ceil(machine_count - 0.001) * (machine_proto.energy_drain * 60)
    local total_consumption = energy_consumption + drain

    if pollutant_type == nil then return total_consumption, 0 end

    local fuel_multiplier = (fuel_proto ~= nil) and fuel_proto.emissions_multiplier or 1
    local total_multiplier = fuel_multiplier * (1 + total_effects.pollution) * recipe_proto.emissions_multiplier

    local emissions_per_joule = energy_consumption * (machine_proto.emissions_per_joule[pollutant_type] or 0)
    local emissions_per_second = machine_count * (machine_proto.emissions_per_second[pollutant_type] or 0)
    local total_emissions = (emissions_per_joule + emissions_per_second) * total_multiplier * 60

    return total_consumption, total_emissions
end

-- Determines the amount of fuel needed in the given context
function solver_util.determine_fuel_amount(energy_consumption, burner, fuel_value)
    return (energy_consumption / burner.effectivity) / fuel_value
end
