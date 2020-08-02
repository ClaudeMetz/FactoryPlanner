-- Assembles event handlers from all the relevant files and calls them when needed
event_handler = {}

local event_identifier_name_map = {
    [defines.events.on_gui_click] = "on_gui_click",
    [defines.events.on_gui_confirmed] = "on_gui_confirmed",
    [defines.events.on_gui_text_changed] = "on_gui_text_changed",
    [defines.events.on_gui_checked_state_changed] = "on_gui_checked_state_changed",
    [defines.events.on_gui_elem_changed] = "on_gui_elem_changed",
    [defines.events.on_gui_switch_state_changed] = "on_gui_switch_state_changed"
}

local event_standard_timeouts = {
    --on_gui_click = 10,  -- TODO need to use the listener one for this for now
    on_gui_confirmed = 30
}

-- (not really objects, as in instances of a class, but naming is hard, alright?)
local objects_that_need_handling = {porter_dialog, import_dialog, export_dialog, tutorial_dialog, chooser_dialog,
  options_dialog, utility_dialog, preferences_dialog, module_dialog, beacon_dialog, subfactory_dialog, product_dialog,
  recipe_dialog}

local event_cache = {}
local special_handlers = {}


-- ** LOCAL UTIL **
-- Returns whether the given event is allowed to take place
-- TODO clean up when other rate limiting is gone; rename object_name to element_name
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



local function standard_handler(player, event, event_handlers)
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
            handler_table.handler(player, event.element)
        end
    end

    -- Return whether a handler was found or not
    return (handler_table ~= nil)
end


-- ** SPECIAL HANDLERS **
function special_handlers.on_gui_confirmed(player, event, event_handlers)
    -- Try the normal handler, if it returns true, an event_handler was found
    if standard_handler(player, event, event_handlers) then
        return

    -- Otherwise, close the currently open modal dialog, if possible
    elseif data_util.get("ui_state", player).modal_dialog_type ~= nil then
        -- Doesn't need rate limiting because of the check above (I think)
        modal_dialog.exit(player, "submit", {})
    end
end


-- Actually compile a list of handlers
for _, object in pairs(objects_that_need_handling) do
    if object.events then
        for event_name, elements in pairs(object.events) do
            event_cache[event_name] = event_cache[event_name] or {
                names = {},
                patterns = {},
                special_handler = special_handlers[event_name]
            }

            for _, element in pairs(elements) do
                local handler_table = {handler = element.handler, timeout = nil}

                local element_timeout = element.timeout
                if not element_timeout then handler_table.timeout = event_standard_timeouts[event_name]
                elseif element_timeout ~= 0 then handler_table.timeout = element_timeout end

                if element.name then
                    event_cache[event_name].names[element.name] = handler_table
                elseif element.pattern then
                    event_cache[event_name].patterns[element.pattern] = handler_table
                end
            end
        end
    end
end


-- ** TOP LEVEL **
function event_handler.handle_gui_event(event)
    if event.element and string.find(event.element.name, "^fp_.+$") then
        local player = game.get_player(event.player_index)

        -- The event table actually contains its identifier, not its name
        local event_name = event_identifier_name_map[event.name]
        local event_handlers = event_cache[event_name]

        if event_handlers then  -- make sure the given event is even handled
            if event_handlers.special_handler then
                event_handlers.special_handler(player, event, event_handlers)
            else
                standard_handler(player, event, event_handlers)
            end
        end
    end
end