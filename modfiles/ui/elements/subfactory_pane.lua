require("ui.elements.info_pane")

-- Creates the subfactory pane that includes the products, byproducts and ingredients
function add_subfactory_pane_to(main_dialog)
    local table = main_dialog.add{type="table", name="table_subfactory_pane", column_count=4, style="table"}
    table.draw_vertical_lines = true
    table.style.vertically_squashable = false
    table.style.height = 153
    table.style.bottom_margin = 10

    refresh_subfactory_pane(game.get_player(main_dialog.player_index))
end


-- Refreshes the subfactory pane by reloading the data
function refresh_subfactory_pane(player)
    local table_subfactory =  player.gui.center["fp_frame_main_dialog"]["table_subfactory_pane"]
    -- Cuts function short if the subfactory pane hasn't been initialized yet
    if not table_subfactory then return end

    local subfactory = get_context(player).subfactory
    table_subfactory.visible = (subfactory ~= nil and subfactory.valid)
    
    table_subfactory.clear()
    if subfactory ~= nil and subfactory.valid then
        -- Info cell
        add_subfactory_pane_cell_to(player, table_subfactory, "info")
        refresh_info_pane(player)
        
        -- The three item cells
        local classes = {"Ingredient", "Product", "Byproduct"}
        for _, class in pairs(classes) do
            local ui_name = class:gsub("^%u", string.lower) .. "s"
            local scroll_pane = add_subfactory_pane_cell_to(player, table_subfactory, ui_name)
            if scroll_pane["item_table"] == nil then init_item_table(scroll_pane, get_settings(player).items_per_row) end
            refresh_item_table(player, class)
        end
    end
end


-- Constructs the basic structure of a subfactory_pane-cell
function add_subfactory_pane_cell_to(player, table, ui_name)
    local width = ((get_ui_state(player).main_dialog_dimensions.width - 2*18) / 4)
    local flow = table.add{type="flow", name="flow_" .. ui_name, direction="vertical"}
    flow.style.width = width
    flow.style.vertically_stretchable = true
    local label_title = flow.add{type="label", name="label_" .. ui_name .. "_title", 
     caption={"", "  ", {"label." .. ui_name}}}
    label_title.style.font = "fp-font-16p"
    local scroll_pane = flow.add{type="scroll-pane", name="scroll-pane", direction="vertical",
      style="fp_scroll_pane_items"}

    return scroll_pane
end

-- Initializes the item table of the given scroll_pane
function init_item_table(scroll_pane, column_count)
    local item_table = scroll_pane.add{type="table", name="item_table", column_count=column_count}
    item_table.style.horizontal_spacing = 8
    item_table.style.vertical_spacing = 4
    item_table.style.top_margin = 4
end

-- Refreshes the given kind of item table
function refresh_item_table(player, class)
    local player_table = get_table(player)

    local ui_name = class:gsub("^%u", string.lower)
    local item_table = player.gui.center["fp_frame_main_dialog"]["table_subfactory_pane"]["flow_" .. ui_name .. "s"]
      ["scroll-pane"]["item_table"]
    item_table.clear()

    -- Only show the totals for the current floor, if the toggle is active
    if get_ui_state(player).floor_total then
        local parent_line = get_context(player).floor.origin_line
        if parent_line ~= nil and parent_line[class].count > 0 then
            for _, item in ipairs(Line.get_in_order(parent_line, class)) do
                local button = item_table.add{type="sprite-button", name="fp_sprite-button_subpane_" .. ui_name .. "_"
                  .. item.id, sprite=item.sprite, style="fp_button_icon_large_blank", number=item.amount, enabled=false}

                ui_util.setup_item_button(player_table, button, item, false)
                if button.number ~= nil and button.number < margin_of_error then button.visible = false end
            end
        end
        
    -- Otherwise, show the subfactory totals
    else
        local subfactory = get_context(player).subfactory
        if subfactory[class].count > 0 then
            for _, item in ipairs(Subfactory.get_in_order(subfactory, class)) do
                local style = determine_button_style(item)
                local button = item_table.add{type="sprite-button", name="fp_sprite-button_subpane_" .. ui_name .. "_" 
                  .. item.id, sprite=item.sprite, style=style, mouse_button_filter={"left-and-right"}}
                  
                ui_util.setup_item_button(player_table, button, item, true)
                ui_util.add_tutorial_tooltip(button, "tl_" .. string.lower(class), true, true)
                if button.number ~= nil and button.number < margin_of_error then button.visible = false end
            end
        end

        local append_function = _G["append_to_" .. ui_name .. "_table"]
        if append_function ~= nil then append_function(item_table) end
    end
end

-- Determines the button style, depending on the class of the item
function determine_button_style(item)
    if item.class == "Ingredient" then
        return "fp_button_icon_large_blank"
    elseif item.class == "Byproduct" then
        return "fp_button_icon_large_red"
    else  -- item.class == "Product"
        if item.amount == 0 then
            return "fp_button_icon_large_red"
        elseif item.amount < item.required_amount then
            return "fp_button_icon_large_yellow"
        elseif item.amount == item.required_amount then
            return "fp_button_icon_large_green"
        else
            return "fp_button_icon_large_cyan"
        end
    end
end

-- Adds the button to add a product to the table
function append_to_product_table(table)
    local button = table.add{type="sprite-button", name="fp_sprite-button_add_product", sprite="fp_sprite_plus",
      style="fp_sprite-button_inset", tooltip={"tooltip.add_product"}, mouse_button_filter={"left"}}
    button.style.height = 36
    button.style.width = 36
    button.style.padding = 3
end


-- Opens clicked element in FNEI or shifts it left or right
function handle_ingredient_element_click(player, ingredient_id, click, direction, alt)
    local subfactory = get_context(player).subfactory
    local ingredient = Subfactory.get(subfactory, "Ingredient", ingredient_id)

    if alt then  -- Open item in FNEI
        ui_util.fnei.show_item(ingredient, click)
        
    elseif direction ~= nil then  -- Shift product in the given direction
        Subfactory.shift(subfactory, ingredient, direction)
        refresh_item_table(player, "Ingredient")
    end
end

-- Handles click on a subfactory pane product button
function handle_product_element_click(player, product_id, click, direction, alt)
    local context = get_context(player)
    local product = Subfactory.get(context.subfactory, "Product", product_id)

    if alt then  -- Open item in FNEI
        ui_util.fnei.show_item(product, click)

    elseif direction ~= nil then  -- Shift product in the given direction
        Subfactory.shift(context.subfactory, product, direction)

    else  -- Open modal dialogs
        if click == "left" then
            if context.floor.level == 1 then
                enter_modal_dialog(player, {type="recipe_picker", object=product, preserve=true})
            else
                queue_message(player, {"label.error_product_wrong_floor"}, "warning")
            end
        elseif click == "right" then
            enter_modal_dialog(player, {type="item_picker", object=product, preserve=true, submit=true, delete=true})
        end
    end
    
    refresh_item_table(player, "Product")
end


-- Handles click on a subfactory pane byproduct button
function handle_byproduct_element_click(player, byproduct_id, click, direction, alt)
    local context = get_context(player)
    local byproduct = Subfactory.get(context.subfactory, "Byproduct", byproduct_id)
    
    if alt then  -- Open item in FNEI
        ui_util.fnei.show_item(byproduct, click)

    elseif direction ~= nil then  -- Shift product in the given direction
        Subfactory.shift(context.subfactory, byproduct, direction)

    -- Open recipe dialog? Dealing with byproducts will come at a later stage
    elseif click == "left" then
        local floor = context.floor
        if floor.level == 1 then
            --enter_modal_dialog(player, {type="recipe_picker", object=byproduct, preserve=true})
        else
            --queue_message(player, {"label.error_byproduct_wrong_floor"}, "warning")
        end
    end

    refresh_item_table(player, "Byproduct")
end