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
    
    -- Only show the totals for the current floor if the toggle is active
    if ui_state.flags.floor_total and subfactory.selected_floor.level > 1 then
        local parent_line = ui_state.context.floor.origin_line
        if parent_line ~= nil and parent_line[class].count > 0 then
            items = (class ~= "Ingredient") and Line.get_in_order(parent_line, class) or Collection.get_in_order(
              Subfactory.combine_item_collections(subfactory, parent_line.Ingredient, parent_line.Fuel))
        end

    -- Otherwise, show the subfactory totals
    elseif subfactory[class].count > 0 then
        items = Subfactory.get_in_order(subfactory, class)
    end

    if items ~= nil then _refresh_item_table(player, item_table, class, items) end

    -- Add button to add new products to its table
    if class == "Product" then
        local button_add = item_table.add{type="sprite-button", name="fp_sprite-button_add_product", sprite="fp_sprite_plus",
          style="fp_sprite-button_inset", tooltip={"fp.add_a_product"}, mouse_button_filter={"left"},
          enabled=(not ui_state.flags.archive_open)}
        button_add.style.height = 36
        button_add.style.width = 36
        button_add.style.padding = 3
    end
end


-- Refreshes the item table of the given class
function _refresh_item_table(player, item_table, class, items)
    local player_table = get_table(player)
    local ui_state = player_table.ui_state
    
    local ui_name = class:gsub("^%u", string.lower)
    local floor_total = ui_state.flags.floor_total
    local view_name = ui_state.view_state.selected_view.name

    local round_belts = (view_name == "belts_or_lanes" and player_table.settings.round_button_numbers)
    local tutorial_tooltip = ui_util.tutorial_tooltip(player, nil, ("tl_" .. ui_name), true)
    local style = "fp_button_icon_large_blank"

    for _, item in ipairs(items) do
        local item_amount, secondary_number = item.amount, ""

        if not floor_total then
            -- Determine item amount to be shown on the button
            item_amount = item.required_amount

            -- Format the secondary number for the tooltip
            local secondary_amount = ui_util.determine_item_amount_and_appendage(player_table, view_name,
                item.proto.type, item.amount, nil)  -- appendage is not needed here, thus ignored
            if secondary_amount ~= nil then secondary_number = ui_util.format_number(secondary_amount, 4) .. " / " end

            -- Determine style needed for top level items
            if item.class == "Ingredient" then
                style = "fp_button_icon_large_blank"
            elseif item.class == "Byproduct" then
                style = "fp_button_icon_large_red"
            else  -- item.class == "Product"
                if item.amount <= 0 then
                    style = "fp_button_icon_large_red"
                elseif item.amount < item.required_amount then
                    style = "fp_button_icon_large_yellow"
                elseif item.amount == item.required_amount then
                    style = "fp_button_icon_large_green"
                else  -- overproduction, should not happen normally
                    style = "fp_button_icon_large_cyan"
                end
            end
        end

        local raw_amount, appendage = ui_util.determine_item_amount_and_appendage(player_table, view_name,
          item.proto.type, item_amount, nil)

        if (raw_amount ~= nil and ((raw_amount > margin_of_error)) or (class == "Product" and not floor_total)) then
            local number_line = (raw_amount ~= nil) and {"", ui_util.format_number(raw_amount, 4) .. " ", appendage} or ""
            local tooltip = {"", item.proto.localised_name, "\n" .. secondary_number, number_line, tutorial_tooltip}
            local button_number = (round_belts and raw_amount ~= nil) and math.ceil(raw_amount) or raw_amount

            local button = item_table.add{type="sprite-button", name="fp_sprite-button_subpane_" .. ui_name .. "_"
              .. item.id, sprite=item.proto.sprite, number=button_number, tooltip=tooltip,
              style=style, enabled=(not floor_total), mouse_button_filter={"left-and-right"}}
        end
    end
end


-- Opens clicked element in FNEI or shifts it left or right
function handle_ingredient_element_click(player, ingredient_id, click, direction, action, alt)
    local subfactory = get_context(player).subfactory
    local ingredient = Subfactory.get(subfactory, "Ingredient", ingredient_id)

    if alt then  -- Open item in FNEI
        ui_util.fnei.show_item(ingredient, click)
        
    elseif ui_util.check_archive_status(player) then 
        return
        
    elseif direction ~= nil then  -- Shift product in the given direction
        Subfactory.shift(subfactory, ingredient, direction)
        refresh_item_table(player, "Ingredient")
    end
end

-- Handles click on a subfactory pane product button
function handle_product_element_click(player, product_id, click, direction, action, alt)
    local context = get_context(player)
    local subfactory = context.subfactory
    local product = Subfactory.get(subfactory, "Product", product_id)

    if alt then  -- Open item in FNEI
        ui_util.fnei.show_item(product, click)
        
    elseif ui_util.check_archive_status(player) then
        return

    elseif direction ~= nil then  -- Shift product in the given direction
        Subfactory.shift(subfactory, product, direction)
        refresh_item_table(player, "Product")

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
    local byproduct = Subfactory.get(context.subfactory, "Byproduct", byproduct_id)
    
    if alt then  -- Open item in FNEI
        ui_util.fnei.show_item(byproduct, click)

    elseif ui_util.check_archive_status(player) then 
        return

    elseif direction ~= nil then  -- Shift product in the given direction
        Subfactory.shift(context.subfactory, byproduct, direction)
        refresh_item_table(player, "Byproduct")

    elseif click == "left" then
        local floor = context.floor
        if floor.level == 1 then
            --enter_modal_dialog(player, {type="recipe", modal_data={product=byproduct, production_type="consume"}})
        else
            --ui_util.message.enqueue(player, {"fp.error_byproduct_wrong_floor"}, "error", 1, true)
        end
    end
end