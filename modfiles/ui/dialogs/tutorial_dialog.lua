tutorial_dialog = {}

-- ** LOCAL UTIL **
local tab_definitions = {"interface", "usage", "matrix_solver"}

function tab_definitions.interface(player, tab, tab_pane)
    tab.caption = {"fp.interface"}

    local function add_base_frame(name)
        local frame = tab_pane.add{type="frame", style="fp_frame_bordered_stretch", direction="vertical"}
        frame.style.horizontally_stretchable = true

        frame.add{type="label", caption={"fp." .. name .. "_tutorial_title"}, style="caption_label"}
        local label_text = frame.add{type="label", caption={"fp." .. name .. "_tutorial_text"}}
        label_text.style.single_line = false

        return frame
    end

    -- Interactive tutorial
    local frame_interactive = add_base_frame("interactive")
    local flow_interactive = frame_interactive.add{type="flow", direction="horizontal"}
    flow_interactive.style.margin = {12, 20, 8, 20}

    flow_interactive.add{type="empty-widget", style="flib_horizontal_pusher"}

    -- If the tutorial subfactory is valid, it can be imported regardless of the current modset
    local subfactory_compatible = global.tutorial_subfactory_validity
    local button_tooltip = (not subfactory_compatible) and {"fp.warning_message", {"fp.create_example_error"}} or nil
    flow_interactive.add{type="button", tags={mod="fp", on_gui_click="add_example_subfactory"},
        caption={"fp.create_example"}, tooltip=button_tooltip, enabled=subfactory_compatible, mouse_button_filter={"left"}}

    flow_interactive.add{type="empty-widget", style="flib_horizontal_pusher"}

    local tutorial_mode = data_util.get("preferences", player).tutorial_mode
    ui_util.switch.add_on_off(flow_interactive, "toggle_tutorial_mode", {}, tutorial_mode,
        {"fp.tutorial_mode"}, nil, true)

    flow_interactive.add{type="empty-widget", style="flib_horizontal_pusher"}

    -- Interface tutorial
    local frame_interface = add_base_frame("interface")
    local recipebook_string = (RECIPEBOOK_ACTIVE) and {"fp.interface_controls_recipebook"} or ""
    local label_controls = frame_interface.add{type="label", caption={"", {"fp.interface_controls"}, recipebook_string}}
    label_controls.style.single_line = false
    label_controls.style.margin = {6, 0, 0, 6}
end

function tab_definitions.usage(_, tab, tab_pane)
    tab.caption = {"fp.usage"}

    local bordered_frame = tab_pane.add{type="frame", style="fp_frame_bordered_stretch"}
    local label_text = bordered_frame.add{type="label", caption={"fp.tutorial_usage_text"}}
    label_text.style.single_line = false
    label_text.style.padding = 2
end

function tab_definitions.matrix_solver(_, tab, tab_pane)
    tab.caption = {"fp.matrix_solver"}

    local bordered_frame = tab_pane.add{type="frame", style="fp_frame_bordered_stretch"}
    local label_text = bordered_frame.add{type="label", caption={"fp.tutorial_matrix_solver_text"}}
    label_text.style.single_line = false
    label_text.style.padding = 2
end


-- ** TOP LEVEL **
tutorial_dialog.dialog_settings = (function(_) return {
    caption = {"fp.tutorial"},
    create_content_frame = false
} end)

function tutorial_dialog.open(player, modal_data)
    local frame_tabs = modal_data.modal_elements.dialog_flow.add{type="frame", style="inside_deep_frame_for_tabs"}

    local tabbed_pane = frame_tabs.add{type="tabbed-pane", style="tabbed_pane_with_no_side_padding"}
    tabbed_pane.style.height = 600

    for _, tab_name in ipairs(tab_definitions) do
        local tab = tabbed_pane.add{type="tab"}
        local tab_pane = tabbed_pane.add{type="scroll-pane", style="flib_naked_scroll_pane_under_tabs"}
        tab_pane.style.width = 555

        tab_definitions[tab_name](player, tab, tab_pane)
        tabbed_pane.add_tab(tab, tab_pane)
    end
end


-- ** EVENTS **
tutorial_dialog.gui_events = {
    on_gui_click = {
        {
            name = "add_example_subfactory",
            timeout = 20,
            handler = (function(player, _, _)
                -- If this button can be pressed, the tutorial subfactory is valid implicitly
                data_util.add_subfactories_by_string(player, TUTORIAL_EXPORT_STRING)
                main_dialog.refresh(player, "all")
                modal_dialog.exit(player, "cancel")
            end)
        }
    },
    on_gui_switch_state_changed = {
        {
            name = "toggle_tutorial_mode",
            handler = (function(player, _, event)
                local preferences = data_util.get("preferences", player)
                preferences.tutorial_mode = ui_util.switch.convert_to_boolean(event.element.switch_state)
                main_dialog.refresh(player, "all")
            end)
        }
    }
}
