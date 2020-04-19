require("info_pane")

-- Creates the subfactory pane that includes the products, byproducts and ingredients, and an info-pane
function add_subfactory_pane_to(main_dialog)
    local table_subfactory = main_dialog.add{type="table", name="table_subfactory_pane",
      column_count=4, style="table", visible=false}
    table_subfactory.draw_vertical_lines = true
    table_subfactory.style.vertically_squashable = false
    table_subfactory.style.height = 153
    table_subfactory.style.bottom_margin = 10
    
    local player = game.get_player(main_dialog.player_index)
    local pane_width = ((get_ui_state(player).main_dialog_dimensions.width - 2*18) / 4)
    local panes = {"info", "ingredient", "product", "byproduct"}

    for _, pane_name in ipairs(panes) do
        local flow = table_subfactory.add{type="flow", name="flow_" .. pane_name, direction="vertical"}
        flow.style.vertically_stretchable = true
        flow.style.width = pane_width

        local label_title = flow.add{type="label", name="label_title", caption={"fp." .. pane_name}}
        label_title.style.font = "fp-font-16p"
        label_title.style.left_padding = 4

        local scroll_pane = flow.add{type="scroll-pane", name="scroll-pane", direction="vertical",
          style="fp_scroll_pane_items"}

        if pane_name ~= "info" then
            local item_table = scroll_pane.add{type="table", name="item_table",
              column_count=get_settings(player).items_per_row}
            item_table.style.horizontal_spacing = 8
            item_table.style.vertical_spacing = 4
            item_table.style.top_margin = 4
        end
    end
    
    refresh_subfactory_pane(player)
end


-- Refreshes the subfactory pane by reloading the data
function refresh_subfactory_pane(player)
    local ui_state = get_ui_state(player)

    local view_state = ui_state.view_state
    if view_state == nil then return end
    
    local table_subfactory = player.gui.screen["fp_frame_main_dialog"]["table_subfactory_pane"]
    if table_subfactory == nil then return end
    
    local subfactory = ui_state.context.subfactory
    table_subfactory.visible = (subfactory ~= nil and subfactory.valid)

    if table_subfactory.visible then
        refresh_info_pane(player)

        refresh_item_table(player, "Ingredient")
        refresh_item_table(player, "Product")
        refresh_item_table(player, "Byproduct")
    end
end

-- Refreshes the given kind of item table
function refresh_item_table(player, class)
    local ui_state = get_ui_state(player)
    local ui_name = class:gsub("^%u", string.lower)
    
    local item_table = player.gui.screen["fp_frame_main_dialog"]["table_subfactory_pane"]
      ["flow_" .. ui_name]["scroll-pane"]["item_table"]
    item_table.clear()
    
    local subfactory = ui_state.context.subfactory
    local items = nil
    local display_mode = (ui_state.flags.floor_total and subfactory.selected_floor.level > 1)
      and "floor_total" or "standard"
    
    -- Only show the totals for the current floor if the toggle is active
    if display_mode == "floor_total" then
        local parent_line = ui_state.context.floor.origin_line  -- must exist if selected_floor.level > 1
        if parent_line[class].count > 0 then
            -- Combine Fuel and Ingredients into a single item list
            items = (class ~= "Ingredient") and Line.get_in_order(parent_line, class) or Collection.get_in_order(
              Subfactory.combine_item_collections(subfactory, parent_line.Ingredient, parent_line.Fuel))
        end

    -- Otherwise, show the subfactory totals, if there are any
    elseif subfactory[class].count > 0 then
        items = Subfactory.get_in_order(subfactory, class)
    end

    if items ~= nil then _refresh_item_table(player, item_table, class, items, display_mode) end

    -- Add button to add new products to its table
    if class == "Product" then
        local button_add = item_table.add{type="sprite-button", name="fp_sprite-button_add_product", sprite="fp_sprite_plus",
          style="fp_sprite-button_inset", tooltip={"fp.add_a_product"}, mouse_button_filter={"left"},
          visible=(display_mode == "standard"), enabled=(not ui_state.flags.archive_open)}
        button_add.style.height = 36
        button_add.style.width = 36
        button_add.style.padding = 3
    end
end


-- Refreshes the item table of the given class
function _refresh_item_table(player, item_table, class, items, display_mode)
    local player_table = get_table(player)
    local ui_state = player_table.ui_state
    
    local ui_name = class:gsub("^%u", string.lower)
    local view_name = ui_state.view_state.selected_view.name

    local round_belts = (view_name == "belts_or_lanes" and player_table.preferences.round_button_numbers)
    local tutorial_tooltip = ui_util.tutorial_tooltip(player, nil, ("tl_" .. ui_name), true)
    local style = "fp_button_icon_large_blank"  -- will remain untouched if the display mode is 'floor_total'

    for _, item in ipairs(items) do
        local item_amount = (display_mode == "standard" and class == "Product") and item.required_amount or item.amount
        local display_amount, appendage = ui_util.determine_item_amount_and_appendage(player_table, view_name,
          item.proto.type, item_amount, nil)

        if display_amount == nil or display_amount > margin_of_error then
            local secondary_number = ""

            if display_mode == "standard" then
                -- Determine style needed for top level items, plus some adjustments for Products
                if class == "Ingredient" then
                    style = "fp_button_icon_large_blank"
                elseif class == "Byproduct" then
                    style = "fp_button_icon_large_red"
                else  -- class == "Product"
                    if item.amount <= 0 then
                        style = "fp_button_icon_large_red"
                    elseif item.amount < item.required_amount then
                        style = "fp_button_icon_large_yellow"
                    elseif item.amount == item.required_amount then
                        style = "fp_button_icon_large_green"
                    else  -- overproduction, should not happen normally
                        style = "fp_button_icon_large_cyan"
                    end

                    -- Add the secondary amount to Products only
                    local secondary_amount = ui_util.determine_item_amount_and_appendage(player_table, view_name,
                      item.proto.type, item.amount, nil)  -- appendage is not needed here, thus ignored
                    secondary_number = (secondary_amount) and ui_util.format_number(secondary_amount, 4) .. " / " or ""
                end
            end

            local number_line, button_number = "", nil
            if display_amount ~= nil then  -- Don't show a number if no display_amount was determined (fluids)
                number_line = {"", "\n" .. secondary_number .. ui_util.format_number(display_amount, 4)
                  .. " ", appendage}
                button_number = (round_belts) and math.ceil(display_amount) or display_amount
            end
            local tooltip = {"", item.proto.localised_name, number_line, tutorial_tooltip}

            local button = item_table.add{type="sprite-button", name="fp_sprite-button_subpane_" .. ui_name .. "_"
              .. item.id, sprite=item.proto.sprite, number=button_number, tooltip=tooltip,
              style=style, enabled=(display_mode == "standard"), mouse_button_filter={"left-and-right"}}
        end
    end
end


-- Handles click on a subfactory pane ingredient button
function handle_ingredient_element_click(player, ingredient_id, click, direction, action, alt)
    local subfactory = get_context(player).subfactory
    local ingredient = Subfactory.get(subfactory, "Ingredient", ingredient_id)

    if alt then
        ui_util.execute_alt_action(player, "show_item", {item=ingredient.proto, click=click})
        
    elseif ui_util.check_archive_status(player) then 
        return
        
    elseif direction ~= nil then  -- Shift product in the given direction
        if Subfactory.shift(subfactory, ingredient, direction) then
            refresh_item_table(player, "Ingredient")
        else
            local direction_string = (direction == "negative") and {"fp.left"} or {"fp.right"}
            local message = {"fp.error_list_item_cant_be_shifted", {"fp.lingredient"}, direction_string}
            ui_util.message.enqueue(player, message, "error", 1, false)
        end
        
        refresh_current_activity(player)
    end
end

-- Handles click on a subfactory pane product button
function handle_product_element_click(player, product_id, click, direction, action, alt)
    local context = get_context(player)
    local subfactory = context.subfactory
    local product = Subfactory.get(subfactory, "Product", product_id)

    if alt then
        ui_util.execute_alt_action(player, "show_item", {item=product.proto, click=click})
        
    elseif ui_util.check_archive_status(player) then
        return

    elseif direction ~= nil then  -- Shift product in the given direction
        if Subfactory.shift(subfactory, product, direction) then
            refresh_item_table(player, "Product")
        else
            local direction_string = (direction == "negative") and {"fp.left"} or {"fp.right"}
            local message = {"fp.error_list_item_cant_be_shifted", {"fp.lproduct"}, direction_string}
            ui_util.message.enqueue(player, message, "error", 1, false)
        end
        
        refresh_current_activity(player)

    else
        if click == "left" then
            if context.floor.level == 1 then
                enter_modal_dialog(player, {type="recipe", modal_data={product=product, production_type="produce"}})
            else
                ui_util.message.enqueue(player, {"fp.error_product_wrong_floor"}, "error", 1, true)
            end
        elseif click == "right" then
            if action == "edit" then
                enter_modal_dialog(player, {type="product", submit=true, delete=true, modal_data={product=product}})

            elseif action == "delete" then
                Subfactory.remove(subfactory, product)

                -- Remove useless recipes after a product has been deleted
                calculation.update(player, subfactory, false)
                Subfactory.remove_useless_lines(subfactory)

                calculation.update(player, subfactory, true)
            end
        end
    end
end

-- Handles click on a subfactory pane byproduct button
function handle_byproduct_element_click(player, byproduct_id, click, direction, action, alt)
    local context = get_context(player)
    local subfactory = context.subfactory
    local byproduct = Subfactory.get(subfactory, "Byproduct", byproduct_id)
    
    if alt then
        ui_util.execute_alt_action(player, "show_item", {item=byproduct.proto, click=click})

    elseif ui_util.check_archive_status(player) then 
        return

    elseif direction ~= nil then  -- Shift product in the given direction
        if Subfactory.shift(subfactory, byproduct, direction) then
            refresh_item_table(player, "Byproduct")
        else
            local direction_string = (direction == "negative") and {"fp.left"} or {"fp.right"}
            local message = {"fp.error_list_item_cant_be_shifted", {"fp.lbyproduct"}, direction_string}
            ui_util.message.enqueue(player, message, "error", 1, false)
        end
        
        refresh_current_activity(player)

    elseif click == "left" then
        if context.floor.level ~= 1 then
            ui_util.message.enqueue(player, {"fp.error_byproduct_wrong_floor"}, "error", 1, true)

        -- Byproduct recipes can only be added when the matrix solver is active
        elseif get_settings(player).prefer_matrix_solver then
            enter_modal_dialog(player, {type="recipe", modal_data={product=byproduct, production_type="consume"}})
        end
    end
end