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
    local ui_name = class:gsub("^%u", string.lower)
    local item_table = player.gui.center["fp_frame_main_dialog"]["table_subfactory_pane"]["flow_" .. ui_name .. "s"]
      ["scroll-pane"]["item_table"]
    item_table.clear()

    local subfactory = get_context(player).subfactory
    if subfactory[class].count > 0 then
        for _, item in ipairs(Subfactory.get_in_order(subfactory, class)) do
            local item_specifics = _G["get_" .. ui_name .. "_specifics"](item)
            
            if item_specifics.number == 0 or item_specifics.number > margin_of_error then
                local button = item_table.add{type="sprite-button", name="fp_sprite-button_subpane_" .. ui_name .. "_" 
                .. item.id, sprite=item.type .. "/" .. item.name, mouse_button_filter={"left-and-right"}}

                button.number = item_specifics.number
                button.tooltip = item_specifics.tooltip
                button.style = item_specifics.style
            end
        end
    end

    local append_function = _G["append_to_" .. ui_name .. "_table"]
    if append_function ~= nil then append_function(item_table) end
end


-- **** INGREDIENTS ****
-- Returns necessary details to complete the item button for an ingredient
function get_ingredient_specifics(ingredient)
    return {
        number = ingredient.amount,
        tooltip = generate_item_tooltip(ingredient),
        style = "fp_button_icon_large_blank"
    }
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


-- **** PRODUCTS ****
-- Returns necessary details to complete the item button for a product
function get_product_specifics(product)
    local style
    if product.amount == 0 then
        style = "fp_button_icon_large_red"
    elseif product.amount < product.required_amount then
        style = "fp_button_icon_large_yellow"
    elseif product.amount == product.required_amount then
        style = "fp_button_icon_large_green"
    else
        style = "fp_button_icon_large_cyan"
    end

    local number = (product.required_amount < margin_of_error) and 0 or product.required_amount
    return {
        number = number,
        tooltip = generate_item_tooltip(product),
        style = style
    }
end

-- Adds the button to add a product to the table
function append_to_product_table(table)
    local button = table.add{type="sprite-button", name="fp_sprite-button_add_product", sprite="fp_sprite_plus",
      style="fp_sprite_button", tooltip={"tooltip.add_product"}, mouse_button_filter={"left"}}
    button.style.height = 36
    button.style.width = 36
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


-- **** BYPRODUCTS ****
-- Returns necessary details to complete the item button for a byproduct
function get_byproduct_specifics(byproduct)
    return {
        number = byproduct.amount,
        tooltip = generate_item_tooltip(byproduct),
        style = "fp_button_icon_large_red"
    }
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


-- Generates an appropriate tooltip for the given item
function generate_item_tooltip(item)
    local localised_name
    -- Special handling for mining recipes
    if item.type == "entity" then
        -- 'item'-type only works here because the only entity items are ores currently
        localised_name = global.all_items["item"][item.name].localised_name
        localised_name = {"", {"label.raw"}, " ", localised_name}
    else
        localised_name = global.all_items[item.type][item.name].localised_name
    end
    return {"", localised_name, "\n", ui_util.format_number(item.amount, 4)}
end