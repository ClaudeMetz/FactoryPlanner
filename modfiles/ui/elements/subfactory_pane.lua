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
     caption={"", "  ", {"fp." .. ui_name}}}
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
            local items = (class ~= "Ingredient") and Line.get_in_order(parent_line, class) or Collection.get_in_order(
              Subfactory.combine_item_collections(subfactory, parent_line.Ingredient, parent_line.Fuel))

            for _, item in ipairs(items) do
                local button = item_table.add{type="sprite-button", name="fp_sprite-button_subpane_" .. ui_name .. "_"
                  .. item.id, sprite=item.proto.sprite, style="fp_button_icon_large_blank", enabled=false}

                ui_util.setup_item_button(player_table, button, item, nil, true)
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
                  
                ui_util.setup_item_button(player_table, button, item, nil)
                ui_util.add_tutorial_tooltip(player, button, nil, "tl_" .. string.lower(class), true, true)
                if button.number ~= nil and class ~= "Product" and button.number < margin_of_error then button.visible = false end
            end
        end

        local append_function = _G["append_to_" .. ui_name .. "_table"]
        if append_function ~= nil then append_function(player, item_table) end
    end
end

-- Determines the button style, depending on the class of the item
function determine_button_style(item)
    if item.class == "Ingredient" then
        return "fp_button_icon_large_blank"
    elseif item.class == "Byproduct" then
        return "fp_button_icon_large_red"
    else  -- item.class == "Product"
        if item.amount <= 0 then
            return "fp_button_icon_large_red"
        elseif item.amount < item.required_amount then
            return "fp_button_icon_large_yellow"
        elseif item.amount == item.required_amount then
            return "fp_button_icon_large_green"
        else  -- overproduction, should not happen normally
            return "fp_button_icon_large_cyan"
        end
    end
end

-- Adds the button to add a product to the table
function append_to_product_table(player, table)
    local button = table.add{type="sprite-button", name="fp_sprite-button_add_product", sprite="fp_sprite_plus",
      style="fp_sprite-button_inset", tooltip={"fp.add_a_product"}, mouse_button_filter={"left"},
      enabled=(not ui_util.check_archive_status(player, true))}
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
        
    elseif ui_util.check_archive_status(player) then 
        return
        
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
        
    elseif ui_util.check_archive_status(player) then
        return

    elseif direction ~= nil then  -- Shift product in the given direction
        Subfactory.shift(context.subfactory, product, direction)
        refresh_item_table(player, "Product")

    else  -- Open modal dialogs
        if click == "left" then
            if context.floor.level == 1 then
                enter_modal_dialog(player, {type="recipe_picker", object=product, modal_data={production_type="produce"}})
            else
                ui_util.message.enqueue(player, {"fp.error_product_wrong_floor"}, "error", 1)
            end
        elseif click == "right" then
            enter_modal_dialog(player, {type="item_picker", object=product, submit=true, delete=true})
        end
    end
end


-- Handles click on a subfactory pane byproduct button
function handle_byproduct_element_click(player, byproduct_id, click, direction, alt)
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
            --enter_modal_dialog(player, {type="recipe_picker", object=byproduct, modal_data={production_type="consume"}})
        else
            --ui_util.message.enqueue(player, {"fp.error_byproduct_wrong_floor"}, "error", 1)
        end
    end
end


-- Constructs the info pane including timescale settings
function refresh_info_pane(player)
    local ui_state = get_ui_state(player)
    local context = ui_state.context
    local subfactory = context.subfactory

    local flow = player.gui.screen["fp_frame_main_dialog"]["table_subfactory_pane"]["flow_info"]["scroll-pane"]
    flow.style.left_margin = 0

    local table_info_elements = flow["table_info_elements"]
    if table_info_elements == nil then
        table_info_elements = flow.add{type="table", name="table_info_elements", column_count=1}
        table_info_elements.style.vertical_spacing = 6
        table_info_elements.style.left_margin = 6
    else
        table_info_elements.clear()
    end
    

    -- Timescale
    local table_timescale = table_info_elements.add{type="table", name="table_timescale_buttons", column_count=2}
    local label_timescale_title = table_timescale.add{type="label", name="label_timescale_title",
      caption={"", {"fp.timescale"}, " [img=info]: "}, tooltip={"fp.timescales_tt"}}
    label_timescale_title.style.font = "fp-font-14p"
    table_timescale.style.bottom_margin = 4

    local timescales = {1, 60, 3600}
    local table_timescales = table_timescale.add{type="table", name="table_timescales", column_count=table_size(timescales)}
    table_timescales.style.horizontal_spacing = 0
    table_timescales.style.left_margin = 2
    for _, scale in pairs(timescales) do
        local button = table_timescales.add{type="button", name=("fp_button_timescale_" .. scale),
          caption=ui_util.format_timescale(scale), mouse_button_filter={"left"}}
        button.enabled = (not (subfactory.timescale == scale))
        button.style = (subfactory.timescale == scale) and "fp_button_timescale_selected" or "fp_button_timescale"
    end


    -- Notes
    local table_notes = table_info_elements.add{type="table", name="table_notes", column_count=2}
    local label_notes = table_notes.add{type="label", name="label_notes_title", caption={"", {"fp.notes"}, ":  "}}
    label_notes.style.font = "fp-font-14p"
    label_notes.style.bottom_padding = 2
    local button_notes = table_notes.add{type="button", name="fp_button_view_notes", caption={"fp.view_notes"},
      style="fp_button_mini", mouse_button_filter={"left"}}
    button_notes.tooltip = (string.len(subfactory.notes) < 750) and
      subfactory.notes or string.sub(subfactory.notes, 1, 750) .. "\n[...]"


    -- Power Usage + Pollution
    local table_energy_pollution = table_info_elements.add{type="table", name="table_energy_pollution", column_count=2}
    table_energy_pollution.draw_vertical_lines = true
    table_energy_pollution.style.horizontal_spacing = 20

    -- Show either subfactory or floor energy/pollution, depending on the floor_total toggle
    local origin_line = context.floor.origin_line
    local energy_consumption, pollution
    if ui_state.floor_total and origin_line ~= nil then
        energy_consumption = origin_line.energy_consumption
        pollution = origin_line.pollution
    else
        energy_consumption = subfactory.energy_consumption
        pollution = subfactory.pollution
    end

    -- Energy consumption
    local table_energy = table_energy_pollution.add{type="table", name="table_energy", column_count=2}
    local label_energy_title = table_energy.add{type="label", name="label_energy_title", 
      caption={"", {"fp.energy"}, ":"}}
    label_energy_title.style.font = "fp-font-14p"
    local label_energy_value = table_energy.add{type="label", name="label_energy_value", 
      caption=ui_util.format_SI_value(energy_consumption, "W", 3),
      tooltip=ui_util.format_SI_value(energy_consumption, "W", 5)}
    label_energy_value.style.font = "default-bold"

    -- Pollution
    local table_pollution = table_energy_pollution.add{type="table", name="table_pollution", column_count=2}
    local label_pollution_title = table_pollution.add{type="label", name="label_pollution_title",
      caption={"", {"fp.cpollution"}, ":"}}
    label_pollution_title.style.font = "fp-font-14p"
    local label_pollution_value = table_pollution.add{type="label", name="label_pollution_value", 
      caption={"", ui_util.format_SI_value(pollution, "P/s", 3)},
      tooltip={"", ui_util.format_SI_value(pollution, "P/s", 5)}}
    label_pollution_value.style.font = "default-bold"


    -- Mining Productivity
    local table_mining_prod = table_info_elements.add{type="table", name="table_mining_prod", column_count=3}
    table_mining_prod.add{type="label", name="label_mining_prod_title",
      caption={"", {"fp.mining_prod"}, " [img=info]: "}, tooltip={"fp.mining_prod_tt"}}
    table_mining_prod["label_mining_prod_title"].style.font = "fp-font-14p"

    if ui_state.current_activity == "overriding_mining_prod" or subfactory.mining_productivity ~= nil then
        subfactory.mining_productivity = subfactory.mining_productivity or 0  -- switch from no mining prod to a custom one
        local textfield_prod_bonus = table_mining_prod.add{type="textfield", name="fp_textfield_mining_prod",
          text=(subfactory.mining_productivity or 0)}
        textfield_prod_bonus.style.width = 60
        textfield_prod_bonus.style.height = 26
        ui_util.setup_numeric_textfield(textfield_prod_bonus, true, true)
        local label_percentage = table_mining_prod.add{type="label", name="label_percentage", caption="%"}
        label_percentage.style.font = "default-bold"
    else
        local prod_bonus = ui_util.format_number((player.force.mining_drill_productivity_bonus * 100), 4)
        local label_prod_bonus = table_mining_prod.add{type="label", name="label_mining_prod_value", 
          caption={"", prod_bonus, "%"}}
        label_prod_bonus.style.font = "default-bold"
        local button_override = table_mining_prod.add{type="button", name="fp_button_mining_prod_override", 
          caption={"fp.override"}, style="fp_button_mini", mouse_button_filter={"left"}}
        button_override.style.left_margin = 8
    end
end


-- Handles the timescale changing process
function handle_subfactory_timescale_change(player, timescale)
    if ui_util.check_archive_status(player) then return end

    local subfactory = get_context(player).subfactory
    subfactory.timescale = timescale
    get_ui_state(player).current_activity = nil
    calculation.update(player, subfactory, true)
end

-- Activates the mining prod override mode for the current subfactory
function mining_prod_override(player)
    if ui_util.check_archive_status(player) then return end

    get_ui_state(player).current_activity = "overriding_mining_prod"
    refresh_main_dialog(player)
end

-- Persists changes to the overriden mining productivity
function handle_mining_prod_change(player, element)
    if ui_util.check_archive_status(player) then return end

    local subfactory = get_context(player).subfactory
    subfactory.mining_productivity = tonumber(element.text)
end

-- Handles confirmation of the mining prod textfield, possibly disabling the custom override
function handle_mining_prod_confirmation(player)
    local ui_state = get_ui_state(player)
    local subfactory = ui_state.context.subfactory

    if subfactory.mining_productivity == nil then ui_state.current_activity = nil end
    calculation.update(player, subfactory, true)
end