require("model")
require("structures")
require("matrix_solver")
require("ui.dialogs.modal_dialog")

calculation = {
    interface = {},
    util = {}
}

-- Updates the whole subfactory calculations from top to bottom
function calculation.update(player, subfactory, refresh)
    local player_table = get_table(player)
    local use_matrix_solver = player_table.preferences.use_matrix_solver
    if use_matrix_solver then
        calculation.start_matrix_solver(player, subfactory, refresh, false)
    else
        calculation.start_line_by_line_solver(player, subfactory, refresh)
    end
end

function calculation.start_line_by_line_solver(player, subfactory, refresh)
    if subfactory ~= nil and subfactory.valid then
        local player_table = get_table(player)
        -- Save the active subfactory in global so the model doesn't have to pass it around
        player_table.active_subfactory = subfactory
        
        local subfactory_data = calculation.interface.get_subfactory_data(player, subfactory)
        model.update_subfactory(subfactory_data)
        player_table.active_subfactory = nil
    end
    if refresh then refresh_main_dialog(player) end
end

function calculation.start_matrix_solver(player, subfactory, refresh, show_dialog)
    local modal_data= calculation.get_matrix_solver_modal_data(player, subfactory)
    modal_data["refresh"] = refresh
    local dialog_settings = {
        type = "matrix_solver",
        submit = true,
        modal_data = modal_data
    }
    local num_rows = #modal_data.ingredients + #modal_data.products + #modal_data.byproducts + #modal_data.eliminated_items + #modal_data.free_items
    local num_cols = #modal_data.recipes + #modal_data.ingredients + #modal_data.byproducts + #modal_data.free_items
    if num_rows~=num_cols then show_dialog = true end
    
    if show_dialog then
        if refresh then refresh_main_dialog(player) end
        enter_modal_dialog(player, dialog_settings)
    else
        local variables = {
            free=modal_data.free_items,
            eliminated=modal_data.eliminated_items
        }
        calculation.run_matrix_solver(player, subfactory, variables, refresh)
    end
end

function calculation.get_matrix_solver_modal_data(player, subfactory)
    local eliminated_items = {}
    local free_items = {}
    local subfactory_data = calculation.interface.get_subfactory_data(player, subfactory)
    local subfactory_metadata = matrix_solver.get_subfactory_metadata(subfactory_data)
    local all_items = subfactory_metadata.all_items
    local raw_inputs = subfactory_metadata.raw_inputs
    local byproducts = subfactory_metadata.byproducts
    local unproduced_outputs = subfactory_metadata.unproduced_outputs
    local produced_outputs = matrix_solver.set_diff(subfactory_metadata.desired_outputs, unproduced_outputs)
    local free_variables = matrix_solver.union_sets(raw_inputs, byproducts, unproduced_outputs)
    local intermediate_items = matrix_solver.set_diff(all_items, free_variables)
    if subfactory.matrix_solver_variables == nil then
        eliminated_items = intermediate_items
    else
        -- by default when a subfactory is updated, add any new variables to eliminated and let the user select free.
        local free_items_list = subfactory.matrix_solver_variables.free
        for _, free_item in ipairs(free_items_list) do
            free_items[free_item] = true
        end
        -- make sure that any items that no longer exist are removed
        free_items = matrix_solver.intersect_sets(free_items, all_items)
        eliminated_items = matrix_solver.set_diff(intermediate_items, free_items)
    end
    -- technically the produced outputs are eliminated variables but we don't want to double-count it in the UI
    eliminated_items = matrix_solver.set_diff(eliminated_items, produced_outputs)
    local result = {
        recipes = matrix_solver.set_to_ordered_list(subfactory_metadata.recipes),
        ingredients = matrix_solver.set_to_ordered_list(subfactory_metadata.raw_inputs),
        products = matrix_solver.set_to_ordered_list(produced_outputs),
        byproducts = matrix_solver.set_to_ordered_list(subfactory_metadata.byproducts),
        eliminated_items = matrix_solver.set_to_ordered_list(eliminated_items),
        free_items = matrix_solver.set_to_ordered_list(free_items)
    }
    return result

end

function calculation.check_linear_dependence(player, subfactory, variables)
    local subfactory_data = calculation.interface.get_subfactory_data(player, subfactory)
    return matrix_solver.run_matrix_solver(player, subfactory_data, variables, true)
end

function calculation.run_matrix_solver(player, subfactory, variables, refresh)
    if subfactory ~= nil and subfactory.valid then
        local player_table = get_table(player)
        player_table.active_subfactory = subfactory
        local subfactory_data = calculation.interface.get_subfactory_data(player, subfactory)
        matrix_solver.run_matrix_solver(player, subfactory_data, variables)
        player_table.active_subfactory = nil
    end
    if refresh then refresh_main_dialog(player) end
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

    local top_floor = Subfactory.get(subfactory, "Floor", 1)
    subfactory_data.top_floor = calculation.util.generate_floor_data(player, subfactory, top_floor)

    -- TODO for claude: set this mode correctly
    local mode = "MATRIX_SOLVER"
    if mode == "MATRIX_SOLVER" then
        subfactory_data.matrix_solver_variables = subfactory.matrix_solver_variables
    end

    return subfactory_data
end

-- Updates the active subfactories top-level data with the given result
function calculation.interface.set_subfactory_result(result)
    local player_table = global.players[result.player_index]
    local subfactory = player_table.active_subfactory

    if result.variables ~= nil then
        subfactory.matrix_solver_variables = result.variables
    end
    
    subfactory.energy_consumption = result.energy_consumption
    subfactory.pollution = result.pollution

    -- For products, the existing top-level items just get updated individually
    -- When the products are not present in the result, it means they have been produced
    for _, product in pairs(Subfactory.get_in_order(subfactory, "Product")) do
        local product_result_amount = result.Product[product.proto.type][product.proto.name] or 0
        product.amount = product.required_amount - product_result_amount
    end
    
    calculation.util.update_items(subfactory, result, "Byproduct")
    calculation.util.update_items(subfactory, result, "Ingredient")

    -- Determine satisfaction-amounts for all line ingredients
    if player_table.preferences.ingredient_satisfaction then
        local top_floor = Subfactory.get(subfactory, "Floor", 1)
        local aggregate = structures.aggregate.init()  -- gets modified by the two functions
        calculation.util.determine_net_ingredients(top_floor, aggregate)
        calculation.util.update_ingredient_satisfaction(top_floor, aggregate)
    end
end

-- Updates the given line of the given floor of the active subfactory
function calculation.interface.set_line_result(result)
    local subfactory = global.players[result.player_index].active_subfactory
    local floor = Subfactory.get(subfactory, "Floor", result.floor_id)
    local line = Floor.get(floor, "Line", result.line_id)
    
    line.machine.count = result.machine_count
    line.energy_consumption = result.energy_consumption
    line.pollution = result.pollution
    line.production_ratio = result.production_ratio
    line.uncapped_production_ratio = result.uncapped_production_ratio

    -- Reset the priority_product if there's <2 products
    if structures.class.count(result.Product) < 2 then
        Line.set_priority_product(line, nil)
    end

    calculation.util.update_items(line, result, "Product")
    calculation.util.update_items(line, result, "Byproduct")
    calculation.util.update_items(line, result, "Ingredient")
    calculation.util.update_items(line, result, "Fuel")
end


-- **** LOCAL UTIL ****
-- Generates structured data of the given floor for calculation
function calculation.util.generate_floor_data(player, subfactory, floor)
    local floor_data = {
        id = floor.id,
        lines = {}
    }

    local preferred_fuel = get_preferences(player).preferred_fuel
    local mining_productivity = (subfactory.mining_productivity ~= nil) and
      (subfactory.mining_productivity / 100) or player.force.mining_drill_productivity_bonus

    for _, line in ipairs(Floor.get_in_order(floor, "Line")) do
        local line_data = {
            id = line.id,
            timescale = subfactory.timescale,
            percentage = line.percentage,
            production_type = line.recipe.production_type,
            machine_limit = {limit=line.machine.limit, hard_limit=line.machine.hard_limit},
            total_effects = nil,  -- reference or copy, depending on case
            beacon_consumption = 0,
            priority_product_proto = line.priority_product_proto,  -- reference
            recipe_proto = line.recipe.proto,  -- reference
            machine_proto = line.machine.proto,  -- reference
            fuel_proto = nil,  -- will be a reference
            subfloor = nil  -- will be a floor_data object
        }

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

        -- Fuel proto
        if line_data.subfloor == nil then  -- the fuel_proto is only needed when there's no subfloor
            if line.Fuel.count == 1 then  -- use the already configured Fuel, if available
                line_data.fuel_proto = Line.get_by_gui_position(line, "Fuel", 1).proto
            else  -- otherwise, use the preferred fuel
                line_data.fuel_proto = preferred_fuel
            end
        end

        -- Subfloor
        if line.subfloor ~= nil then line_data.subfloor = 
          calculation.util.generate_floor_data(player, subfactory, line.subfloor) end

        table.insert(floor_data.lines, line_data)
    end

    return floor_data
end

-- Updates the items of the given object (of given class) using the given result
-- This procedure is a bit more complicated to to retain the users ordering of items
function calculation.util.update_items(object, result, class_name)
    local items = result[class_name]

    for _, item in pairs(_G[object.class].get_in_order(object, class_name)) do
        local item_result_amount = items[item.proto.type][item.proto.name]
        
        if item_result_amount == nil then
            _G[object.class].remove(object, item)
        else
            item.amount = item_result_amount
            -- This item_result_amount has been incorporated, so it can be removed
            items[item.proto.type][item.proto.name] = nil
        end
    end

    for _, item_result in pairs(structures.class.to_array(items)) do
        if object.class == "Subfactory" then
            top_level_item = Item.init_by_item(item_result, class_name, item_result.amount, 0)
            _G[object.class].add(object, top_level_item)

        else  -- object.class == "Line"
            item = (class_name == "Fuel") and Fuel.init_by_item(item_result, item_result.amount)
              or Item.init_by_item(item_result, class_name, item_result.amount)
            _G[object.class].add(object, item)
        end
    end
end

-- Determines the net ingredients of this floor
function calculation.util.determine_net_ingredients(floor, aggregate)
    for _, line in ipairs(Floor.get_in_order(floor, "Line")) do
        if line.subfloor ~= nil then 
            calculation.util.determine_net_ingredients(line.subfloor, aggregate)
        else
            for _, ingredient in ipairs(Line.get_in_order(line, "Ingredient")) do
                local simple_ingredient = {type=ingredient.proto.type, name=ingredient.proto.name, amount=ingredient.amount}
                structures.aggregate.add(aggregate, "Ingredient", simple_ingredient)
            end

            local function subtract_product(product_type, limiter)
                for _, product in ipairs(Line.get_in_order(line, product_type)) do
                    local simple_product = {type=product.proto.type, name=product.proto.name, amount=product.amount}
                    local ingredient_amount = aggregate.Ingredient[simple_product.type][simple_product.name] or 0
                    local used_ingredient_amount = limiter(ingredient_amount, simple_product.amount)
                    structures.aggregate.subtract(aggregate, "Ingredient", simple_product, used_ingredient_amount)
                end
            end

            subtract_product("Product", math.min)
            subtract_product("Byproduct", math.max)
        end
    end
end

-- Goes through all ingredients (again), determining their satisfied_amounts
function calculation.util.update_ingredient_satisfaction(floor, aggregate)
    for _, line in ipairs(Floor.get_in_order(floor, "Line", true)) do
        if line.subfloor ~= nil then 
            local aggregate_ingredient_copy = util.table.deepcopy(aggregate.Ingredient)
            calculation.util.update_ingredient_satisfaction(line.subfloor, aggregate)

            for _, ingredient in ipairs(Line.get_in_order(line, "Ingredient")) do
                local type, name = ingredient.proto.type, ingredient.proto.name
                local removed_amount = (aggregate_ingredient_copy[type][name] or 0) - (aggregate.Ingredient[type][name] or 0)
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

-- Goes through all subfactories to update their ingredient satisfaction numbers
function calculation.util.update_all_ingredient_satisfactions(player)
    local factories = {"factory", "archive"}
    for _, player_table in pairs(global.players) do
        for _, factory_name in pairs(factories) do
            for _, subfactory in ipairs(Factory.get_in_order(player_table[factory_name], "Subfactory")) do
                local top_floor = Subfactory.get(subfactory, "Floor", 1)
                local aggregate = structures.aggregate.init()  -- gets modified by the two functions
                calculation.util.determine_net_ingredients(top_floor, aggregate)
                calculation.util.update_ingredient_satisfaction(top_floor, aggregate)
            end
        end
    end
end


-- **** FORMULAE ****
-- Determine the amount of machines needed to produce the given recipe in the given context
function calculation.util.determine_machine_count(machine_proto, recipe_proto, total_effects, production_ratio, timescale)
    local launch_delay = 0
    if recipe_proto.name == "rocket-part" then
        local rockets_produced = production_ratio / 100
        local launch_sequence_time = 41.25 / timescale  -- in seconds
        -- Not sure why this forumla works, but it seemingly does
        launch_delay = launch_sequence_time * rockets_produced
    end
    
    local machine_prod_ratio = production_ratio / (1 + math.max(total_effects.productivity, 0))
    local machine_speed = machine_proto.speed * (1 + math.max(total_effects.speed, -0.8))
    return ((machine_prod_ratio / (machine_speed / recipe_proto.energy)) / timescale) + launch_delay
end

-- Calculates the production ratio from a given machine limit
-- (Forumla derived from determine_machine_count, not sure how to work in the launch_delay correctly)
function calculation.util.determine_production_ratio(machine_proto, recipe_proto, total_effects, machine_limit, timescale)
    local machine_speed = machine_proto.speed * (1 + math.max(total_effects.speed, -0.8))
    local productivity_multiplier = (1 + math.max(total_effects.productivity, 0))
    return (machine_limit --[[ -launch_delay ]]) * timescale * (machine_speed / recipe_proto.energy) * productivity_multiplier
end

-- Calculates the ingredient/product amount after applying productivity bonuses
-- [Formula derived from: amount - proddable_amount + (proddable_amount / productivity)]
function calculation.util.determine_prodded_amount(item, total_effects)
    local productivity = (1 + math.max(total_effects.productivity, 0))
    return item.amount + item.proddable_amount * ((1 / productivity) - 1)
end

-- Determines the amount of energy needed to satisfy the given recipe in the given context
function calculation.util.determine_energy_consumption(machine_proto, machine_count, total_effects)
    return machine_count * (machine_proto.energy_usage * 60) * (1 + math.max(total_effects.consumption, -0.8))
end

-- Determines the amount of pollution this recipe produces
function calculation.util.determine_pollution(machine_proto, recipe_proto, fuel_proto, total_effects, energy_consumption)
    local fuel_multiplier = (fuel_proto ~= nil) and fuel_proto.emissions_multiplier or 1
    local pollution_multiplier = 1 + math.max(total_effects.pollution, -0.8)
    return energy_consumption * (machine_proto.emissions * 60) * pollution_multiplier * fuel_multiplier * recipe_proto.emissions_multiplier
end

-- Determines the amount of fuel needed in the given context
function calculation.util.determine_fuel_amount(energy_consumption, burner, fuel_value, timescale)
    return ((energy_consumption / burner.effectivity) / fuel_value) * timescale
end