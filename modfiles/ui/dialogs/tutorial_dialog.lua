tutorial_dialog = {}

-- ** LOCAL UTIL **
local tab_definitions = {"interface", "usage", "pro_tips"}

function tab_definitions.interface(player, tab, tab_pane)
    tab.caption = {"fp.interface"}

    local function add_base_frame(name)
        local frame = tab_pane.add{type="frame", style="bordered_frame", direction="vertical"}
        frame.style.horizontally_stretchable = true

        frame.add{type="label", caption={"fp." .. name .. "_tutorial_title"}, style="caption_label"}
        local text = frame.add{type="label", caption={"fp." .. name .. "_tutorial_text"}}
        text.style.single_line = false

        return frame
    end

    -- Interactive tutorial
    local frame_interactive = add_base_frame("interactive")
    local flow_interactive = frame_interactive.add{type="flow", direction="horizontal"}
    flow_interactive.style.margin = {12, 20, 8, 20}

    local active_mods = game.active_mods
    local no_other_mods_active = (table_size(active_mods) == 3 and active_mods["base"] ~= nil
      and active_mods["factoryplanner"] ~= nil and active_mods["flib"] ~= nil)
    local tutorial_mode = data_util.get("preferences", player).tutorial_mode

    flow_interactive.add{type="empty-widget", style="flib_horizontal_pusher"}
    local button_tooltip = (not no_other_mods_active) and {"fp.warning_message", {"fp.create_example_error"}} or nil
    flow_interactive.add{type="button", name="fp_button_tutorial_add_example", caption={"fp.create_example"},
      tooltip=button_tooltip, enabled=no_other_mods_active, mouse_button_filter={"left"}}
    flow_interactive.add{type="empty-widget", style="flib_horizontal_pusher"}
    ui_util.switch.add_on_off(flow_interactive, "tutorial_mode", tutorial_mode, {"fp.tutorial_mode"}, nil, true)
    flow_interactive.add{type="empty-widget", style="flib_horizontal_pusher"}

    -- Interface tutorial
    local frame_interface = add_base_frame("interface")
    local alt_action_string = {"fp.alt_action_" .. data_util.get("settings", player).alt_action}
    local label_controls = frame_interface.add{type="label", caption={"fp.interface_controls", alt_action_string}}
    label_controls.style.single_line = false
    label_controls.style.margin = {6, 0, 0, 6}
end

function tab_definitions.usage(_, tab, tab_pane)
    tab.caption = {"fp.usage"}

    local bordered_frame = tab_pane.add{type="frame", style="bordered_frame"}
    local label_usage = bordered_frame.add{type="label", caption={"fp.tutorial_usage_text"}}
    label_usage.style.single_line = false
    label_usage.style.padding = 2
end

function tab_definitions.pro_tips(_, tab, tab_pane)
    tab.caption = {"fp.pro_tips"}

    local protip_names = {"shortcuts", "line_fuel", "list_ordering", "hovering", "interface_size", "settings",
      "recursive_subfloors", "views", "priority_product", "preferences", "up_down_grading", "archive", "machine_limits"}
    for _, name in ipairs(protip_names) do
        local bordered_frame = tab_pane.add{type="frame", style="bordered_frame"}
        local label = bordered_frame.add{type="label", caption={"fp.pro_" .. name}}
        label.style.single_line = false
    end
end


-- ** TOP LEVEL **
tutorial_dialog.dialog_settings = (function(_) return {
    caption = {"fp.tutorial"},
    disable_scroll_pane = true
} end)

tutorial_dialog.events = {
    on_gui_click = {
        {
            name = "fp_button_tutorial_add_example",
            handler = (function(player, _, _)
                data_util.add_subfactories_by_string(player, TUTORIAL_EXPORT_STRING, true)
                modal_dialog.exit(player, "cancel", {})
            end)
        }
    },
    on_gui_switch_state_changed = {
        {
            name = "fp_switch_tutorial_mode",
            handler = (function(player, element)
                local new_state = ui_util.switch.convert_to_boolean(element.switch_state)
                data_util.get("preferences", player).tutorial_mode = new_state
                main_dialog.refresh(player)
            end)
        }
    }
}

function tutorial_dialog.open(player, _, modal_data)
    local frame_tabs = modal_data.ui_elements.flow_modal_dialog.add{type="frame", style="inside_deep_frame_for_tabs"}

    local tabbed_pane = frame_tabs.add{type="tabbed-pane", style="tabbed_pane_with_no_side_padding"}
    local main_dialog_dimensions = data_util.get("ui_state", player).main_dialog_dimensions
    tabbed_pane.style.height = main_dialog_dimensions.height * 0.7

    for _, tab_name in ipairs(tab_definitions) do
        local tab = tabbed_pane.add{type="tab"}
        local tab_pane = tabbed_pane.add{type="scroll-pane", style="fp_scroll_pane_inside_tab"}
        tab_pane.style.width = 550

        tab_definitions[tab_name](player, tab, tab_pane)
        tabbed_pane.add_tab(tab, tab_pane)
    end
end