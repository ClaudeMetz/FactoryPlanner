require("ui.elements.info_pane")
require("ui.elements.ingredient_pane")
require("ui.elements.product_pane")
require("ui.elements.byproduct_pane")

-- Creates the subfactory pane that includes the products, byproducts and ingredients
function add_subfactory_pane_to(main_dialog)
    local table = main_dialog.add{type="table", name="table_subfactory_pane", column_count = 4}
    table.style.horizontally_stretchable = true
    table.draw_vertical_lines = true

    refresh_subfactory_pane(game.players[main_dialog.player_index])
end


-- Refreshes the subfactory pane by reloading the data
function refresh_subfactory_pane(player)
    local table_subfactory =  player.gui.center["fp_main_dialog"]["table_subfactory_pane"]
    -- Cuts function short if the subfactory pane hasn't been initialized yet
    if not table_subfactory then return end

    table_subfactory.clear()
    
    local subfactory_id = global.players[player.index].selected_subfactory_id
    -- selected_subfactory_id is always 0 when there are no subfactories
    if (subfactory_id ~= 0) and Subfactory.is_valid(player, subfactory_id) then
        -- Info cell
        add_subfactory_pane_cell_to(table_subfactory, "info")
        refresh_info_pane(player)
        
        -- All 3 item cells
        local column_count = settings.get_player_settings(player)["fp_subfactory_items_per_row"].value
        local classes = {[1] = "Ingredient", [2] = "Product", [3] = "Byproduct"}
        for _, class in ipairs(classes) do
            local ui_name = class:gsub("^%u", string.lower) .. "s"
            local scroll_pane = add_subfactory_pane_cell_to(table_subfactory, ui_name)
            if scroll_pane["item_table"] == nil then init_item_table(scroll_pane, column_count) end
            refresh_item_table(player, class)
        end
    end
end


-- Constructs the basic structure of a subfactory_pane-cell
function add_subfactory_pane_cell_to(table, ui_name)
    local width = (global.players[table.player_index].main_dialog_dimensions.width / 4) + 2
    local flow = table.add{type="flow", name="flow_" .. ui_name, direction="vertical"}
    flow.style.width = width
    local label_title = flow.add{type="label", name="label_" .. ui_name .. "_title", caption={"", "  ", {"label." .. ui_name}}}
    label_title.style.font = "fp-font-16p"
    local scroll_pane = flow.add{type="scroll-pane", name="scroll-pane", direction="vertical"}
    scroll_pane.style.maximal_height = 116
    scroll_pane.style.right_padding = 8

    return scroll_pane
end

-- Initializes the item table of the given scroll_pane
function init_item_table(scroll_pane, column_count)
    local item_table = scroll_pane.add{type="table", name="item_table", column_count = column_count}
    item_table.style.left_padding = 10
    item_table.style.horizontal_spacing = 10
end

-- Refreshes the given kind of item table
function refresh_item_table(player, class)
    local ui_name = class:gsub("^%u", string.lower)
    local item_table = player.gui.center["fp_main_dialog"]["table_subfactory_pane"]["flow_" .. ui_name .. "s"]
      ["scroll-pane"]["item_table"]
    item_table.clear()

    local subfactory_id = global.players[player.index].selected_subfactory_id
    if Subfactory.get_count(player, subfactory_id, class) ~= 0 then
        for _, id in ipairs(Subfactory.get_in_order(player, subfactory_id, class)) do
            local item = Subfactory.get(player, subfactory_id, class, id)
            local item_specifics = _G["get_" .. ui_name .. "_specifics"](item)

            local button = item_table.add{type="sprite-button", name="fp_sprite-button_subpane_" ..
              ui_name .. "_" .. id, sprite=item.item_type .. "/" .. item.name}

            button.number = item_specifics.number
            button.tooltip = item_specifics.tooltip
            button.style = item_specifics.style
        end
    end

    local append_function = _G["append_to_" .. ui_name .. "_table"]
    if append_function ~= nil then append_function(item_table) end
end