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
    local subfactory_valid = (global.tutorial_subfactory ~= nil and global.tutorial_subfactory.valid)
    local button_tooltip = (not subfactory_valid) and {"fp.warning_message", {"fp.create_example_error"}} or nil
    flow_interactive.add{type="button", tags={mod="fp", on_gui_click="add_example_subfactory"},
        caption={"fp.create_example"}, tooltip=button_tooltip, enabled=subfactory_valid, mouse_button_filter={"left"}}

    flow_interactive.add{type="empty-widget", style="flib_horizontal_pusher"}

    local tutorial_mode = util.globals.preferences(player).tutorial_mode
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


local function open_tutorial_dialog(player, modal_data)
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
local listeners = {}

listeners.gui = {
    on_gui_click = {
        {
            name = "add_example_subfactory",
            timeout = 20,
            handler = (function(player, _, _)
                -- If this button can be pressed, the tutorial subfactory is valid implicitly
                local player_table = util.globals.player_table(player)
                local subfactory = Factory.add(player_table.factory, global.tutorial_subfactory)
                solver.update(player, subfactory)
                util.context.set_subfactory(player, subfactory)

                ui_util.raise_refresh(player, "all", nil)
                ui_util.raise_close_dialog(player, "cancel")
            end)
        }
    },
    on_gui_switch_state_changed = {
        {
            name = "toggle_tutorial_mode",
            handler = (function(player, _, event)
                local preferences = util.globals.preferences(player)
                preferences.tutorial_mode = ui_util.switch.convert_to_boolean(event.element.switch_state)
                ui_util.raise_refresh(player, "all", nil)
            end)
        }
    }
}

listeners.dialog = {
    dialog = "tutorial",
    metadata = (function(_) return {
        caption = {"fp.tutorial"},
        create_content_frame = false
    } end),
    open = open_tutorial_dialog
}

return { listeners }
