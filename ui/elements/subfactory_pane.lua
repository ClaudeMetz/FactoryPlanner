require("ui.elements.subfactory_panes.info_pane")
require("ui.elements.subfactory_panes.ingredient_pane")
require("ui.elements.subfactory_panes.product_pane")
require("ui.elements.subfactory_panes.byproduct_pane")

-- Creates the subfactory pane that includes the products, byproducts and ingredients
function add_subfactory_pane_to(main_dialog, player)
    local table = main_dialog.add{type="table", name="table_subfactory_pane", column_count = 4}
    table.style.horizontally_stretchable = true
    table.draw_vertical_lines = true

    refresh_subfactory_pane(player)
end


-- Refreshes the subfactory pane by reloading the data
function refresh_subfactory_pane(player)
    local table_subfactory =  player.gui.center["fp_main_dialog"]["table_subfactory_pane"]
    -- Cuts function short if the subfactory pane hasn't been initialized yet
    if not table_subfactory then return end

    table_subfactory.clear()
    
    local subfactory_id = global["selected_subfactory_id"]
    -- selected_subfactory_id is always 0 when there are no subfactories
    if (subfactory_id ~= 0) and Subfactory.is_valid(subfactory_id) then
        -- Info cell
        add_subfactory_pane_cell_to(table_subfactory, "info")
        refresh_info_pane(player)
        
        -- All 3 item cells
        local classes = {[1] = "Ingredient", [2] = "Product", [3] = "Byproduct"}
        for _, class in ipairs(classes) do
            local ui_name = class:gsub("^%u", string.lower) .. "s"
            add_subfactory_pane_cell_to(table_subfactory, ui_name)
            refresh_item_table(player, class)
        end
    end
end


-- Constructs the basic structure of a subfactory_pane-cell
function add_subfactory_pane_cell_to(table, ui_name)
    local width = global["main_dialog_dimensions"].width / 4 - 6
    local flow = table.add{type="flow", name="flow_" .. ui_name, direction="vertical"}
    flow.style.width = width
    local label_title = flow.add{type="label", name="label_" .. ui_name .. "_title", caption={"", "  ", {"label." .. ui_name}}}
    label_title.style.font = "fp-button-standard"
end

-- Refreshes the given kind of item table
function refresh_item_table(player, class)
    local ui_name = class:gsub("^%u", string.lower) .. "s"
    local flow = player.gui.center["fp_main_dialog"]["table_subfactory_pane"]["flow_" .. ui_name]
    if flow["table_" .. ui_name] == nil then
        flow.add{type="table", name="table_" .. ui_name, column_count = 6}
        flow["table_" .. ui_name].style.left_padding = 10
        flow["table_" .. ui_name].style.horizontal_spacing = 10
    else
        flow["table_" .. ui_name].clear()
    end

    local subfactory_id = global["selected_subfactory_id"]
    if Subfactory.get_count(subfactory_id, class) ~= 0 then
        for _, id in ipairs(Subfactory.get_in_order(subfactory_id, class)) do
            local item = Subfactory.get(subfactory_id, class, id)
            local item_specifics = _G["get_" .. ui_name:sub(1, -2) .. "_specifics"](item)

            local button = flow["table_" .. ui_name].add{type="sprite-button", name="fp_sprite-button_" ..
              ui_name:sub(1, -2) .. "_" .. id, sprite=item.item_type .. "/" .. item.name}

            button.number = item_specifics.number
            button.tooltip = item_specifics.tooltip
            button.style = item_specifics.style
        end
    end

    local append_function = _G["append_to_" .. ui_name:sub(1, -2) .. "_table"]
    if append_function ~= nil then append_function(flow["table_" .. ui_name]) end
end