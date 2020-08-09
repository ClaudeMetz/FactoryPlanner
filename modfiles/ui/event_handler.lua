-- Assembles event handlers from all the relevant files and calls them when needed
event_handler = {}

-- (not really objects, as in instances of a class, but naming is hard, alright?)
local objects_that_need_handling = {main_dialog, modal_dialog, porter_dialog, import_dialog, export_dialog,
  tutorial_dialog, chooser_dialog, options_dialog, utility_dialog, preferences_dialog, module_dialog, beacon_dialog,
  modules_dialog, product_dialog, recipe_dialog}

-- ** RATE LIMITING **
-- Returns whether the given event is allowed to take place
-- TODO clean up when other rate limiting is gone; rename object_name to element_name
-- This is also not made to work with non-GUI events, which I'll have to fix
-- NOT IN USE CURRENTLY
local function rate_limit(player, event, element_name, timeout)
    local last_action = data_util.get("ui_state", player).last_action

    -- Always allow action if there is no last_action or the ticks are paused
    local limiting_active = (table_size(last_action) > 0 and not game.tick_paused
      and event.name == last_action.event_name and element_name == last_action.object_name
      and (event.tick - last_action.tick) < timeout)

    -- Only update the last action if an action will indeed be carried out
    if not limiting_active then
        last_action.tick = event.tick
        last_action.event_name = event.name
        last_action.object_name = element_name
    end

    return (not limiting_active)
end


-- ** GUI HANDLERS **
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
    --on_gui_click = 10,  -- TODO need to use the listener one for this for now
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
        local timeout = handler_table.timeout
        if (timeout == nil) or rate_limit(player, event, element_name, timeout) then
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
-- Actually compile a list of GUI handlers
for _, object in pairs(objects_that_need_handling) do
    if object.events then
        for event_name, elements in pairs(object.events) do
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
for event_id, _ in pairs(gui_identifier_map) do
    -- TODO not in use yet as to not overwrite the listeners registrations
    --script.on_event(event_id, event_handler.handle_gui_event)
end




--[[ special_handlers.on_gui_opened = {
    raw_event = true,
    special_handler = (function(player, event, event_handlers)
        -- Closes the main dialog when the player opens another UI while in a modal dialog
        if event.gui_type ~= defines.gui_type.custom or not event.element.get_mod() == "factoryplanner" then
            event_handlers.names["fp_frame_main_dialog"].handler(player)
        end
    end)
} ]]