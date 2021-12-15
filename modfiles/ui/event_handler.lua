-- Assembles event handlers from all the relevant files and calls them when needed

local gui_objects = {main_dialog, title_bar, subfactory_list, subfactory_info, item_boxes,
  production_box, production_handler, view_state, modal_dialog, porter_dialog, import_dialog, export_dialog,
  tutorial_dialog, chooser_dialog, options_dialog, utility_dialog, preferences_dialog, module_dialog, beacon_dialog,
  modules_dialog, picker_dialog, recipe_dialog, matrix_dialog}

-- ** RATE LIMITING **
-- Returns whether rate limiting is active for the given action, stopping it from proceeding
-- This is essentially to prevent duplicate commands in quick succession, enabled by lag
local function rate_limiting_active(player, tick, action_name, timeout)
    local ui_state = data_util.get("ui_state", player)

    -- If this action has no timeout, reset the last action and allow it
    if timeout == nil or game.tick_paused then
        ui_state.last_action = nil
        return false
    end

    local last_action = ui_state.last_action
    -- Only disallow action under these specific circumstances
    if last_action and last_action.action_name == action_name and (tick - last_action.tick) < timeout then
        return true

    else  -- set the last action if this action will actually be carried out
        ui_state.last_action = {
            action_name = action_name,
            tick = tick
        }
        return false
    end
end

-- ** TUTORIAL TOOLTIPS **
local function generate_tutorial_tooltip_lines(modifier_actions)
    local action_lines = {}

    for modifier_click, modifier_action in pairs(modifier_actions) do
        if modifier_action.name ~= "recipebook" then  -- needs dynamic handling
            local split_modifiers = split_string(modifier_click, "-")

            local modifier_string = {""}
            for _, modifier in pairs(fancytable.slice(split_modifiers, 1, -1)) do
                table.insert(modifier_string, {"", {"fp.tut_" .. modifier}, " + "})
            end
            table.insert(modifier_string, {"fp.tut_" .. split_modifiers[#split_modifiers]})

            local action_string = {"fp.tut_action_line", modifier_string, {"fp.tut_" .. modifier_action.name}}
            table.insert(action_lines, {string=action_string, limitations=modifier_action.limitations})
        end
    end

    return action_lines
end


-- ** GUI EVENTS **
-- These handlers go out to the first thing that it finds that registered for it
-- They can register either by element name or by a pattern matching element names
local gui_identifier_map = {
    [defines.events.on_gui_click] = "on_gui_click",
    [defines.events.on_gui_closed] = "on_gui_closed",
    [defines.events.on_gui_confirmed] = "on_gui_confirmed",
    [defines.events.on_gui_text_changed] = "on_gui_text_changed",
    [defines.events.on_gui_checked_state_changed] = "on_gui_checked_state_changed",
    [defines.events.on_gui_switch_state_changed] = "on_gui_switch_state_changed",
    [defines.events.on_gui_elem_changed] = "on_gui_elem_changed",
    [defines.events.on_gui_value_changed] = "on_gui_value_changed"
}

local gui_timeouts = {
    on_gui_click = 2,
    on_gui_confirmed = 20
}


-- ** SPECIAL HANDLERS **
local special_gui_handlers = {}

special_gui_handlers.on_gui_closed = (function(event, _, _)
    return (event.gui_type == defines.gui_type.custom and event.element.visible)
end)

special_gui_handlers.on_gui_confirmed = (function(_, player, action_name)
    if action_name then return true end  -- run the standard handler if one is found

    -- Otherwise, close the currently open modal dialog if possible
    if data_util.get("ui_state", player).modal_dialog_type ~= nil then
        modal_dialog.exit(player, "submit")
    end
    return false
end)


local gui_event_cache = {}
-- Create tables for all events that are being registered
for _, event_name in pairs(gui_identifier_map) do
    gui_event_cache[event_name] = {
        actions = {},
        special_handler = special_gui_handlers[event_name]
    }
end

-- Compile the list of GUI actions
for _, object in pairs(gui_objects) do
    if object.gui_events then
        for event_name, actions in pairs(object.gui_events) do
            local event_table = gui_event_cache[event_name]

            for _, action in pairs(actions) do
                local timeout = action.timeout or gui_timeouts[event_name]  -- can be nil
                local action_table = {handler = action.handler, timeout = timeout}

                if event_name == "on_gui_click" and action.modifier_actions then
                    action_table.modifier_actions = {}
                    -- Transform modifier actions into a more useable form
                    for modifier_action_name, modifier_action in pairs(action.modifier_actions) do
                        local modifier_click = modifier_action[1]
                        action_table.modifier_actions[modifier_click] = {
                            name = modifier_action_name,
                            limitations = modifier_action[2] or {}
                        }
                    end

                    -- Generate all the tooltip lines for these modifier actions
                    TUTORIAL_TOOLTIPS[action.name] = generate_tutorial_tooltip_lines(action_table.modifier_actions)
                end

                event_table.actions[action.name] = action_table
            end
        end
    end
end

local mouse_click_map = {
    [defines.mouse_button_type.left] = "left",
    [defines.mouse_button_type.right] = "right",
    [defines.mouse_button_type.middle] = "middle"
}
local function convert_click_to_string(event)
    local modifier_click = mouse_click_map[event.button]
    if event.shift then modifier_click = "shift-" .. modifier_click end
    if event.alt then modifier_click = "alt-" .. modifier_click end
    if event.control then modifier_click = "control-" .. modifier_click end
    return modifier_click
end

local function handle_gui_event(event)
    if not event.element then return end

    local tags = event.element.tags
    if tags.mod ~= "fp" then return end

    -- GUI events always have an associated player
    local player = game.get_player(event.player_index)

    -- The event table actually contains its identifier, not its name
    local event_name = gui_identifier_map[event.name]
    local event_table = gui_event_cache[event_name]
    local action_name = tags[event_name]  -- could be nil

    -- If a special handler is set, it needs to return true before proceeding with the registered handlers
    local special_handler = event_table.special_handler
    if special_handler and special_handler(event, player, action_name) == false then return end

    -- Special handlers need to run even without an action handler, so we
    -- wait until this point to check whether there is an associated action
    if not action_name then return end  -- meaning this event type has no action on this element
    local action_table = event_table.actions[action_name]

    -- Check if rate limiting allows this action to proceed
    if rate_limiting_active(player, event.tick, action_name, action_table.timeout) then return end

    local third_parameter = event  -- all GUI events except on_gui_click have the event as the third parameter

    -- Special modifier handling for on_gui_click if configured
    if event_name == "on_gui_click" and action_table.modifier_actions then
        local modifier_action = action_table.modifier_actions[convert_click_to_string(event)]
        if not modifier_action then return end  -- meaning the used modifiers do not have an associated action

        local active_limitations = {
            archive_open = data_util.get("flags", player).archive_open,
            matrix_active = (data_util.get("context", player).subfactory.matrix_free_items ~= nil),
            recipebook = (script.active_mods["RecipeBook"] ~= nil)
        }
        -- Check whether the selected action is allowed according to its limitations
        if not data_util.action_allowed(modifier_action.limitations, active_limitations) then return end

        third_parameter = modifier_action.name
    end

    action_table.handler(player, tags, third_parameter)
end

-- Register all the GUI events from the identifier map
for event_id, _ in pairs(gui_identifier_map) do script.on_event(event_id, handle_gui_event) end



-- ** MISC EVENTS **
-- These events call every handler that has subscribed to it by id or name. The difference to GUI events
-- is that multiple handlers can be registered to the same event, and there is no standard handler

local misc_identifier_map = {
    -- Standard events
    [defines.events.on_gui_opened] = "on_gui_opened",
    [defines.events.on_player_display_resolution_changed] = "on_player_display_resolution_changed",
    [defines.events.on_player_display_scale_changed] = "on_player_display_scale_changed",
    [defines.events.on_player_selected_area] = "on_player_selected_area",
    [defines.events.on_player_cursor_stack_changed] = "on_player_cursor_stack_changed",
    [defines.events.on_player_main_inventory_changed] = "on_player_main_inventory_changed",
    [defines.events.on_lua_shortcut] = "on_lua_shortcut",

    -- Keyboard shortcuts
    ["fp_toggle_main_dialog"] = "fp_toggle_main_dialog",
    ["fp_confirm_dialog"] = "fp_confirm_dialog",
    ["fp_focus_searchfield"] = "fp_focus_searchfield",
    ["fp_toggle_pause"] = "fp_toggle_pause",
    ["fp_cycle_production_views"] = "fp_cycle_production_views",
    ["fp_refresh_production"] = "fp_refresh_production",
    ["fp_floor_up"] = "fp_floor_up"
}

local misc_timeouts = {
    fp_confirm_dialog = 20
}

-- ** SPECIAL HANDLERS **
local special_misc_handlers = {}

special_misc_handlers.on_gui_opened = (function(event)
    -- This should only fire when a UI not associated with FP is opened, so FP's dialogs can close properly
    return (event.gui_type ~= defines.gui_type.custom or not event.element or event.element.tags.mod ~= "fp")
end)


local misc_event_cache = {}
-- Compile the list of misc handlers
for _, object in pairs(gui_objects) do
    if object.misc_events then
        for event_name, handler in pairs(object.misc_events) do
            misc_event_cache[event_name] = misc_event_cache[event_name] or {
                registered_handlers = {},
                special_handler = special_misc_handlers[event_name],
                timeout = misc_timeouts[event_name]
            }

            table.insert(misc_event_cache[event_name].registered_handlers, handler)
        end
    end
end


local function handle_misc_event(event)
    local event_name = event.input_name or event.name -- also handles keyboard shortcuts
    local event_handlers = misc_event_cache[misc_identifier_map[event_name]]
    if not event_handlers then return end  -- make sure the given event is even handled

    -- We'll assume every one of the events has a player attached
    local player = game.get_player(event.player_index)

    -- Check if the action is allowed to be carried out by rate limiting
    if rate_limiting_active(player, event.tick, event_name, event_handlers.timeout) then return end

    -- If a special handler is set, it needs to return true before proceeding with the registered handlers
    local special_handler = event_handlers.special_handler
    if special_handler and special_handler(event) == false then return end

    for _, registered_handler in pairs(event_handlers.registered_handlers) do registered_handler(player, event) end
end

-- Register all the misc events from the identifier map
for event_id, _ in pairs(misc_identifier_map) do script.on_event(event_id, handle_misc_event) end
