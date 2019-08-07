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
    local table_subfactory =  player.gui.screen["fp_frame_main_dialog"]["table_subfactory_pane"]
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
    local subfactory = get_context(player).subfactory

    local ui_name = class:gsub("^%u", string.lower)
    local item_table = player.gui.screen["fp_frame_main_dialog"]["table_subfactory_pane"]["flow_" .. ui_name .. "s"]
      ["scroll-pane"]["item_table"]
    item_table.clear()

    -- Only show the totals for the current floor, if the toggle is active
    if get_ui_state(player).floor_total and subfactory.selected_floor.level > 1 then
        local parent_line = get_context(player).floor.origin_line
        if parent_line ~= nil and parent_line[class].count > 0 then
            for _, item in ipairs(Line.get_in_order(parent_line, class)) do
                local button = item_table.add{type="sprite-button", name="fp_sprite-button_subpane_" .. ui_name .. "_"
                  .. item.id, sprite=item.proto.sprite, style="fp_button_icon_large_blank", number=item.amount, enabled=false}

                ui_util.setup_item_button(player_table, button, item)
                if button.number ~= nil and button.number < margin_of_error then button.visible = false end
            end
        end
        
    -- Otherwise, show the subfactory totals
    else
        if subfactory[class].count > 0 then
            for _, item in ipairs(Subfactory.get_in_order(subfactory, class)) do
                local style = determine_button_style(item)
                local button = item_table.add{type="sprite-button", name="fp_sprite-button_subpane_" .. ui_name .. "_" 
                  .. item.id, sprite=item.proto.sprite, style=style, mouse_button_filter={"left-and-right"}}
                  
                ui_util.setup_item_button(player_table, button, item)
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
                enter_modal_dialog(player, {type="recipe_picker", object=product})
            else
                ui_util.message.enqueue(player, {"label.error_product_wrong_floor"}, "error", 1)
            end
        elseif click == "right" then
            enter_modal_dialog(player, {type="item_picker", object=product, submit=true, delete=true})
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
            --enter_modal_dialog(player, {type="recipe_picker", object=byproduct})
        else
            --ui_util.message.enqueue(player, {"label.error_byproduct_wrong_floor"}, "error", 1)
        end
    end

    refresh_item_table(player, "Byproduct")
end


-- Constructs the info pane including timescale settings
function refresh_info_pane(player)
    local ui_state = get_ui_state(player)
    local context = ui_state.context
    local subfactory = context.subfactory

    local flow = player.gui.screen["fp_frame_main_dialog"]["table_subfactory_pane"]["flow_info"]["scroll-pane"]
    flow.style.left_margin = 0

    if flow["table_info_elements"] == nil then
        flow.add{type="table", name="table_info_elements", column_count=1}
        flow["table_info_elements"].style.vertical_spacing = 6
    else
        flow["table_info_elements"].clear()
    end
    
    -- Timescale
    local table_timescale = flow["table_info_elements"].add{type="table", name="table_timescale_buttons", column_count=2}
    local label_timescale_title = table_timescale.add{type="label", name="label_timescale_title",
      caption={"", " ", {"label.timescale"}, " [img=info]: "}, tooltip={"tooltip.timescales"}}
    label_timescale_title.style.font = "fp-font-14p"
    table_timescale.style.bottom_margin = 4

    local timescales = {["1s"] = 1, ["1m"] = 60, ["1h"] = 3600}
    local table_timescales = table_timescale.add{type="table", name="table_timescales", column_count=table_size(timescales)}
    table_timescales.style.horizontal_spacing = 0
    table_timescales.style.left_margin = 2
    for caption, scale in pairs(timescales) do  -- Factorio-Lua preserving ordering is important here
        local button = table_timescales.add{type="button", name=("fp_button_timescale_" .. scale), caption=caption,
          mouse_button_filter={"left"}}
        button.enabled = (not (subfactory.timescale == scale))
        button.style = (subfactory.timescale == scale) and "fp_button_timescale_selected" or "fp_button_timescale"
    end

    -- Notes
    local table_notes = flow["table_info_elements"].add{type="table", name="table_notes", column_count=2}
    local label_notes = table_notes.add{type="label", name="label_notes_title", caption={"", " ",  {"label.notes"}, ":  "}}
    label_notes.style.font = "fp-font-14p"
    label_notes.style.bottom_padding = 2
    table_notes.add{type="button", name="fp_button_view_notes", caption={"button-text.view_notes"},
      style="fp_button_mini", mouse_button_filter={"left"}}

    -- Power Usage
    local table_energy_consumption = flow["table_info_elements"].add{type="table", name="table_energy_consumption",
      column_count=2}
    table_energy_consumption.add{type="label", name="label_energy_consumption_title", 
      caption={"", " ",  {"label.energy_consumption"}, ": "}}
    table_energy_consumption["label_energy_consumption_title"].style.font = "fp-font-14p"

    -- Show either subfactory or floor energy consumption, depending on the floor_total toggle
    local origin_line = context.floor.origin_line
    local energy_consumption = (ui_state.floor_total and origin_line ~= nil) and
      origin_line.energy_consumption or subfactory.energy_consumption
    
    local label_energy = table_energy_consumption.add{type="label", name="label_energy_consumption",
      caption=ui_util.format_SI_value(energy_consumption, "W", 3),
      tooltip=ui_util.format_SI_value(energy_consumption, "W", 5)}
    label_energy.style.font = "default-bold"

    -- Mining Productivity
    local table_mining_prod = flow["table_info_elements"].add{type="table", name="table_mining_prod", column_count=3}
    table_mining_prod.add{type="label", name="label_mining_prod_title",
      caption={"", " ",  {"label.mining_prod"}, " [img=info]: "}, tooltip={"tooltip.mining_prod"}}
    table_mining_prod["label_mining_prod_title"].style.font = "fp-font-14p"

    if ui_state.current_activity == "overriding_mining_prod" or subfactory.mining_productivity ~= nil then
        subfactory.mining_productivity = subfactory.mining_productivity or 0
        local textfield_prod_bonus = table_mining_prod.add{type="textfield", name="fp_textfield_mining_prod",
          text=(subfactory.mining_productivity or 0)}
        textfield_prod_bonus.style.width = 60
        textfield_prod_bonus.style.height = 26
        ui_util.setup_numeric_textfield(textfield_prod_bonus, true, true)
        local label_percentage = table_mining_prod.add{type="label", name="label_percentage", caption="%"}
        label_percentage.style.font = "default-bold"
    else
        local label_prod_bonus = table_mining_prod.add{type="label", name="label_mining_prod_value", 
          caption={"", player.force.mining_drill_productivity_bonus, "%"}}
        label_prod_bonus.style.font = "default-bold"
        local button_override = table_mining_prod.add{type="button", name="fp_button_mining_prod_override", 
          caption={"button-text.override"}, style="fp_button_mini", mouse_button_filter={"left"}}
        button_override.style.left_margin = 8
    end
end


-- Handles the timescale changing process
function handle_subfactory_timescale_change(player, timescale)
    local subfactory = get_context(player).subfactory
    subfactory.timescale = timescale
    get_ui_state(player).current_activity = nil
    update_calculations(player, subfactory)
end

-- Activates the mining prod override mode for the current subfactory
function mining_prod_override(player)
    get_ui_state(player).current_activity = "overriding_mining_prod"
    refresh_main_dialog(player)
end

-- Persists changes to the overriden mining productivity
function handle_mining_prod_change(player, element)
    local subfactory = get_context(player).subfactory
    subfactory.mining_productivity = tonumber(element.text)
end