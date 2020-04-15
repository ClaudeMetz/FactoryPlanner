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

    flow.add{type="label", name="label_byproducts", caption={"fp.matrix_solver_byproducts"}}
    flow.add{type="flow", name="flow_matrix_solver_byproducts", direction="horizontal"}

    flow.add{type="label", name="label_eliminated_items", caption={"fp.matrix_solver_eliminated"}}
    flow.add{type="flow", name="flow_matrix_solver_eliminated_items", direction="horizontal"}

    flow.add{type="label", name="label_free_items", caption={"fp.matrix_solver_free"}}
    flow.add{type="flow", name="flow_matrix_solver_free_items", direction="horizontal"}

    flow.add{type="label", name="label_num_rows"}
    flow.add{type="label", name="label_num_cols"}

    refresh_matrix_solver_items(flow_modal_dialog, modal_data, {})
end

function close_matrix_solver_dialog(flow_modal_dialog, action, data)
    -- all I care about is the modal_data, the data parameter was empty even when I tried defining get_matrix_solver_condition_instructions
    local player = game.players[flow_modal_dialog.player_index]
    local ui_state = get_ui_state(player)
    local modal_data = ui_state.modal_data
    local subfactory = ui_state.context.subfactory
    local refresh = modal_data["refresh"]

    calculation.run_matrix_solver(player, subfactory, modal_data.free_items, refresh)
end

function get_matrix_solver_condition_instructions(modal_data)
    return {
        data = {
            num_rows = (function(flow_modal_dialog)
                -- can't use the parent function's modal_data since it doesn't get updated from clicking on free/eliminated
                local player = game.players[flow_modal_dialog.player_index]
                local ui_state = get_ui_state(player)
                local modal_data = ui_state.modal_data
                return #modal_data.ingredients + #modal_data.products + #modal_data.byproducts + #modal_data.eliminated_items + #modal_data.free_items
            end),
            num_cols = (function(flow_modal_dialog)
                local player = game.players[flow_modal_dialog.player_index]
                local ui_state = get_ui_state(player)
                local modal_data = ui_state.modal_data
                return #modal_data.recipes + #modal_data.ingredients + #modal_data.byproducts + #modal_data.free_items
            end),
            linearly_dependent_cols = (function(flow_modal_dialog)
                local player = game.players[flow_modal_dialog.player_index]
                local ui_state = get_ui_state(player)
                local modal_data = ui_state.modal_data
                local num_rows = #modal_data.ingredients + #modal_data.products + #modal_data.byproducts + #modal_data.eliminated_items + #modal_data.free_items
                local num_cols = #modal_data.recipes + #modal_data.ingredients + #modal_data.byproducts + #modal_data.free_items
                -- return early if these don't match since the matrix solver can crash when these are different
                if num_rows ~= num_cols then
                    return {}
                end
                local subfactory = ui_state.context.subfactory
                return calculation.check_linear_dependence(player, subfactory, modal_data.free_items)
            end),
            flow_modal_dialog = (function(flow_modal_dialog) return flow_modal_dialog end)
        },
        conditions = {
            [1] = {
                label = "Number of rows must match number of columns",
                check = (function(data)
                    return (data.num_rows ~= data.num_cols)
                end),
                show_on_edit=true -- not sure what this does
            },
            [2] = {
                label = "Columns must be linearly independent",
                check = (function(data)
                    -- highlight the linearly dependent cols in this step
                    local player = game.players[data.flow_modal_dialog.player_index]
                    local ui_state = get_ui_state(player)
                    local modal_data = ui_state.modal_data
                    refresh_matrix_solver_items(data.flow_modal_dialog, modal_data, data.linearly_dependent_cols)
                    return (next(data.linearly_dependent_cols) ~= nil) -- check if empty
                end),
                show_on_edit=true
            }
        }
    }
end

-- item_variable_type is either "eliminated" or "free"
function get_item_button(item_id, item_variable_type, linearly_dependent_cols)
    local style=nil
    if linearly_dependent_cols['item_'..item_id] then
        style = "fp_button_icon_large_red"
    elseif item_variable_type=="free" or item_variable_type=="eliminated" then
        style = "fp_button_icon_large_recipe" -- recipe just makes it look like a button
    else
        style = "fp_button_icon_large_blank"
    end
    local item = get_item(item_id)
    return {
        type="sprite-button",
        name="fp_sprite-button_matrix_solver_item_"..item_variable_type.."_"..item_id,
        sprite=item.sprite,
        tooltip=item.localised_name,
        style=style
    }
end

function get_item(item_id)
    local split_string = cutil.split(item_id, "_")
    local item_type_id = split_string[1]
    local item_id = split_string[2]
    return global.all_items.types[item_type_id].items[item_id]
end

function handle_matrix_solver_free_item_press(player, item_id)
    local ui_state = get_ui_state(player)
    local modal_data = ui_state.modal_data
    cutil.array.remove(modal_data.free_items, item_id)
    cutil.array.insert(modal_data.eliminated_items, item_id)
    local flow_modal_dialog = player.gui.screen["fp_frame_modal_dialog"]["flow_modal_dialog"]
    refresh_matrix_solver_items(flow_modal_dialog, modal_data, {})
end

function handle_matrix_solver_eliminated_item_press(player, item_id)
    local ui_state = get_ui_state(player)
    local modal_data = ui_state.modal_data
    cutil.array.remove(modal_data.eliminated_items, item_id)
    cutil.array.insert(modal_data.free_items, item_id)
    local flow_modal_dialog = player.gui.screen["fp_frame_modal_dialog"]["flow_modal_dialog"]
    refresh_matrix_solver_items(flow_modal_dialog, modal_data, {})
end

function refresh_matrix_solver_items(flow_modal_dialog, modal_data, linearly_dependent_cols)
    local recipe_buttons = flow_modal_dialog["flow_matrix_solver_items"]["flow_matrix_solver_recipes"]
    local recipes = modal_data.recipes
    recipe_buttons.clear()
    for i, recipe_id in ipairs(recipes) do
        local recipe = global.all_recipes.recipes[recipe_id]
        local sprite = recipe.sprite
        local tooltip = recipe.localised_name
        local button_style
        if linearly_dependent_cols["recipe_"..recipe_id] then button_style="fp_button_icon_large_red" else button_style="fp_button_icon_large_blank" end
        recipe_buttons.add{type="sprite-button", name="fp_sprite-button_matrix_solver_recipe_"..recipe_id.."_"..i,
            sprite=sprite, tooltip=tooltip, style=button_style, enabled=false}
    end

    local ingredient_buttons = flow_modal_dialog["flow_matrix_solver_items"]["flow_matrix_solver_ingredients"]
    local ingredients = modal_data.ingredients
    ingredient_buttons.clear()
    for _, item_id in ipairs(ingredients) do
        ingredient_buttons.add(get_item_button(item_id, "ingredient", linearly_dependent_cols))
    end

    local product_buttons = flow_modal_dialog["flow_matrix_solver_items"]["flow_matrix_solver_products"]
    local products = modal_data.products
    product_buttons.clear()
    for _, item_id in ipairs(products) do
        product_buttons.add(get_item_button(item_id, "product", linearly_dependent_cols))
    end

    local byproduct_buttons = flow_modal_dialog["flow_matrix_solver_items"]["flow_matrix_solver_byproducts"]
    local byproducts = modal_data.byproducts
    byproduct_buttons.clear()
    for _, item_id in ipairs(byproducts) do
        byproduct_buttons.add(get_item_button(item_id, "byproduct", linearly_dependent_cols))
    end

    local free_buttons = flow_modal_dialog["flow_matrix_solver_items"]["flow_matrix_solver_free_items"]
    local free_items = modal_data.free_items
    free_buttons.clear()
    for _, item_id in ipairs(free_items) do
        free_buttons.add(get_item_button(item_id, "free", linearly_dependent_cols))
    end

    local eliminated_buttons = flow_modal_dialog["flow_matrix_solver_items"]["flow_matrix_solver_eliminated_items"]
    local eliminated_items = modal_data.eliminated_items
    eliminated_buttons.clear()
    for _, item_id in ipairs(eliminated_items) do
        eliminated_buttons.add(get_item_button(item_id, "eliminated", linearly_dependent_cols))
    end

    local num_rows = #ingredients + #products + #byproducts + #eliminated_items + #free_items
    flow_modal_dialog["flow_matrix_solver_items"]["label_num_rows"].caption = {"", {"fp.matrix_solver_total_rows"}, ": ", num_rows}
    local num_cols = #recipes + #ingredients + #byproducts + #free_items
    flow_modal_dialog["flow_matrix_solver_items"]["label_num_cols"].caption = {"", {"fp.matrix_solver_total_cols"}, ": ", num_cols}
end
