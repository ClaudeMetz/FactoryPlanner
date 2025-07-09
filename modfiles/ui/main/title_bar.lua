-- ** LOCAL UTIL **
local function toggle_paused_state(player, _, _)
    if not game.is_multiplayer() then
        local preferences = util.globals.preferences(player)
        preferences.pause_on_interface = not preferences.pause_on_interface

        local main_elements = util.globals.main_elements(player)
        main_dialog.set_pause_state(player, main_elements.main_frame)
    end
end


local function refresh_title_bar(player)
    local ui_state = util.globals.ui_state(player)
    if ui_state.main_elements.main_frame == nil then return end

    local factory = util.context.get(player, "Factory")   --[[@as Factory?]]
    local title_bar_elements = ui_state.main_elements.title_bar

    title_bar_elements.compact_button.enabled = factory ~= nil and factory.valid
    title_bar_elements.pause_button.enabled = (not game.is_multiplayer())
end


local function determine_left_handle_width(player)
    local ui_state = util.globals.ui_state(player)
    local half_total_width = ui_state.main_dialog_dimensions.width / 2

    local half_label_width = MAGIC_NUMBERS.titlebar_label_width / 2
    local left_margins = 3 * 8 + 2 * 4  -- horizontal spacing + drag handle margin
    local left_buttons_width = 3 * 24 + 2 * 8  -- button width + spacing

    return half_total_width - half_label_width - left_margins - left_buttons_width
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

    local preferences = util.globals.preferences(player)
    local button_pause = flow_title_bar.add{type="sprite-button", sprite="fp_play", tooltip={"fp.pause_on_interface"},
        tags={mod="fp", on_gui_click="toggle_pause_game"}, auto_toggle=true, style="fp_button_frame",
        toggled=(not preferences.pause_on_interface), mouse_button_filter={"left"}}
    button_pause.style.padding = -1
    main_elements.title_bar["pause_button"] = button_pause

    local button_calculator = flow_title_bar.add{type="sprite-button", sprite="fp_calculator",
        tooltip={"fp.open_calculator"}, style="fp_button_frame", mouse_button_filter={"left"},
        tags={mod="fp", on_gui_click="open_calculator_dialog"}}
    button_calculator.style.padding = -3

    local left_handle = flow_title_bar.add{type="empty-widget", style="flib_titlebar_drag_handle",
        ignored_by_interaction=true}
    left_handle.style.horizontally_stretchable = false  -- necessary so the other side stretches properly
    left_handle.style.width = determine_left_handle_width(player)
    flow_title_bar.add{type="label", caption="Factory Planner", style="fp_label_frame_title",
        ignored_by_interaction=true}
    flow_title_bar.add{type="empty-widget", style="flib_titlebar_drag_handle", ignored_by_interaction=true}

    flow_title_bar.add{type="button", caption={"fp.preferences"}, style="fp_button_frame_tool",
        tags={mod="fp", on_gui_click="title_bar_open_preferences"}, mouse_button_filter={"left"}}

    local separation = flow_title_bar.add{type="line", direction="vertical"}
    separation.style.height = MAGIC_NUMBERS.title_bar_height - 4

    local button_close = flow_title_bar.add{type="sprite-button", tags={mod="fp", on_gui_click="exit_main_dialog"},
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
                local floor = util.context.get(player, "Floor")
                if floor and floor.level > 1 and floor:count() == 1 then
                    util.context.ascend_floors(player, "up")
                end
                main_dialog.toggle_districts_view(player, true)

                main_dialog.toggle(player)
                util.globals.ui_state(player).compact_view = true

                compact_dialog.toggle(player)
            end)
        },
        {
            name = "exit_main_dialog",
            handler = (function(player, _, _)
                main_dialog.toggle(player)
            end)
        },
        {
            name = "toggle_pause_game",
            handler = toggle_paused_state
        },
        {
            name = "title_bar_open_preferences",
            handler = (function(player, _, _)
                util.raise.open_dialog(player, {dialog="preferences"})
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
