-- Creates the error bar
function add_error_bar_to(main_dialog, player)
    local error_bar = main_dialog.add{type="flow", name="flow_error_bar", direction="vertical"}
    
    refresh_error_bar(player)
end

-- Refreshes the error_bar
function refresh_error_bar(player)
    local flow_error_bar = player.gui.center["fp_main_dialog"]["flow_error_bar"]
    -- Cuts function short if the error bar hasn't been initialized yet
    if not flow_error_bar then return end

    flow_error_bar.clear()

    local subfactory_id = global["selected_subfactory_id"]
    -- selected_subfactory_id is always 0 when there are no subfactories
    if (subfactory_id ~= 0) and (not is_subfactory_valid(subfactory_id)) then
        create_error_bar(flow_error_bar, subfactory_id)
        flow_error_bar.style.visible = true
    else
        flow_error_bar.style.visible = false
    end
end

-- Constructs the error bar
function create_error_bar(flow, subfactory_id)
    local label_1 = flow.add{type="label", name="label_error_bar_1", caption={"", "   ", {"label.error_bar_1"}}}
    label_1.style.font = "fp-button-standard"
    local table = flow.add{type="table", name="table_error_bar", column_count=2}
    local label_2 = table.add{type="label", name="label_error_bar_2", caption={"", "   ", {"label.error_bar_2"}}}
    label_2.style.font = "fp-button-standard"
    local button = table.add{type="button", name="fp_button_error_bar_" .. subfactory_id, caption={"button-text.error_bar_delete"}}
    button.style.font = "fp-button-standard"    
end