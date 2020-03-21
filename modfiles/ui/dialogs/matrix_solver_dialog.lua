function open_matrix_solver_dialog(flow_modal_dialog, modal_data)
    local flow = flow_modal_dialog["flow_matrix_solver_items"]
    if flow == nil then
        flow = flow_modal_dialog.add{type="flow", name="flow_matrix_solver_items", direction="vertical"}
        flow.style.bottom_margin=12
    end
    flow.add{type="label", name="label_recipes", caption={"fp.matrix_solver_recipes"}}
    flow.add{type="flow", name="flow_matrix_solver_recipes", direction="horizontal"}
    flow.add{type="label", name="label_ingredients", caption={"fp.matrix_solver_ingredients"}}
    flow.add{type="flow", name="flow_matrix_solver_ingredients", direction="horizontal"}
    flow.add{type="label", name="label_products", caption={"fp.matrix_solver_products"}}
    flow.add{type="flow", name="flow_matrix_solver_products", direction="horizontal"}
    flow.add{type="label", name="label_by_products", caption={"fp.matrix_solver_by_products"}}
    flow.add{type="flow", name="flow_matrix_solver_by_products", direction="horizontal"}
    flow.add{type="label", name="label_free_items", caption={"fp.matrix_solver_free"}}
    flow.add{type="flow", name="flow_matrix_solver_free_items", direction="horizontal"}
    flow.add{type="label", name="label_constrained_items", caption={"fp.matrix_solver_constrained"}}
    flow.add{type="flow", name="flow_matrix_solver_constrained_items", direction="horizontal"}
    refresh_matrix_solver_items(flow_modal_dialog, modal_data)
end

function close_matrix_solver_dialog(flow_modal_dialog, action, data)
    -- all I care about is the modal_data, the data parameter was empty even when I tried defining get_matrix_solver_condition_instructions
    local player = game.players[flow_modal_dialog.player_index]
    local ui_state = get_ui_state(player)
    local modal_data = ui_state.modal_data
    local subfactory = ui_state.context.subfactory

    -- what gets passed in here?
    local variables = {
        free = modal_data.free_items,
        constrained = modal_data.constrained_items
    }
    calculation.run_matrix_solver(player, subfactory, variables)
end

-- item_variable_type is either "constrained" or "free"
function get_item_button(item_id, item_variable_type, style)
    return {
        type="sprite-button",
        name="fp_sprite-button_matrix_solver_item_"..item_variable_type.."_"..item_id,
        sprite=get_sprite(item_id),
        style=style
    }
end

function get_sprite(item_id)
    local split_string = cutil.split(item_id, "_")
    local item_type_id = split_string[1]
    local item_id = split_string[2]
    return global.all_items.types[item_type_id].items[item_id].sprite
end

function handle_matrix_solver_item_press(player, item_variable_type, item_id)
    local ui_state = get_ui_state(player)
    local modal_data = ui_state.modal_data
    local flow_modal_dialog = player.gui.screen["fp_frame_modal_dialog"]["flow_modal_dialog"]
    local old_variable_table
    local new_variable_table
    if item_variable_type == "free" then
        old_variable_table = modal_data.free_items
        new_variable_table = modal_data.constrained_items
    else
        old_variable_table = modal_data.constrained_items
        new_variable_table = modal_data.free_items
    end
    remove(old_variable_table, item_id)
    insert(new_variable_table, item_id)
    refresh_matrix_solver_items(flow_modal_dialog, modal_data)
end

function refresh_matrix_solver_items(flow_modal_dialog, modal_data)
    local recipe_buttons = flow_modal_dialog["flow_matrix_solver_items"]["flow_matrix_solver_recipes"]
    local recipes = modal_data.recipes
    recipe_buttons.clear()
    for _, recipe_id in ipairs(recipes) do
        local sprite = global.all_recipes.recipes[recipe_id].sprite
        recipe_buttons.add{type="sprite-button", name="fp_sprite-button_matrix_solver_recipe_"..recipe_id, sprite=sprite,
            style="fp_button_icon_large_blank", enabled=false}
    end

    local ingredient_buttons = flow_modal_dialog["flow_matrix_solver_items"]["flow_matrix_solver_ingredients"]
    local ingredients = modal_data.ingredients
    ingredient_buttons.clear()
    for _, item_id in ipairs(ingredients) do
        ingredient_buttons.add(get_item_button(item_id, "ingredient", "fp_button_icon_large_blank"))
    end

    local product_buttons = flow_modal_dialog["flow_matrix_solver_items"]["flow_matrix_solver_products"]
    local products = modal_data.products
    product_buttons.clear()
    for _, item_id in ipairs(products) do
        product_buttons.add(get_item_button(item_id, "product", "fp_button_icon_large_blank"))
    end

    local by_product_buttons = flow_modal_dialog["flow_matrix_solver_items"]["flow_matrix_solver_by_products"]
    local by_products = modal_data.by_products
    by_product_buttons.clear()
    for _, item_id in ipairs(by_products) do
        by_product_buttons.add(get_item_button(item_id, "by_product", "fp_button_icon_large_blank"))
    end

    local free_buttons = flow_modal_dialog["flow_matrix_solver_items"]["flow_matrix_solver_free_items"]
    local free_items = modal_data.free_items
    free_buttons.clear()
    for _, item_id in ipairs(free_items) do
        free_buttons.add(get_item_button(item_id, "free", nil))
    end

    local constrained_buttons = flow_modal_dialog["flow_matrix_solver_items"]["flow_matrix_solver_constrained_items"]
    local constrained_items = modal_data.constrained_items
    constrained_buttons.clear()
    for _, item_id in ipairs(constrained_items) do
        constrained_buttons.add(get_item_button(item_id, "constrained", nil))
    end
end

-- utility function that removes from a sorted array in place
function remove(orig_table, value)
    local i = 1
    local found = false
    while i<=#orig_table and (not found) do
        local curr = orig_table[i]
        if curr >= value then
            found = true
        end
        if curr == value then
            table.remove(orig_table, i)
        end
        i = i+1
    end
end

-- utility function that inserts into a sorted array in place
function insert(orig_table, value)
    local i = 1
    local found = false
    while i<=#orig_table and (not found) do
        local curr = orig_table[i]
        if curr >= value then
            found=true
        end
        if curr > value then
            table.insert(orig_table, i, value)
        end
        i = i+1
    end
    if not found then
        table.insert(orig_table, value)
    end
end
