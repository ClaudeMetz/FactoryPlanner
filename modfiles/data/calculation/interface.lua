require("model")
require("structures")

calculation = {
    interface = {},
    util = {}
}


-- ** LOCAL UTIL **
-- Generates structured data of the given floor for calculation
local function generate_floor_data(player, subfactory, floor)
    local floor_data = {
        id = floor.id,
        lines = {}
    }

    local mining_productivity = (subfactory.mining_productivity ~= nil) and
      (subfactory.mining_productivity / 100) or player.force.mining_drill_productivity_bonus

    for _, line in ipairs(Floor.get_in_order(floor, "Line")) do
        local line_data = { id = line.id }

        if line.subfloor ~= nil then  -- lines with subfloor need no further data than a reference to that subfloor
            line_data.recipe_proto = Floor.get(line.subfloor, "Line", 1).recipe.proto
            line_data.subfloor = generate_floor_data(player, subfactory, line.subfloor)

        else
            line_data.recipe_proto = line.recipe.proto  -- reference
            line_data.timescale = subfactory.timescale
            line_data.percentage = line.percentage
            line_data.production_type = line.recipe.production_type
            line_data.machine_limit = {limit=line.machine.limit, hard_limit=line.machine.hard_limit}
            line_data.beacon_consumption = 0
            line_data.priority_product_proto = line.priority_product_proto  -- reference
            line_data.machine_proto = line.machine.proto  -- reference

            -- Fuel prototype
            if line.machine.fuel ~= nil then line_data.fuel_proto = line.machine.fuel.proto end

            -- Total effects
            if line.machine.proto.mining then
                -- If there is mining prod, a copy of the table is required
                local effects = cutil.shallowcopy(line.total_effects)
                effects.productivity = effects.productivity + mining_productivity
                line_data.total_effects = effects
            else
                -- If there's no mining prod, a reference will suffice
                line_data.total_effects = line.total_effects
            end

            -- Beacon total (can be calculated here, which is faster and simpler)
            if line.beacon ~= nil and line.beacon.total_amount ~= nil then
                line_data.beacon_consumption = line.beacon.proto.energy_usage * line.beacon.total_amount * 60
            end
        end

        table.insert(floor_data.lines, line_data)
    end

    return floor_data
end

-- Replaces the items of the given object (of given class) using the given result
local function update_object_items(object, item_class, item_results)
    local object_class = _G[object.class]
    object_class.clear(object, item_class)

    for _, item_result in pairs(structures.class.to_array(item_results)) do
        local required_amount = (object.class == "Subfactory") and 0 or nil
        local item = Item.init_by_item(item_result, item_class, item_result.amount, required_amount)
        object_class.add(object, item)
    end
end

-- Goes through every line and setting their satisfied_amounts appropriately
local function update_ingredient_satisfaction(floor, product_class)
    product_class = product_class or structures.class.init()

    local function deteremine_satisfaction(ingredient)
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

    -- Iterate the lines from top to bottom, setting satisfaction amounts along the way
    for _, line in ipairs(Floor.get_in_order(floor, "Line", true)) do
        if line.subfloor ~= nil then
            local subfloor_product_class = structures.class.copy(product_class)
            update_ingredient_satisfaction(line.subfloor, subfloor_product_class)

        elseif line.machine.fuel then
            deteremine_satisfaction(line.machine.fuel)
        end

        for _, ingredient in pairs(Line.get_in_order(line, "Ingredient")) do
            if ingredient.proto.type ~= "entity" then
                deteremine_satisfaction(ingredient)
            end
        end

        -- Products and byproducts just get added to the list as being produced
        for _, class_name in pairs{"Product", "Byproduct"} do
            for _, product in pairs(Line.get_in_order(line, class_name)) do
                structures.class.add(product_class, product)
            end
        end
    end
end


-- ** TOP LEVEL **
-- Updates the whole subfactory calculations from top to bottom
function calculation.update(player, subfactory, refresh)
    if subfactory ~= nil and subfactory.valid then
        local player_table = data_util.get("table", player)
        -- Save the active subfactory in global so the model doesn't have to pass it around
        player_table.active_subfactory = subfactory

        local subfactory_data = calculation.interface.get_subfactory_data(player, subfactory)
        model.update_subfactory(subfactory_data)
        player_table.active_subfactory = nil
    end

    if refresh then main_dialog.refresh(player) end
end

-- Updates the given subfactory's ingredient satisfactions
function calculation.determine_ingredient_satisfaction(subfactory)
    update_ingredient_satisfaction(Subfactory.get(subfactory, "Floor", 1), nil)
end


-- ** INTERFACE **
-- Returns a table containing all the data needed to run the calculations for the given subfactory
function calculation.interface.get_subfactory_data(player, subfactory)
    local subfactory_data = {
        player_index = player.index,
        top_level_products = {},
        top_floor = nil
    }

    for _, product in ipairs(Subfactory.get_in_order(subfactory, "Product")) do
        local product_data = {
            proto = product.proto,  -- reference
            amount = Item.required_amount(product)
        }
        table.insert(subfactory_data.top_level_products, product_data)
    end

    local top_floor = Subfactory.get(subfactory, "Floor", 1)
    subfactory_data.top_floor = generate_floor_data(player, subfactory, top_floor)

    return subfactory_data
end

-- Updates the active subfactories top-level data with the given result
function calculation.interface.set_subfactory_result(result)
    local player_table = global.players[result.player_index]
    local subfactory = player_table.active_subfactory

    subfactory.energy_consumption = result.energy_consumption
    subfactory.pollution = result.pollution

    -- If products are not present in the result, it means they have been produced
    for _, product in pairs(Subfactory.get_in_order(subfactory, "Product")) do
        local product_result_amount = result.Product[product.proto.type][product.proto.name] or 0
        product.amount = Item.required_amount(product) - product_result_amount
    end

    update_object_items(subfactory, "Ingredient", result.Ingredient)
    update_object_items(subfactory, "Byproduct", result.Byproduct)

    -- Determine satisfaction-amounts for all line ingredients
    if player_table.preferences.ingredient_satisfaction then
        calculation.determine_ingredient_satisfaction(subfactory)
    end
end

-- Updates the given line of the given floor of the active subfactory
function calculation.interface.set_line_result(result)
    local subfactory = global.players[result.player_index].active_subfactory
    local floor = Subfactory.get(subfactory, "Floor", result.floor_id)
    local line = Floor.get(floor, "Line", result.line_id)

    if line.subfloor ~= nil then
        line.machine = {count = result.machine_count}
    else
        line.machine.count = result.machine_count
        if line.machine.fuel ~= nil then line.machine.fuel.amount = result.fuel_amount end

        line.production_ratio = result.production_ratio
        line.uncapped_production_ratio = result.uncapped_production_ratio

        -- Reset the priority_product if there's <2 products
        if structures.class.count(result.Product) < 2 then line.priority_product_proto = nil end
    end

    line.energy_consumption = result.energy_consumption
    line.pollution = result.pollution

    update_object_items(line, "Product", result.Product)
    update_object_items(line, "Byproduct", result.Byproduct)
    update_object_items(line, "Ingredient", result.Ingredient)
end


-- **** UTIL ****
-- Determines the number of crafts per tick for the given data
function calculation.util.determine_crafts_per_tick(machine_proto, recipe_proto, total_effects)
    local machine_speed = machine_proto.speed * (1 + math.max(total_effects.speed, -0.8))
    return machine_speed / recipe_proto.energy
end

-- Determine the amount of machines needed to produce the given recipe in the given context
function calculation.util.determine_machine_count(crafts_per_tick, production_ratio, timescale, is_rocket_silo)
    local launch_delay = 0
    if is_rocket_silo then  -- This calculation only works for unmodified rockets
        local launch_sequence_time = 41.25 / timescale  -- in seconds
        launch_delay = launch_sequence_time * production_ratio
    end

    return ((production_ratio / crafts_per_tick) / timescale) + launch_delay
end

-- Calculates the production ratio from a given machine limit
function calculation.util.determine_production_ratio(crafts_per_tick, machine_limit, timescale, is_rocket_silo)
    -- Formulae derived from 'determine_machine_count', it includes the launch_delay if necessary
    if is_rocket_silo then  -- Formula reduced by Wolfram Alpha
        return (4 * machine_limit * timescale * crafts_per_tick) / (165 * crafts_per_tick + 4)
    else
        return machine_limit * timescale * crafts_per_tick
    end
end

-- Calculates the product amount after applying productivity bonuses
function calculation.util.determine_prodded_amount(item, crafts_per_tick, total_effects)
    local productivity = math.max(total_effects.productivity, 0)
    if productivity == 0 then return item.amount end

    if crafts_per_tick > 60 then productivity = ((1/60) * productivity) * crafts_per_tick end

    -- Return formula is a simplification of the following formula:
    -- item.amount - item.proddable_amount + (item.proddable_amount * (productivity + 1))
    return item.amount + (item.proddable_amount * productivity)
end

-- Determines the amount of energy needed to satisfy the given recipe in the given context
function calculation.util.determine_energy_consumption(machine_proto, machine_count, total_effects)
    local consumption_multiplier = 1 + math.max(total_effects.consumption, -0.8)
    return machine_count * (machine_proto.energy_usage * 60) * consumption_multiplier
end

-- Determines the amount of pollution this recipe produces
function calculation.util.determine_pollution(machine_proto, recipe_proto, fuel_proto,
  total_effects, energy_consumption)
    local fuel_multiplier = (fuel_proto ~= nil) and fuel_proto.emissions_multiplier or 1
    local pollution_multiplier = 1 + math.max(total_effects.pollution, -0.8)
    return energy_consumption * (machine_proto.emissions * 60) * pollution_multiplier
      * fuel_multiplier * recipe_proto.emissions_multiplier
end

-- Determines the amount of fuel needed in the given context
function calculation.util.determine_fuel_amount(energy_consumption, burner, fuel_value, timescale)
    return ((energy_consumption / burner.effectivity) / fuel_value) * timescale
end