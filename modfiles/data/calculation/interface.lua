require("model")
require("structures")

calculation = {
    interface = {},
    util = {}
}

-- Updates the whole subfactory calculations from top to bottom
function calculation.update(player, subfactory, refresh)
    local main_dialog = player.gui.screen["fp_frame_main_dialog"]
    if main_dialog ~= nil and main_dialog.visible then
        if subfactory ~= nil and subfactory.valid then
            local player_table = get_table(player)

            -- Save the active subfactory in global so the model doesn't have to pass it around
            player_table.active_subfactory = subfactory
            
            local subfactory_data = calculation.interface.get_subfactory_data(player, subfactory)
            --Profiler.Start()
            --local p = game.create_profiler()
            model.update_subfactory(subfactory_data)
            --p.stop()
            --log(p)
            --Profiler.Stop()
            player_table.active_subfactory = nil
        end
        if refresh then refresh_main_dialog(player) end
    end
end


-- Returns a table containing all the data needed to run the calculations for the given subfactory
function calculation.interface.get_subfactory_data(player, subfactory)
    local subfactory_data = {
        player_index = player.index,
        top_level_products = {},
        top_floor = {}
    }

    for _, product in ipairs(Subfactory.get_in_order(subfactory, "Product")) do
        local product_data = {
            proto = product.proto,  -- reference
            required_amount = product.required_amount
        }
        table.insert(subfactory_data.top_level_products, product_data)
    end

    local function generate_floor_data(floor)
        if floor == nil then return nil end

        local floor_data = {
            id = floor.id,
            lines = {}
        }

        for _, line in ipairs(Floor.get_in_order(floor, "Line")) do
            local line_data = {
                id = line.id,
                timescale = subfactory.timescale,
                percentage = line.percentage,
                machine_cap = line.machine.count_cap,
                total_effects = Line.get_total_effects(line, player),  -- copy
                priority_product_proto = line.priority_product_proto,  -- reference
                production_type = line.recipe.production_type,
                recipe_proto = line.recipe.proto,  -- reference
                machine_proto = line.machine.proto,  -- reference
                fuel_proto = nil,  -- will be a reference
                subfloor = generate_floor_data(line.subfloor)
            }

            if line_data.subfloor == nil then  -- the fuel_proto is only needed when there's no subfloor
                local fuels = Line.get_in_order(line, "Fuel")
                if table_size(fuels) == 1 then  -- use the already configured Fuel, if available
                    line_data.fuel_proto = fuels[1].proto
                else  -- otherwise, use the preferred fuel
                    line_data.fuel_proto = get_preferences(player).preferred_fuel
                end
            end

            table.insert(floor_data.lines, line_data)
        end

        return floor_data
    end

    local top_floor = Subfactory.get(subfactory, "Floor", 1)
    subfactory_data.top_floor = generate_floor_data(top_floor)

    return subfactory_data
end

-- Updates the active subfactories top-level data with the given result
function calculation.interface.set_subfactory_result(result)
    local subfactory = global.players[result.player_index].active_subfactory

    subfactory.energy_consumption = result.energy_consumption

    -- For products, the existing top-level items just get updated individually
    -- When the products are not present in the result, it means they have been produced
    for _, product in pairs(Subfactory.get_in_order(subfactory, "Product")) do
        local product_result_amount = result.Product[product.proto.type][product.proto.name] or 0
        product.amount = product.required_amount - product_result_amount
    end

    -- For ingredients and byproducts, the procedure is more complicated, because
    -- it has to retain the users ordering of those items
    local function update_top_level_items(class_name)
        local items = result[class_name]
        
        for _, item in pairs(Subfactory.get_in_order(subfactory, class_name)) do
            local item_result_amount = items[item.proto.type][item.proto.name]
            
            if item_result_amount == nil then
                Subfactory.remove(subfactory, item)
            else
                item.amount = item_result_amount
                -- This item_result_amount has been incorporated, so it can be removed
                items[item.proto.type][item.proto.name] = nil
            end
        end

        for _, item_result in pairs(structures.class.to_array(items)) do
            local top_level_item = TopLevelItem.init_by_item(item_result, class_name, item_result.amount)
            Subfactory.add(subfactory, top_level_item)
        end
    end

    update_top_level_items("Ingredient")
    update_top_level_items("Byproduct")


    local function determine_net_ingredients(floor, aggregate)
        -- First, determine the net ingredients of this floor
        for _, line in ipairs(Floor.get_in_order(floor, "Line")) do
            if line.subfloor ~= nil then 
                determine_net_ingredients(line.subfloor, aggregate)
            else
                for _, ingredient in ipairs(Line.get_in_order(line, "Ingredient")) do
                    local simple_ingredient = {type=ingredient.proto.type, name=ingredient.proto.name, amount=ingredient.amount}
                    structures.aggregate.add(aggregate, "Ingredient", simple_ingredient)
                end

                for _, product in ipairs(Line.get_in_order(line, "Product")) do
                    local simple_product = {type=product.proto.type, name=product.proto.name, amount=product.amount}
                    local ingredient_amount = aggregate.Ingredient[simple_product.type][simple_product.name] or 0
                    local used_ingredient_amount = math.min(ingredient_amount, simple_product.amount)
                    structures.aggregate.subtract(aggregate, "Ingredient", simple_product, used_ingredient_amount)
                end
            end
        end
    end

    local function update_ingredient_satisfaction(floor, aggregate)
        -- Then, go through all ingredients again, determining their satisfied_amounts
        for _, line in ipairs(Floor.get_in_order(floor, "Line", true)) do
            if line.subfloor ~= nil then 
                local aggregate_copy = data_util.deepcopy(aggregate)
                update_ingredient_satisfaction(line.subfloor, aggregate)

                for _, ingredient in ipairs(Line.get_in_order(line, "Ingredient")) do
                    local type, name = ingredient.proto.type, ingredient.proto.name
                    local removed_amount = (aggregate_copy.Ingredient[type][name] or 0) - (aggregate.Ingredient[type][name] or 0)
                    ingredient.satisfied_amount = ingredient.amount - removed_amount
                end

            else
                for _, ingredient in ipairs(Line.get_in_order(line, "Ingredient")) do
                    local aggregate_ingredient_amount = aggregate.Ingredient[ingredient.proto.type][ingredient.proto.name] or 0
                    local removed_amount = math.min(ingredient.amount, aggregate_ingredient_amount)

                    ingredient.satisfied_amount = ingredient.amount - removed_amount
                    structures.aggregate.subtract(aggregate, "Ingredient", {type=ingredient.proto.type, name=ingredient.proto.name}, removed_amount)
                end
            end
        end
    end

    -- Determine satisfaction-amounts for all line ingredients
    local top_floor = Subfactory.get(subfactory, "Floor", 1)
    local aggregate = structures.aggregate.init()  -- gets modified by the two functions
    determine_net_ingredients(top_floor, aggregate)
    update_ingredient_satisfaction(top_floor, aggregate)
end

-- Updates the given line of the given floor of the active subfactory
function calculation.interface.set_line_result(result)
    local subfactory = global.players[result.player_index].active_subfactory
    local floor = Subfactory.get(subfactory, "Floor", result.floor_id)
    local line = Floor.get(floor, "Line", result.line_id)

    line.machine.count = result.machine_count
    line.energy_consumption = result.energy_consumption
    line.production_ratio = result.production_ratio
    line.uncapped_production_ratio = result.uncapped_production_ratio

    -- Reset the priority_product if there aren't more than one product
    if table_size(structures.class.to_array(result.Product)) < 2 then
        Line.set_priority_product(line, nil)
    end

    -- This procedure is a bit more complicated to to retain the users ordering of items
    local function update_items(class_name)
        local items = result[class_name]

        for _, item in pairs(Line.get_in_order(line, class_name)) do
            local item_result_amount = items[item.proto.type][item.proto.name]
            
            if item_result_amount == nil then
                Line.remove(line, item)
            else
                item.amount = item_result_amount
                -- This item_result_amount has been incorporated, so it can be removed
                items[item.proto.type][item.proto.name] = nil
            end
        end

        for _, item_result in pairs(structures.class.to_array(items)) do
            local item = (class_name == "Fuel") and Fuel.init_by_item(item_result, item_result.amount)
              or Item.init_by_item(item_result, class_name, item_result.amount)
            Line.add(line, item)
        end
    end

    update_items("Product")
    update_items("Byproduct")
    update_items("Ingredient")
    update_items("Fuel")
end


-- Determine the amount of machines needed to produce the given recipe in the given context
function calculation.util.determine_machine_count(machine_proto, recipe_proto, total_effects, production_ratio, timescale)
    local machine_prod_ratio = production_ratio / (1 + math.max(total_effects.productivity, 0))
    local machine_speed = machine_proto.speed * (1 + math.max(total_effects.speed, -0.8))

    local launch_delay = 0
    if recipe_proto.name == "rocket-part" then
        local rockets_produced = production_ratio / 100
        local launch_sequence_time = 41.25 / timescale  -- in seconds
        -- Not sure why this forumla works, but it seemingly does
        launch_delay = launch_sequence_time * rockets_produced
    end

    return ((machine_prod_ratio / (machine_speed / recipe_proto.energy)) / timescale) + launch_delay
end

-- Calculates the production ratio from a given machine cap
-- (Conversion of the machine_count formula, not sure how to work in the launch_delay correctly)
function calculation.util.determine_production_ratio(machine_proto, recipe_proto, total_effects, machine_cap, timescale)
    local machine_speed = machine_proto.speed * (1 + math.max(total_effects.speed, -0.8))
    return ((machine_cap --[[ - launch_delay ]]) * timescale * (machine_speed / recipe_proto.energy) * (1 + math.max(total_effects.productivity, 0)))
end

-- Determines the amount of energy needed to satisfy the given recipe in the given context
function calculation.util.determine_energy_consumption(machine_proto, machine_count, total_effects)
    local energy_consumption = machine_count * (machine_proto.energy_usage * 60)
    return energy_consumption + (energy_consumption * math.max(total_effects.consumption, -0.8))
end

-- Determines the amount of fuel needed in the given context
function calculation.util.determine_fuel_amount(energy_consumption, burner, fuel_value, timescale)
    return ((energy_consumption / burner.effectivity) / fuel_value) * timescale
end