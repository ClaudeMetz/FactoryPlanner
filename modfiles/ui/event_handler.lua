-- Assembles event handlers from all the relevant files and calls them when needed
event_handler = {}

-- (not really objects, as in instances of a class, but naming is hard, alright?)
local objects_that_need_handling = {main_dialog, modal_dialog, porter_dialog, import_dialog, export_dialog,
  tutorial_dialog, chooser_dialog, options_dialog, utility_dialog, preferences_dialog, module_dialog, beacon_dialog,
  modules_dialog, picker_dialog, recipe_dialog}


-- ** RATE LIMITING **
-- Returns whether the given event is allowed to take place
-- This is essentially to prevent duplicate commands in quick succession, enabled by lag
local function rate_limit_action(player, event_name, tick, element_name, timeout)
    local ui_state = data_util.get("ui_state", player)
    local last_action = ui_state.last_action

    -- If this action has no timeout, reset the last action and allow it
    if timeout == nil or game.tick_paused then
        ui_state.last_action = nil
        return true
    end

    -- Only disallow action under these specific circumstances
    if last_action ~= nil and last_action.event_name == event_name and (not element_name
      or last_action.element_name == element_name) and (tick - last_action.tick) < timeout then
        return false

    else  -- set the last action if this action will actually be carried out
        ui_state.last_action = {
            tick = tick,
            event_name = event_name,
            element_name = element_name
        }
        return true
    end
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
    on_gui_click = 4,
    on_gui_confirmed = 20
}


local function standard_gui_handler(player, event, event_handlers, metadata)
    local element_name = event.element.name

    -- Try finding the appropriate handler_table by name first
    local handler_table = event_handlers.names[element_name]

    -- If it can't be found, go through the patterns
    if handler_table == nil then
        for pattern, potential_handler_table in pairs(event_handlers.patterns) do
            if string.find(element_name, pattern) then
                handler_table = potential_handler_table
                break
            end
        end
    end

    -- If a handler_table has been found, run its handler, if it's not rate limited
    if handler_table ~= nil then
        if rate_limit_action(player, event.name, event.tick, element_name, handler_table.timeout) then
            handler_table.handler(player, event.element, metadata)
        end
    end

    -- Return whether a handler was found or not
    return (handler_table ~= nil)
end


-- ** SPECIAL HANDLERS **
local special_gui_handlers = {}

special_gui_handlers.on_gui_click = (function(player, event, event_handlers)
    local metadata = {alt=event.alt}

    standard_gui_handler(player, event, event_handlers, metadata)
end)

special_gui_handlers.on_gui_closed = (function(player, event, event_handlers)
    if event.gui_type == defines.gui_type.custom and event.element.visible then
        standard_gui_handler(player, event, event_handlers)
    end
end)

special_gui_handlers.on_gui_confirmed = (function(player, event, event_handlers)
    -- Try the normal handler, if it returns true, an event_handler was found
    if standard_gui_handler(player, event, event_handlers) then
        return

    -- Otherwise, close the currently open modal dialog, if possible
    elseif data_util.get("ui_state", player).modal_dialog_type ~= nil then
        -- Doesn't need rate limiting because of the check above (I think)
        modal_dialog.exit(player, "submit")
    end
end)


local gui_event_cache = {}
-- Actually compile the list of GUI handlers
for _, object in pairs(objects_that_need_handling) do
    if object.gui_events then
        for event_name, elements in pairs(object.gui_events) do
            gui_event_cache[event_name] = gui_event_cache[event_name] or {
                names = {},
                patterns = {},
                special_handler = special_gui_handlers[event_name]
            }

            for _, element in pairs(elements) do
                local handler_table = {handler = element.handler, timeout = nil}

                local element_timeout = element.timeout
                if not element_timeout then handler_table.timeout = gui_timeouts[event_name]
                elseif element_timeout ~= 0 then handler_table.timeout = element_timeout end

                if element.name then
                    gui_event_cache[event_name].names[element.name] = handler_table
                elseif element.pattern then
                    gui_event_cache[event_name].patterns[element.pattern] = handler_table
                end
            end
        end
    end
end

-- TODO make everything in this file file-local after listeners.lua is no more
function event_handler.handle_gui_event(event)
    if event.element and event.element.get_mod() == "factoryplanner" then
        -- The event table actually contains its identifier, not its name
        local event_name = gui_identifier_map[event.name]
        local event_handlers = gui_event_cache[event_name]

        if event_handlers then  -- make sure the given event is even handled
            local player = game.get_player(event.player_index)

            if event_handlers.special_handler then
                event_handlers.special_handler(player, event, event_handlers)
            else
                standard_gui_handler(player, event, event_handlers)
            end
        end
    end
end

-- Register all the GUI events from the identifier map
-- TODO not in use yet as to not overwrite the listeners registrations
--[[ for event_id, _ in pairs(gui_identifier_map) do
    script.on_event(event_id, event_handler.handle_gui_event)
end ]]



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
    ["fp_focus_searchfield"] = "fp_focus_searchfield"
}

local misc_timeouts = {
    fp_confirm_dialog = 20
}

-- ** SPECIAL HANDLERS **
local special_misc_handlers = {}

special_misc_handlers.on_gui_opened = (function(_, event)
    -- This should only fire when a UI not associated with FP is opened, to properly close FP's stuff
    return (event.gui_type ~= defines.gui_type.custom or not event.element.get_mod() == "factoryplanner")
end)


local misc_event_cache = {}
-- Actually compile the list of misc handlers
for _, object in pairs(objects_that_need_handling) do
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

    if event_handlers then  -- make sure the given event is even handled
        -- I will assume every one of the events has a player attached
        local player = game.get_player(event.player_index)

        -- Check if the action is allowed to be carried out by rate limiting
        if not rate_limit_action(player, event_name, event.tick, nil, event_handlers.timeout) then
            return
        end

        -- If a special handler is set, it needs to return true before proceeding with the registered handlers
        local special_handler = event_handlers.special_handler
        if special_handler and not event_handlers.special_handler(player, event) then
            return
        end

        for _, registered_handler in pairs(event_handlers.registered_handlers) do
            registered_handler(player, event)
        end
    end
end

-- Register all the misc events from the identifier map
for event_id, _ in pairs(misc_identifier_map) do
    script.on_event(event_id, handle_misc_event)
end