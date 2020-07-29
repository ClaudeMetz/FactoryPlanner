-- Assembles event handlers from all the relevant files and calls them when needed
event_handler = {}

local event_identifier_name_map = {
    [defines.events.on_gui_click] = "on_gui_click",
    [defines.events.on_gui_text_changed] = "on_gui_text_changed",
    [defines.events.on_gui_confirmed] = "on_gui_confirmed"
}

-- (not really objects, as in instances of a class, but naming is hard, alright?)
local objects_that_need_handling = {porter_dialog, import_dialog, export_dialog}

local event_cache = {}
local special_handlers = {}


for _, object in pairs(objects_that_need_handling) do
    if object.events then
        for event_name, elements in pairs(object.events) do
            event_cache[event_name] = event_cache[event_name] or {
                names = {},
                patterns = {}
            }

            for _, element in pairs(elements) do
                if element.name then
                    event_cache[event_name].names[element.name] = element.handler
                elseif element.pattern then
                    event_cache[event_name].patterns[element.pattern] = element.handler
                end
            end
        end
    end
end

-- ** LOCAL UTIL **
local function standard_handler(player, element, event_handlers)
    local element_name = element.name
    local handler_by_name = event_handlers.names[element_name]

    if handler_by_name then
        handler_by_name(player, element)
        return true
    else
        for pattern, handler in pairs(event_handlers.patterns) do
            if string.find(element_name, pattern) then
                handler(player, element)
                return true
            end
        end
    end

    return false
end


-- ** SPECIAL HANDLERS **
special_handlers["on_gui_confirmed"] = (function(player, element, event_handlers)
    -- Try the normal handler, if it returns true, an event_handler has been run
    if standard_handler(player, element, event_handlers) then
        return

    -- Otherwise, close the currently open modal dialog, if possible
    elseif data_util.get("ui_state", player).modal_dialog_type ~= nil then
        modal_dialog.exit(player, "submit", {})
    end
end)


-- ** TOP LEVEL **
function event_handler.handle_gui_event(event)
    if event.element and string.find(event.element.name, "^fp_.+$") then
        local player = game.get_player(event.player_index)

        -- TODO incorporate rate limiting

        -- The event table actually contains its identifier, not its name
        local event_name = event_identifier_name_map[event.name]
        local event_handlers = event_cache[event_name]

        if event_handlers then  -- make sure the given event is even handled
            local special_handler = special_handlers[event_name]
            if special_handler then
                special_handler(player, event.element, event_handlers)
            else
                standard_handler(player, event.element, event_handlers)
            end
        end
    end
end