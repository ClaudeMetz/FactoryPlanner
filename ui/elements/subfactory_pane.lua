require("ui.elements.subfactory_panes.info_pane")
require("ui.elements.subfactory_panes.product_pane")

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
    
    -- selected_subfactory_id is always 0 when there are no subfactories
    if (global["selected_subfactory_id"] ~= 0) and global["factory"]:get_selected_subfactory():is_valid() then
        -- Info cell
        create_subfactory_pane_cell(table_subfactory, "info")
        refresh_info_pane(player)
        
        -- Ingredients cell
        create_subfactory_pane_cell(table_subfactory, "ingredients")

        -- Products cell
        create_subfactory_pane_cell(table_subfactory, "products")
        refresh_product_pane(player)

        -- Byproducts cell
        create_subfactory_pane_cell(table_subfactory, "byproducts")
    end
end

-- Constructs the basic structure of a subfactory_pane-cell
function create_subfactory_pane_cell(table, kind)
    local width = global["main_dialog_dimensions"].width / 4 - 6
    local flow = table.add{type="flow", name="flow_" .. kind, direction="vertical"}
    flow.style.width = width
    local label_title = flow.add{type="label", name="label_" .. kind .. "_title", caption={"", "  ", {"label." ..kind}}}
    label_title.style.font = "fp-button-standard"
end