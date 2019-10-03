require("model")

calculation = {
    interface = {},
    util = {}
}

-- Updates the whole subfactory calculations from top to bottom
function calculation.update(player, subfactory)
    local main_dialog = player.gui.screen["fp_frame_main_dialog"]
    if main_dialog ~= nil and main_dialog.visible then
        if subfactory ~= nil and subfactory.valid then 
            local player_table = get_table(player)

            -- Save the active subfactory in global so the model doesn't have to move it around
            player_table.calculation_subfactory = subfactory
            
            local subfactory_data = calculation.interface.get_data(player, subfactory)
            model.update_subfactory(subfactory_data)

            -- Remove the active subfactory from global after the calculations
            player_table.calculation_subfactory = nil
        end
        refresh_main_dialog(player)
    end
end


-- Returns a table containing all the data needed to run the calculations for the given subfactory
function calculation.interface.get_data(player, subfactory)
    local subfactory_data = {
        player_index = player.index,
        timescale = subfactory.timescale,
        mining_productivity = subfactory.mining_productivity or 0,
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
                percentage = line.percentage,
                total_effects = util.table.deepcopy(line.total_effects),
                recipe_proto = line.recipe.proto,  -- reference
                machine_proto = line.machine.proto,  -- reference
                subfloor = generate_floor_data(line.subfloor)
            }

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
    local subfactory = global.players[result.player_index].calculation_subfactory

    subfactory.energy_consumption = result.energy_consumption

    -- For products, the existing top-level items just get updated individually
    for _, product in pairs(Subfactory.get_in_order(subfactory, "Product")) do
        local product_result_amount = result.Product[product.proto.type][product.proto.name]
        product.amount = (product_result_amount == nil) and 0 or product_result_amount
    end

    -- For ingredients and byproducts, the procedure is more complicated, because
    -- it has to retain the users ordering of those items
    local function update_top_level_items(class)
        local items = result[class]
        
        for _, item in pairs(Subfactory.get_in_order(subfactory, class)) do
            local item_result_amount = items[item.proto.type][item.proto.name]
            
            if item_result_amount == nil then
                Subfactory.remove(subfactory, item)
            else
                item.amount = item_result_amount
                -- This item_result_amount has been incorporated, so it can be removed
                items[item.proto.type][item.proto.name] = nil
            end
        end

        for _, item_result in pairs(calculation.util.items_to_array(items)) do
            local top_level_item = TopLevelItem.init_by_item(item_result, class, item_result.amount)
            Subfactory.add(subfactory, top_level_item)
        end
    end

    update_top_level_items("Ingredient")
    update_top_level_items("Byproduct")
end

-- Updates the given line of the given floor of the active subfactory
function calculation.interface.set_line_result(result)
    local subfactory = global.players[result.player_index].calculation_subfactory
    local floor = Subfactory.get(subfactory, "Floor", result.floor_id)
    local line = Floor.get(floor, "Line", result.line_id)

    line.energy_consumption = result.energy_consumption
    line.production_ratio = result.production_ratio

    -- This procedure is a bit more complicated to to retain the users ordering of items
    local function update_items(class)
        local items = result[class]

        for _, item in pairs(Line.get_in_order(line, class)) do
            local item_result_amount = items[item.proto.type][item.proto.name]
            
            if item_result_amount == nil then
                Line.remove(line, item)
            else
                item.amount = item_result_amount
                -- This item_result_amount has been incorporated, so it can be removed
                items[item.proto.type][item.proto.name] = nil
            end
        end

        for _, item_result in pairs(calculation.util.items_to_array(items)) do
            local item = Item.init_by_item(item_result, class, item_result.amount)
            Line.add(line, item)
        end
    end

    update_items("Product")
    update_items("Byproduct")
    update_items("Ingredient")
    update_items("Fuel")
end


-- Returns an array that contains every item in the given data structure
function calculation.util.items_to_array(items)
    local array = {}
    for type, items_of_type in pairs(items) do
        for name, amount in pairs(items_of_type) do
            local item = {
                name = name,
                type = type,
                amount = amount
            }
            table.insert(array, item)
        end
    end
    return array
end