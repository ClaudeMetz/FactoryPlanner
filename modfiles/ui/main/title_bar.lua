-- ** LOCAL UTIL **
local function configure_pause_button_style(button, pause_on_interface)
    button.style = (pause_on_interface) and "fp_button_frame_tool_active" or "fp_button_frame_tool"
end

local function toggle_paused_state(player, _, _)
    if not game.is_multiplayer() then
        local preferences = data_util.preferences(player)
        preferences.pause_on_interface = not preferences.pause_on_interface

        local main_elements = data_util.main_elements(player)
        local button_pause = main_elements.title_bar.pause_button
        configure_pause_button_style(button_pause, preferences.pause_on_interface)

        main_dialog.set_pause_state(player, main_elements.main_frame)
    end
end


local function refresh_title_bar(player)
    local ui_state = data_util.ui_state(player)
    if ui_state.main_elements.main_frame == nil then return end

    local subfactory = ui_state.context.subfactory
    local title_bar_elements = ui_state.main_elements.title_bar
    -- Disallow switching to compact view if the selected subfactory is nil or invalid
    title_bar_elements.switch_button.enabled = subfactory and subfactory.valid
end

local function build_title_bar(player)
    local main_elements = data_util.main_elements(player)
    main_elements.title_bar = {}

    local parent_flow = main_elements.flows.top_horizontal
    local flow_title_bar = parent_flow.add{type="flow", direction="horizontal",
        tags={mod="fp", on_gui_click="re-center_main_dialog"}}
    flow_title_bar.style.horizontal_spacing = 8
    flow_title_bar.drag_target = main_elements.main_frame
    -- The separator line causes the height to increase for some inexplicable reason, so we must hardcode it here
    flow_title_bar.style.height = MAGIC_NUMBERS.title_bar_height

    local button_switch = flow_title_bar.add{type="sprite-button", style="frame_action_button",
        tags={mod="fp", on_gui_click="switch_to_compact_view"}, tooltip={"fp.switch_to_compact_view"},
        sprite="fp_sprite_arrow_left_light", hovered_sprite="fp_sprite_arrow_left_dark",
        clicked_sprite="fp_sprite_arrow_left_dark", mouse_button_filter={"left"}}
    button_switch.style.padding = 2
    main_elements.title_bar["switch_button"] = button_switch

    flow_title_bar.add{type="label", caption={"mod-name.factoryplanner"}, style="frame_title",
        ignored_by_interaction=true}

    local drag_handle = flow_title_bar.add{type="empty-widget", style="flib_titlebar_drag_handle",
        ignored_by_interaction=true}
    drag_handle.style.minimal_width = 80

    flow_title_bar.add{type="button", caption={"fp.tutorial"}, style="fp_button_frame_tool",
        tags={mod="fp", on_gui_click="title_bar_open_dialog", type="tutorial"}, mouse_button_filter={"left"}}
    flow_title_bar.add{type="button", caption={"fp.preferences"}, style="fp_button_frame_tool",
        tags={mod="fp", on_gui_click="title_bar_open_dialog", type="preferences"}, mouse_button_filter={"left"}}

    local separation = flow_title_bar.add{type="line", direction="vertical"}
    separation.style.height = 24

    local button_pause = flow_title_bar.add{type="button", caption={"fp.pause"}, tooltip={"fp.pause_on_interface"},
        tags={mod="fp", on_gui_click="toggle_pause_game"}, enabled=(not game.is_multiplayer()),
        style="fp_button_frame_tool", mouse_button_filter={"left"}}
    main_elements.title_bar["pause_button"] = button_pause

    local preferences = data_util.preferences(player)
    configure_pause_button_style(button_pause, preferences.pause_on_interface)

    local button_close = flow_title_bar.add{type="sprite-button", tags={mod="fp", on_gui_click="close_main_dialog"},
        sprite="utility/close_white", hovered_sprite="utility/close_black", clicked_sprite="utility/close_black",
        tooltip={"fp.close_interface"}, style="frame_action_button", mouse_button_filter={"left"}}
    button_close.style.padding = 1
end


-- ** EVENTS **
local listeners = {}

listeners.gui = {
    on_gui_click = {
        {
            name = "re-center_main_dialog",
            handler = (function(player, _, event)
                if event.button == defines.mouse_button_type.middle then
                    local ui_state = data_util.ui_state(player)
                    local main_frame = ui_state.main_elements.main_frame
                    ui_util.properly_center_frame(player, main_frame, ui_state.main_dialog_dimensions)
                end
            end)
        },
        {
            name = "switch_to_compact_view",
            handler = (function(player, _, _)
                main_dialog.toggle(player)
                data_util.flags(player).compact_view = true

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
                ui_util.raise_open_dialog(player, {dialog=tags.type})
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
        local triggers = {title_bar=true, subfactory=true, all=true}
        if triggers[event.trigger] then refresh_title_bar(player) end
    end)
}

return { listeners }
