-- Creates the production pane that displays 
function add_production_pane_to(main_dialog, player)
    local flow = main_dialog.add{type="flow", name="flow_production_pane", direction="vertical"}
    flow.style.bottom_padding = 20
    local title = flow.add{type="label", name="label_production_pane_title", caption={"", "  ", {"label.production"}}}
    title.style.top_padding = 8
    title.style.font = "fp-font-18p"
    local info = flow.add{type="label", name="label_production_info", caption={"", " (",  {"label.production_info"}, ")"}}

    local scroll_pane = flow.add{type="scroll-pane", name="scroll-pane_production_pane", direction="vertical"}
    scroll_pane.style.horizontally_stretchable = true
    scroll_pane.style.vertically_stretchable = true

    local column_count = 6
    local table = scroll_pane.add{type="table", name="table_production_pane",  column_count=column_count}
    for i=1, column_count do table.style.column_alignments[i] = "right" end
    table.draw_horizontal_line_after_headers = true

    refresh_production_pane(player)
end

-- Refreshes the production pane by reloading the data
function refresh_production_pane(player)
    local flow_production = player.gui.center["fp_main_dialog"]["flow_production_pane"]
    -- Cuts function short if the production pane hasn't been initialized yet
    if not flow_production then return end

    local subfactory_id = global["selected_subfactory_id"]
    -- selected_subfactory_id is always 0 when there are no subfactories
    if (subfactory_id ~= 0) and Subfactory.is_valid(subfactory_id) then
        flow_production.style.visible = true

        local table_production = flow_production["scroll-pane_production_pane"]["table_production_pane"]
        table_production.clear()

        local floor_id = Subfactory.get_selected_floor_id(subfactory_id)
        if Floor.get_line_count(subfactory_id, floor_id) == 0 then
            flow_production["label_production_info"].style.visible = true
        else
            flow_production["label_production_info"].style.visible = false
            
            -- Table titles
            local title_strings = {"Product", "%", "Machine", "Energy", "Ingredients", "Byroducts"}
            for _, string in ipairs(title_strings) do
                local title = table_production.add{type="label", name="label_title_" .. string, caption=" " .. string .. "  "}
                title.style.font = "fp-font-16p"
            end

            -- Table rows
            for _, line_id in ipairs(Floor.get_lines_in_order(subfactory_id, floor_id)) do
                local line = Floor.get_line(subfactory_id, floor_id, line_id)
                create_line_table_row(player, line_id, line)
            end
        end
    else
        flow_production.style.visible = false
    end
end


function create_line_table_row(player, line_id, line)
    local table_production = player.gui.center["fp_main_dialog"]["flow_production_pane"]
      ["scroll-pane_production_pane"]["table_production_pane"]

    -- Product button
    local button_product = table_production.add{type="sprite-button", name="fp_sprite-button_product_" .. line_id,
      sprite=line.product_type .. "/" .. line.product_name, style="fp_button_icon_medium_green"}
    button_product.tooltip = game[line.product_type .. "_prototypes"][line.product_name].localised_name

end