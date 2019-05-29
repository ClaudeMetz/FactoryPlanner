-- Handles populating the preferences dialog
function open_preferences_dialog(flow_modal_dialog)
    flow_modal_dialog.parent.caption = {"label.preferences"}

    -- Label
    local label_preferences_info = flow_modal_dialog.add{type="label", name="label_preferences_info", 
      caption={"label.preferences_info"}}
    label_preferences_info.style.single_line = false
    label_preferences_info.style.bottom_margin = 4

    -- Machine preferences
    local label_machine_info = flow_modal_dialog.add{type="label", name="label_machines_info", 
      caption={"label.preferences_title_machines"}}
    label_machine_info.style.font = "fp-font-bold-15p"
    label_machine_info.tooltip = {"label.preferences_title_machines_tooltip"}
    local scroll_pane_all_machines = flow_modal_dialog.add{type="scroll-pane", name="scroll-pane_all_machines", 
      direction="vertical"}
    scroll_pane_all_machines.style.maximal_height = 650
    scroll_pane_all_machines.style.horizontally_stretchable = true
    scroll_pane_all_machines.horizontal_scroll_policy = "never"
    local table_all_machines = scroll_pane_all_machines.add{type="table", name="table_all_machines", column_count=2}
    table_all_machines.style.top_margin = 4
    table_all_machines.style.left_padding = 6
    table_all_machines.style.bottom_padding = 4

    refresh_preferences_dialog(flow_modal_dialog.gui.player)
end


-- Creates the modal dialog to change your preferences
function refresh_preferences_dialog(player)
    -- Machine preferences
    local table_all_machines = player.gui.center["fp_frame_modal_dialog"]["flow_modal_dialog"]
      ["scroll-pane_all_machines"]["table_all_machines"]
    table_all_machines.clear()

    for category, data in pairs(global.all_machines) do
        if #data.order > 1 then
            table_all_machines.add{type="label", name="label_" .. category, caption="'" .. category .. "':    "}
            local table_machines = table_all_machines.add{type="table", name="table_machines:" .. category,
              column_count=12}
            for _, machine_name in ipairs(data.order) do
                local button_machine = table_machines.add{type="sprite-button", name="fp_sprite-button_preferences_machine_"
                  .. category .. "_" .. machine_name, sprite="entity/" .. machine_name, mouse_button_filter={"left"}}
                local tooltip = data.machines[machine_name].localised_name

                local default_machine_name = data_util.machines.get_default(player, category).name
                if default_machine_name == machine_name then
                    button_machine.style = "fp_button_icon_medium_green"
                    tooltip = {"", tooltip, "\n", {"tooltip.selected"}}
                else 
                    button_machine.style = "fp_button_icon_medium_hidden"
                end
                button_machine.tooltip = tooltip
            end
        end
    end
end


-- Changes the default machine of the given category
function handle_preferences_machine_change(player, category, name)
    data_util.machines.set_default(player, category, name)
    refresh_preferences_dialog(player)
end