-- Creates the production pane that displays 
function add_production_pane_to(main_dialog, player)
    local flow = main_dialog.add{type="flow", name="flow_production_pane", direction="vertical"}
    flow.style.bottom_padding = 20
    local title = flow.add{type="label", name="label_production_pane_title", caption={"", "  ", {"label.production"}}}
    title.style.top_padding = 8
    title.style.font = "fp-button-standard"

    local table = flow.add{type="table", name="table_production_pane", column_count = 10}

    refresh_production_pane(player)
end

-- Refreshes the production pane by reloading the data
function refresh_production_pane(player)
    local flow_production = player.gui.center["fp_main_dialog"]["flow_production_pane"]
    -- Cuts function short if the production pane hasn't been initialized yet
    if not flow_production then return end

    local table_production = flow_production["table_production_pane"]
    table_production.clear()
    -- selected_subfactory_id is always 0 when there are no subfactories
    local subfactory_id = global["selected_subfactory_id"]
    if (subfactory_id ~= 0) and Subfactory.is_valid(subfactory_id) then
        flow_production.style.visible = true

        -- Temporary implementation for this
        if not flow_production["label_production_info"] then
            flow_production.add{type="label", name="label_production_info", caption=" (Add a product and left-click it to add a recipe.)"}
        end
        table_production.style.visible = false

        -- create table
    else
        flow_production.style.visible = false
    end
end