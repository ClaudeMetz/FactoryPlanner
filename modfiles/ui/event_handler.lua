-- Assembles event handlers from all the relevant files and calls them when needed

local event_listener_names = {
    "ui.base.main_dialog", "ui.base.compact_dialog", "ui.base.modal_dialog", "ui.base.item_views",
    "ui.base.calculator_dialog",
    "ui.main.title_bar", "ui.main.district_info", "ui.main.factory_list", "ui.main.production_bar",
    "ui.main.districts_box", "ui.main.item_boxes", "ui.main.production_box", "ui.main.production_table",
    "ui.main.production_handler", "ui.elements.module_configurator",
    "ui.dialogs.beacon_dialog", "ui.dialogs.machine_dialog", "ui.dialogs.picker_dialog", "ui.dialogs.picker_dialog",
    "ui.dialogs.porter_dialog", "ui.dialogs.preferences_dialog", "ui.dialogs.recipe_dialog",
    "ui.dialogs.factory_dialog", "ui.dialogs.utility_dialog"
}

local event_listeners = {}
for _, listener_path in ipairs(event_listener_names) do
    for _, listener in pairs(require(listener_path)) do
        table.insert(event_listeners, listener)
    end
end


-- ** GUI EVENTS **
-- These handlers go out to the first thing that it finds that registered for it.
-- They can register either by element name or by a pattern matching element names.
local gui_identifier_map = {
    [defines.events.on_gui_click] = "on_gui_click",
    [defines.events.on_gui_closed] = "on_gui_closed",
    [defines.events.on_gui_confirmed] = "on_gui_confirmed",
    [defines.events.on_gui_text_changed] = "on_gui_text_changed",
    [defines.events.on_gui_checked_state_changed] = "on_gui_checked_state_changed",
    [defines.events.on_gui_switch_state_changed] = "on_gui_switch_state_changed",
    [defines.events.on_gui_selection_state_changed] = "on_gui_selection_state_changed",
    [defines.events.on_gui_elem_changed] = "on_gui_elem_changed",
    [defines.events.on_gui_value_changed] = "on_gui_value_changed",
    [defines.events.on_gui_hover] = "on_gui_hover",
    [defines.events.on_gui_leave] = "on_gui_leave"
}

-- ** SPECIAL HANDLERS **
local special_gui_handlers = {}

special_gui_handlers.on_gui_closed = (function(event, _, _)
    return (event.gui_type == defines.gui_type.custom and event.element.visible)
end)

special_gui_handlers.on_gui_confirmed = (function(_, player, action_name)
    if action_name then return true end  -- run the standard handler if one is found

    -- Otherwise, close the currently open modal dialog if possible
    if util.globals.ui_state(player).modal_dialog_type ~= nil then
        util.raise.close_dialog(player, "submit")
    end
    return false
end)

local gui_timeouts = {
    on_gui_click = 2,
    on_gui_confirmed = 20
}


---@class ActionTable
---@field handler function
---@field timeout Tick
---@field actions ActionDetails
---@field shortcuts { string: ActionDetails }
---@field tooltip LocalisedString

---@class ActionDetails
---@field name string
---@field limitations ActionLimitations
---@field shortcut_string LocalisedString
---@field show boolean

-- Compile and format the list of GUI actions
for _, listener in pairs(event_listeners) do
    for event_name, actions in pairs(listener.gui or {}) do
        for _, action in pairs(actions) do
            local timeout = action.timeout or gui_timeouts[event_name]  -- can be nil
            local action_table = {handler = action.handler, timeout = timeout}

            if event_name == "on_gui_click" and action.actions_table then
                action_table.actions, action_table.shortcuts = {}, {}
                -- Transform actions table into a more useable form
                for action_name, modifier_action in pairs(action.actions_table) do
                    local action_details = {
                        name = action_name,
                        limitations = modifier_action.limitations or {},
                        shortcut_string = util.actions.shortcut_string(modifier_action.shortcut),
                        show = modifier_action.show
                    }
                    table.insert(action_table.actions, action_details)

                    if modifier_action.shortcut then
                        action_table.shortcuts[modifier_action.shortcut] = action_details
                    end
                end
                action_table.tooltip = util.actions.generate_tooltip(action_table.actions)
            end

            MODIFIER_ACTIONS[action.name] = action_table
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

    -- Guard against an event being called before the player is initialized
    if not storage.players[event.player_index] then return end

    -- GUI events always have an associated player
    local player = game.get_player(event.player_index)  ---@cast player -nil

    -- The event table actually contains its identifier, not its name
    local event_name = gui_identifier_map[event.name]
    local action_name = tags[event_name]  -- could be nil

    -- Close an open context menu on any GUI click
    if event_name == "on_gui_click" then modal_dialog.close_context_menu(player) end

    -- If a special handler is set, it needs to return true before proceeding with the registered handlers
    local special_handler = special_gui_handlers[event_name]
    if special_handler and special_handler(event, player, action_name) == false then return end

    -- Special handlers need to run even without an action handler, so we
    -- wait until this point to check whether there is an associated action
    if not action_name then return end  -- meaning this event type has no action on this element
    local action_table = MODIFIER_ACTIONS[action_name] or {}

    -- Check if rate limiting allows this action to proceed
    if util.actions.rate_limited(player, event.tick, action_name, action_table.timeout) then return end

    -- Special modifier handling for on_gui_click if configured
    if event_name == "on_gui_click" and action_table.actions then
        local click = convert_click_to_string(event)

        if click == "right" then
            modal_dialog.open_context_menu(player, tags, action_name,
                action_table.actions, event.cursor_display_location)
        else
            local modifier_action = action_table.shortcuts[click]
            if not modifier_action then return end  -- meaning the used modifiers do not have an associated action

            local active_limitations = util.actions.current_limitations(player)
            if util.actions.allowed(modifier_action.limitations, active_limitations) then
                action_table.handler(player, tags, modifier_action.name)
            end
        end
    else
        action_table.handler(player, tags, event)  -- gets event as third parameter
    end

    -- Only refresh messages if the event wasn't a hover event
    if event_name ~= "on_gui_hover" and event_name ~= "on_gui_leave" then util.messages.refresh(player) end
end

-- Register all the GUI events from the identifier map
for event_id, _ in pairs(gui_identifier_map) do script.on_event(event_id, handle_gui_event) end



-- ** DIALOG EVENTS **
-- These custom events handle opening and closing modal dialogs
local dialog_event_cache = {}
-- Compile the list of dialog actions
for _, listener in pairs(event_listeners) do
    if listener.dialog then
        dialog_event_cache[listener.dialog.dialog] = listener.dialog
    end
end

local function apply_metadata_overrides(base, overrides)
    for k, v in pairs(overrides) do
        local base_v = base[k]
        if type(base_v) == "table" and type(v) == "table" then
            apply_metadata_overrides(base_v, v)
        else
            base[k] = v
        end
    end
end

local function handle_dialog_event(event)
    -- Guard against an event being called before the player is initialized
    if not storage.players[event.player_index] then return end

    -- These custom events always have an associated player
    local player = game.get_player(event.player_index)  ---@cast player -nil
    local ui_state = util.globals.ui_state(player)

    -- Check if the action is allowed to be carried out by rate limiting
    if util.actions.rate_limited(player, event.tick, event.name, 20) then return end

    if event.name == CUSTOM_EVENTS.open_modal_dialog then
        local listener = dialog_event_cache[event.metadata.dialog]

        local metadata = event.metadata
        if listener.metadata ~= nil then  -- collect additional metadata
            local additional_metadata = listener.metadata(metadata.modal_data)
            apply_metadata_overrides(metadata, additional_metadata)
        end

        modal_dialog.enter(player, metadata, listener.open, listener.early_abort_check)

    elseif event.name == CUSTOM_EVENTS.close_modal_dialog then
        local modal_dialog_type = ui_state.modal_dialog_type
        if modal_dialog_type == nil then return end

        local listener = dialog_event_cache[modal_dialog_type]
        modal_dialog.exit(player, event.action, event.skip_opened, listener.close)
    end
end

-- Register all the misc events from the identifier map
local dialog_events = {CUSTOM_EVENTS.open_modal_dialog, CUSTOM_EVENTS.close_modal_dialog}
for _, event_id in pairs(dialog_events) do script.on_event(event_id, handle_dialog_event) end



-- ** MISC EVENTS **
-- These events call every handler that has subscribed to it by id or name. The difference to GUI events
-- is that multiple handlers can be registered to the same event, and there is no standard handler.
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
    ["fp_toggle_interface"] = "fp_toggle_interface",
    ["fp_toggle_compact_view"] = "fp_toggle_compact_view",
    ["fp_toggle_pause"] = "fp_toggle_pause",
    ["fp_refresh_production"] = "fp_refresh_production",
    ["fp_up_floor"] = "fp_up_floor",
    ["fp_top_floor"] = "fp_top_floor",
    ["fp_cycle_production_views"] = "fp_cycle_production_views",
    ["fp_reverse_cycle_production_views"] = "fp_reverse_cycle_production_views",
    ["fp_confirm_dialog"] = "fp_confirm_dialog",
    ["fp_confirm_gui"] = "fp_confirm_gui",
    ["fp_focus_searchfield"] = "fp_focus_searchfield",
    ["fp_toggle_calculator"] = "fp_toggle_calculator",

    [CUSTOM_EVENTS.build_gui_element] = "build_gui_element",
    [CUSTOM_EVENTS.refresh_gui_element] = "refresh_gui_element"
}

local misc_timeouts = {
    fp_confirm_dialog = 20,
    fp_confirm_gui = 20,
    fp_refresh_production = 20
}

-- ** SPECIAL HANDLERS **
local special_misc_handlers = {}

special_misc_handlers.on_gui_opened = (function(event)
    -- This should only fire when a UI not associated with FP is opened, so FP's dialogs can close properly
    return (event.gui_type ~= defines.gui_type.custom or not event.element or event.element.tags.mod ~= "fp")
end)


local misc_event_cache = {}
-- Compile the list of misc handlers
for _, listener in pairs(event_listeners) do
    if listener.misc then
        for event_name, handler in pairs(listener.misc) do
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
    local string_name = misc_identifier_map[event_name]
    local event_handlers = misc_event_cache[string_name]
    if not event_handlers then return end  -- make sure the given event is even handled

    -- Guard against an event being called before the player is initialized
    if not storage.players[event.player_index] then return end

    -- We'll assume every one of the events has a player attached
    local player = game.get_player(event.player_index)   ---@cast player -nil

    -- Close context menu on any keyboard shortcut
    if event.input_name then modal_dialog.close_context_menu(player) end

    -- Check if the action is allowed to be carried out by rate limiting
    if util.actions.rate_limited(player, event.tick, event_name, event_handlers.timeout) then return end

    -- If a special handler is set, it needs to return true before proceeding with the registered handlers
    local special_handler = event_handlers.special_handler
    if special_handler and special_handler(event) == false then return end

    for _, registered_handler in pairs(event_handlers.registered_handlers) do
        registered_handler(player, event)  -- send actual event
    end

    -- Only refresh messages if this event was a keyboard shortcut
    if event.input_name then util.messages.refresh(player) end
end

-- Register all the misc events from the identifier map
for event_id, _ in pairs(misc_identifier_map) do script.on_event(event_id, handle_misc_event) end


-- ** GLOBAL HANDLERS **
-- In some situations, you need to be able to refer to a function indirectly by string name.
-- As functions can't be stored in storage, these need to be collected and stored in a central placem
-- so code that wants to call them knows where to find them. This collects and stores these functions.
for _, listener in pairs(event_listeners) do
    if listener.global then
        for name, handler in pairs(listener.global) do
            GLOBAL_HANDLERS[name] = handler
        end
    end
end

-- These are not registered as events, instead just made available to call directly
