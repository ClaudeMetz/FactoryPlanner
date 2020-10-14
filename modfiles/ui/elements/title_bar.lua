title_bar = {}

-- ** LOCAL UTIL **
local function configure_pause_button_style(button, pause_on_interface)
    if pause_on_interface then
        button.style = "fp_sprite-button_tool_active"
        button.sprite = "utility/pause"
        button.clicked_sprite = "fp_sprite_pause_light"
    else
        button.style = "frame_action_button"
        button.sprite = "fp_sprite_pause_light"
        button.clicked_sprite = "utility/pause"
    end
end

local function toggle_paused_state(player, button)
    if not game.is_multiplayer() then
        local preferences = data_util.get("preferences", player)
        preferences.pause_on_interface = not preferences.pause_on_interface

        configure_pause_button_style(button, preferences.pause_on_interface)

        local frame_main_dialog = data_util.get("main_elements", player).main_frame
        main_dialog.set_pause_state(player, frame_main_dialog)
    end
end

-- ** TOP LEVEL **
function title_bar.build(player)
    local main_elements = data_util.get("main_elements", player)
    main_elements.title_bar = {}

    local flow_title_bar = main_elements.main_frame.add{type="flow", direction="horizontal"}
    flow_title_bar.style.height = 28
    flow_title_bar.style.margin = {2, 0, 4, 4}
    flow_title_bar.style.horizontal_spacing = 8

    flow_title_bar.add{type="label", caption={"mod-name.factoryplanner"}, style="frame_title"}

    local label_hint = flow_title_bar.add{type="label"}
    label_hint.style.font = "heading-2"
    main_elements.title_bar["hint_label"] = label_hint

    local drag_handle = flow_title_bar.add{type="empty-widget", style="flib_titlebar_drag_handle"}
    drag_handle.drag_target = main_elements.main_frame
    drag_handle.style.margin = {1, 2, 0, 2}

    -- Buttons
    flow_title_bar.add{type="button", name="fp_button_title_bar_tutorial", caption={"fp.tutorial"},
      style="fp_button_frame_tool",  mouse_button_filter={"left"}}
    flow_title_bar.add{type="button", name="fp_button_title_bar_preferences", caption={"fp.preferences"},
      style="fp_button_frame_tool", mouse_button_filter={"left"}}

    local separation = flow_title_bar.add{type="line", direction="vertical"}
    separation.style.height = 24

    local button_pause = flow_title_bar.add{type="sprite-button", name="fp_sprite-button_title_bar_pause_game",
      tooltip={"fp.pause_on_interface"}, enabled=(not game.is_multiplayer()), mouse_button_filter={"left"}}
    button_pause.hovered_sprite = "utility/pause"
    main_elements.title_bar["pause_button"] = button_pause

    local preferences = data_util.get("preferences", player)
    configure_pause_button_style(button_pause, preferences.pause_on_interface)

    local button_close = flow_title_bar.add{type="sprite-button", name="fp_sprite-button_title_bar_close_interface",
      sprite="utility/close_white", tooltip={"fp.close_interface"}, style="frame_action_button",
      mouse_button_filter={"left"}}
    button_close.style.padding = 2
    button_close.hovered_sprite = "utility/close_black"
    button_close.clicked_sprite = "utility/close_black"
end


-- Enqueues the given message into the message queue; Possible types: error, warning, hint
function title_bar.enqueue_message(player, message, type, lifetime, instant_refresh)
    local message_queue = data_util.get("ui_state", player).message_queue
    table.insert(message_queue, {text=message, type=type, lifetime=lifetime})

    if instant_refresh then title_bar.refresh_message(player) end
end

-- Refreshes the current message, taking into account priotities and lifetimes
-- The messages are displayed in enqueued order, displaying higher priorities first
-- The lifetime is decreased for every message on every refresh
-- (The algorithm(s) could be more efficient, but it doesn't matter for the small dataset)
function title_bar.refresh_message(player)
    local ui_state = data_util.get("ui_state", player)
    local message_queue = ui_state.message_queue

    local title_bar_elements = ui_state.main_elements.title_bar
    if not title_bar_elements then return end

    -- The message types are ordered by priority
    local types = {"error", "warning", "hint"}

    local new_message = nil
    -- Go over the all types and messages, trying to find one that should be shown
    for _, type in ipairs(types) do
        -- All messages will have lifetime > 0 at this point
        for _, message in pairs(message_queue) do
            -- Find first message of this type, then break
            if message.type == type then
                new_message = message
                break
            end
        end
        -- If a message is found, break because no messages of lower ranked type should be considered
        if new_message ~= nil then break end
    end

    title_bar_elements.hint_label.caption = (new_message) and
      {"fp." .. new_message.type .. "_message", new_message.text} or ""

    -- Decrease the lifetime of every queued message
    for index, message in pairs(message_queue) do
        message.lifetime = message.lifetime - 1
        if message.lifetime <= 0 then message_queue[index] = nil end
    end
end


-- ** EVENTS **
title_bar.gui_events = {
    on_gui_click = {
        {
            name = "fp_sprite-button_title_bar_close_interface",
            handler = main_dialog.toggle
        },
        {
            name = "fp_sprite-button_title_bar_pause_game",
            handler = toggle_paused_state
        },
        {
            pattern = "^fp_button_title_bar_[a-z]+$",
            handler = (function(player, element, _)
                local dialog_name = string.gsub(element.name, "fp_button_title_bar_", "")
                modal_dialog.enter(player, {type=dialog_name})
            end)
        }
    }
}

title_bar.misc_events = {
    fp_toggle_pause = (function(player, _)
        local main_elements = data_util.get("main_elements", player)
        if main_elements.main_frame and main_elements.main_frame.visible then
            toggle_paused_state(player, main_elements.title_bar.pause_button)
        end
    end)
}