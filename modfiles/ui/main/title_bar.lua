-- ** LOCAL UTIL **
local function toggle_paused_state(player, _, _)
    if not game.is_multiplayer() then
        local preferences = util.globals.preferences(player)
        preferences.pause_on_interface = not preferences.pause_on_interface

        local main_elements = util.globals.main_elements(player)
        local button_pause = main_elements.title_bar.pause_button
        button_pause.toggled = (preferences.pause_on_interface)

        main_dialog.set_pause_state(player, main_elements.main_frame)
    end
end


local function refresh_title_bar(player)
    local ui_state = util.globals.ui_state(player)
    if ui_state.main_elements.main_frame == nil then return end

    local factory = util.context.get(player, "Factory")   --[[@as Factory?]]
    local title_bar_elements = ui_state.main_elements.title_bar

    title_bar_elements.compact_button.enabled = factory ~= nil and factory.valid and not ui_state.districts_view
    title_bar_elements.pause_button.enabled = (not game.is_multiplayer())
end


local function determine_handle_widths(player)
    local ui_state = util.globals.ui_state(player)
    local half_total_width = ui_state.main_dialog_dimensions.width / 2
    local shared_width = MAGIC_NUMBERS.titlebar_label_width / 2 + 12 + 2*8

    local left_width = half_total_width - MAGIC_NUMBERS.left_titlebar_width - shared_width
    local right_width = half_total_width - MAGIC_NUMBERS.right_titlebar_width - shared_width

    return {left=left_width, right=right_width}
end

local function add_handle(flow, width)
    local drag_handle = flow.add{type="empty-widget", style="flib_titlebar_drag_handle",
        ignored_by_interaction=true}
    drag_handle.style.width = width
end

local function build_title_bar(player)
    local main_elements = util.globals.main_elements(player)
    main_elements.title_bar = {}

    local parent_flow = main_elements.flows.top_horizontal
    local flow_title_bar = parent_flow.add{type="flow", direction="horizontal", style="frame_header_flow",
        tags={mod="fp", on_gui_click="re-center_main_dialog"}}
    flow_title_bar.drag_target = main_elements.main_frame

    local button_compact = flow_title_bar.add{type="sprite-button", style="fp_button_frame",
        tags={mod="fp", on_gui_click="switch_to_compact_view"}, tooltip={"fp.switch_to_compact_view"},
        sprite="fp_pin", mouse_button_filter={"left"}}
    main_elements.title_bar["compact_button"] = button_compact

    local handle_widths = determine_handle_widths(player)
    add_handle(flow_title_bar, handle_widths["left"])
    flow_title_bar.add{type="label", caption="Factory Planner", style="fp_label_frame_title",
        ignored_by_interaction=true}
    add_handle(flow_title_bar, handle_widths["right"])

    local flow_right = flow_title_bar.add{type="flow", direction="horizontal"}
    flow_right.style.horizontal_spacing = 8

    flow_right.add{type="button", caption={"fp.tutorial"}, style="fp_button_frame_tool",
        tags={mod="fp", on_gui_click="title_bar_open_dialog", type="tutorial"}, mouse_button_filter={"left"}}
    flow_right.add{type="button", caption={"fp.preferences"}, style="fp_button_frame_tool",
        tags={mod="fp", on_gui_click="title_bar_open_dialog", type="preferences"}, mouse_button_filter={"left"}}

    local separation = flow_right.add{type="line", direction="vertical"}
    separation.style.height = MAGIC_NUMBERS.title_bar_height - 4

    local button_pause = flow_right.add{type="button", caption={"fp.pause"}, tooltip={"fp.pause_on_interface"},
        tags={mod="fp", on_gui_click="toggle_pause_game"}, style="fp_button_frame_tool", mouse_button_filter={"left"}}
    main_elements.title_bar["pause_button"] = button_pause

    local preferences = util.globals.preferences(player)
    button_pause.toggled = (preferences.pause_on_interface)

    local button_close = flow_right.add{type="sprite-button", tags={mod="fp", on_gui_click="close_main_dialog"},
        sprite="utility/close", tooltip={"fp.close_interface"}, style="fp_button_frame",
        mouse_button_filter={"left"}}
    button_close.style.padding = 1

    refresh_title_bar(player)
end


-- ** EVENTS **
local listeners = {}

listeners.gui = {
    on_gui_click = {
        {
            name = "re-center_main_dialog",
            handler = (function(player, _, event)
                if event.button == defines.mouse_button_type.middle then
                    local ui_state = util.globals.ui_state(player)
                    local main_frame = ui_state.main_elements.main_frame
                    util.gui.properly_center_frame(player, main_frame, ui_state.main_dialog_dimensions)
                end
            end)
        },
        {
            name = "switch_to_compact_view",
            handler = (function(player, _, _)
                main_dialog.toggle(player)
                util.globals.ui_state(player).compact_view = true

                compact_dialog.toggle(player)
            end)
        },
        {
            name = "close_main_dialog",
            handler = (function(player, _, _)
                main_dialog.toggle(player)
            end)
        },
        {
            name = "toggle_pause_game",
            handler = toggle_paused_state
        },
        {
            name = "title_bar_open_dialog",
            handler = (function(player, tags, _)
                util.raise.open_dialog(player, {dialog=tags.type})
            end)
        }
    }
}

listeners.misc = {
    fp_toggle_pause = (function(player, _)
        if main_dialog.is_in_focus(player) then toggle_paused_state(player) end
    end),

    build_gui_element = (function(player, event)
        if event.trigger == "main_dialog" then
            build_title_bar(player)
        end
    end),
    refresh_gui_element = (function(player, event)
        local triggers = {title_bar=true, factory=true, all=true}
        if triggers[event.trigger] then refresh_title_bar(player) end
    end)
}

return { listeners }
