require("model")
require("structures")

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

            -- Save the active subfactory in global so the model doesn't have to pass it around
            player_table.active_subfactory = subfactory
            
            local subfactory_data = calculation.interface.get_data(player, subfactory)
            model.update_subfactory(subfactory_data)

            player_table.active_subfactory = nil
        end
        refresh_main_dialog(player)
    end
end


-- Returns a table containing all the data needed to run the calculations for the given subfactory
function calculation.interface.get_data(player, subfactory)
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
                total_effects = util.table.deepcopy(line.total_effects),
                recipe_proto = line.recipe.proto,  -- reference
                machine_proto = line.machine.proto,  -- reference
                subfloor = generate_floor_data(line.subfloor)
            }

            -- Include mining prod right here, if applicable
            local mining_prod = data_util.determine_mining_productivity(player, subfactory, line.machine.proto)
            line_data.total_effects.productivity = math.max(line_data.total_effects.productivity + mining_prod, 0)

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
end

-- Updates the given line of the given floor of the active subfactory
function calculation.interface.set_line_result(result)
    local subfactory = global.players[result.player_index].active_subfactory
    local floor = Subfactory.get(subfactory, "Floor", result.floor_id)
    local line = Floor.get(floor, "Line", result.line_id)

    line.machine.count = result.machine_count
    line.energy_consumption = result.energy_consumption
    line.production_ratio = result.production_ratio

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
            local item = Item.init_by_item(item_result, class_name, item_result.amount)
            Line.add(line, item)
        end
    end

    update_items("Product")
    update_items("Byproduct")
    update_items("Ingredient")
    update_items("Fuel")
end