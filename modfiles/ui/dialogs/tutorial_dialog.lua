local function open_tutorial_dialog(player, modal_data)
    local function add_base_frame(name)
        local frame = modal_data.modal_elements.content_frame.add{type="frame",
            style="bordered_frame", direction="vertical"}
        frame.style.width = 550

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

    -- Run solver to see if any lines don't do anything, indicating an unuseful example
    local tutorial_factory = global.tutorial_factory
    if tutorial_factory then
        tutorial_factory.parent = {location_proto={pollutant_type=nil}}  -- hack to get it working temporarily
        solver.update(player, tutorial_factory)
        for line in tutorial_factory.top_floor:iterator() do
            if line.production_ratio == 0 then
                tutorial_factory = nil
                break
            end
        end
    end

    local button_tooltip = (tutorial_factory == nil) and {"fp.warning_message", {"fp.create_example_error"}} or nil
    flow_interactive.add{type="button", tags={mod="fp", on_gui_click="add_example_factory"}, tooltip=button_tooltip,
        caption={"fp.create_example"}, enabled=(tutorial_factory ~= nil), mouse_button_filter={"left"}}

    flow_interactive.add{type="empty-widget", style="flib_horizontal_pusher"}

    local tutorial_mode = util.globals.preferences(player).tutorial_mode
    util.gui.switch.add_on_off(flow_interactive, "toggle_tutorial_mode", {}, tutorial_mode,
        {"fp.tutorial_mode"}, nil, true)

    flow_interactive.add{type="empty-widget", style="flib_horizontal_pusher"}

    -- Interface tutorial
    local frame_interface = add_base_frame("interface")
    local label_controls = frame_interface.add{type="label", caption={"fp.interface_controls"}}
    label_controls.style.single_line = false
    label_controls.style.margin = {6, 0, 0, 6}
end


-- ** EVENTS **
local listeners = {}

listeners.gui = {
    on_gui_click = {
        {
            name = "add_example_factory",
            timeout = 20,
            handler = (function(player, _, _)
                -- If this button can be pressed, the tutorial factory is valid implicitly
                local clone = global.tutorial_factory:clone()
                util.context.get(player, "District"):insert(clone)
                solver.update(player, clone)

                util.context.set(player, clone)
                view_state.rebuild_state(player)

                util.raise.refresh(player, "all")
                util.raise.close_dialog(player, "cancel")
            end)
        }
    },
    on_gui_switch_state_changed = {
        {
            name = "toggle_tutorial_mode",
            handler = (function(player, _, event)
                local preferences = util.globals.preferences(player)
                preferences.tutorial_mode = util.gui.switch.convert_to_boolean(event.element.switch_state)
                util.raise.refresh(player, "all")
            end)
        }
    }
}

listeners.dialog = {
    dialog = "tutorial",
    metadata = (function(_) return {
        caption = {"fp.tutorial"},
        create_content_frame = true
    } end),
    open = open_tutorial_dialog
}

return { listeners }
