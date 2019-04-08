require("ui.elements.info_pane")

-- Creates the subfactory pane that includes the products, byproducts and ingredients
function add_subfactory_pane_to(main_dialog)
    local table = main_dialog.add{type="table", name="table_subfactory_pane", column_count=4, style="table"}
    table.draw_vertical_lines = true
    table.style.maximal_height = 153

    refresh_subfactory_pane(game.get_player(main_dialog.player_index))
end


-- Refreshes the subfactory pane by reloading the data
function refresh_subfactory_pane(player)
    local table_subfactory =  player.gui.center["fp_frame_main_dialog"]["table_subfactory_pane"]
    -- Cuts function short if the subfactory pane hasn't been initialized yet
    if not table_subfactory then return end

    table_subfactory.clear()
    
    local player_table = global.players[player.index]
    local subfactory = player_table.context.subfactory
    if subfactory ~= nil and subfactory.valid then
        -- Info cell
        add_subfactory_pane_cell_to(table_subfactory, "info")
        refresh_info_pane(player)
        
        -- The three item cells
        local classes = {"Ingredient", "Product", "Byproduct"}
        for _, class in pairs(classes) do
            local ui_name = class:gsub("^%u", string.lower) .. "s"
            local scroll_pane = add_subfactory_pane_cell_to(table_subfactory, ui_name)
            if scroll_pane["item_table"] == nil then init_item_table(scroll_pane, player_table.items_per_row) end
            refresh_item_table(player, class)
        end
    end
end


-- Constructs the basic structure of a subfactory_pane-cell
function add_subfactory_pane_cell_to(table, ui_name)
    local width = ((global.players[table.player_index].main_dialog_dimensions.width - 2*18) / 4)
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

    local subfactory = global.players[player.index].context.subfactory
    if subfactory[class].count > 0 then
        for _, item in ipairs(Subfactory.get_in_order(subfactory, class)) do
            local item_specifics = _G["get_" .. ui_name .. "_specifics"](item)

            local button = item_table.add{type="sprite-button", name="fp_sprite-button_subpane_" ..
              ui_name .. "_" .. item.id, sprite=item.type .. "/" .. item.name}

            button.number = item_specifics.number
            button.tooltip = item_specifics.tooltip
            button.style = item_specifics.style
        end
    end

    local append_function = _G["append_to_" .. ui_name .. "_table"]
    if append_function ~= nil then append_function(item_table) end
end


-- **** INGREDIENTS ****
-- Returns necessary details to complete the item button for an ingredient
function get_ingredient_specifics(ingredient)
    local localised_name = game[ingredient.type .. "_prototypes"][ingredient.name].localised_name
    -- Special handling for mining recipes
    if ingredient.type == "entity" then localised_name = {"", {"label.raw"}, " ", localised_name} end
    local tooltip = {"", localised_name, "\n", ui_util.format_number(ingredient.amount, 4)}

    return {
        number = ingredient.amount,
        tooltip = tooltip,
        style = "fp_button_icon_large_blank"
    }
end

-- Shifts clicked element's position left or right
function handle_ingredient_element_click(player, ingredient_id, click, direction)
    if direction ~= nil then
        local subfactory = global.players[player.index].context.subfactory
        local ingredient = Subfactory.get(subfactory, "Ingredient", ingredient_id)
        Subfactory.shift(subfactory, ingredient, direction)
        refresh_item_table(player, "Ingredient")
    end
end


-- **** PRODUCTS ****
-- Returns necessary details to complete the item button for a product
function get_product_specifics(product)
    local localised_name = game[product.type .. "_prototypes"][product.name].localised_name
    local tooltip = {"", localised_name, "\n", ui_util.format_number(product.amount, 4), " / ",
      ui_util.format_number(product.required_amount, 4)}

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

    return {
        number = product.required_amount,
        tooltip = tooltip,
        style = style
    }
end

-- Adds the button to add a product to the table
function append_to_product_table(table)
    local button = table.add{type="sprite-button", name="fp_sprite-button_add_product", sprite="fp_sprite_plus",
      style="fp_sprite_button", tooltip={"tooltip.add_product"}}
    button.style.height = 36
    button.style.width = 36
end

-- Opens modal dialogs of clicked element or shifts it's position left or right
function handle_product_element_click(player, product_id, click, direction)
    local player_table = global.players[player.index]
    local subfactory = player_table.context.subfactory
    local product = Subfactory.get(subfactory, "Product", product_id)

    -- Shift product in the given direction
    if direction ~= nil then
        Subfactory.shift(subfactory, product, direction)

    else  -- Open modal dialogs
        if click == "left" then
            if player_table.context.floor.level == 1 then
                enter_modal_dialog(player, {type="recipe_picker", object=product, preserve=true})
            else
                queue_hint_message(player, {"label.error_product_wrong_floor"})
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
    local localised_name = game[byproduct.type .. "_prototypes"][byproduct.name].localised_name
    local tooltip = {"", localised_name, "\n", ui_util.format_number(byproduct.amount, 4)}

    return {
        number = byproduct.amount,
        tooltip = tooltip,
        style = "fp_button_icon_large_red"
    }
end


-- Opens recipe dialog of clicked element or shifts it's position left or right
function handle_byproduct_element_click(player, byproduct_id, click, direction)
    local subfactory = global.players[player.index].context.subfactory
    local byproduct = Subfactory.get(subfactory, "Byproduct", byproduct_id)
    
    -- Shift byproduct in the given direction
    if direction ~= nil then
        Subfactory.shift(subfactory, byproduct, direction)

    -- Open recipe dialog? Dealing with byproducts will come at a later stage
    elseif click == "left" then
        local floor = global.players[player.index].context.floor
        if floor.level == 1 then
            enter_modal_dialog(player, {type="recipe_picker", object=byproduct, preserve=true})
        else
            queue_hint_message(player, {"label.error_byproduct_wrong_floor"})
        end
    end

    refresh_item_table(player, "Byproduct")
end