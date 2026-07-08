-- Assembles event handlers from all the relevant files to register them

local event_listener_names = {
    "backend.init", "backend.calculation.solver",
    "ui.base.main_dialog", "ui.base.compact_dialog", "ui.base.modal_dialog", "ui.base.calculator_dialog",
    "ui.components.module_configurator", "ui.components.item_views",
    "ui.dialogs.beacon_dialog", "ui.dialogs.machine_dialog", "ui.dialogs.picker_dialog",
    "ui.dialogs.porter_dialog", "ui.dialogs.preferences_dialog", "ui.dialogs.recipe_dialog",
    "ui.dialogs.factory_dialog", "ui.dialogs.utility_dialog", "ui.dialogs.item_dialog",
    "ui.main.title_bar", "ui.main.district_info", "ui.main.factory_list", "ui.main.production_bar",
    "ui.main.districts_box", "ui.main.item_boxes", "ui.main.production_box", "ui.main.production_table",
    "ui.main.production_handler"
}

---@class ListenerDefinitions
---@field gui GUIListenerDefinition?
---@field player table<string, PlayerEventHandler>?
---@field game table<string, GameEventHandler>?
---@field dialog ModalDialogEvent?
---@field global table<string, fun(...)>?

---@alias GUIListenerDefinition table<string, GUIEventDefinition[]>

local event_listeners = {}  ---@type ListenerDefinitions[]
for _, listener_path in ipairs(event_listener_names) do
    for _, listener in pairs(require(listener_path)--[[@as ListenerDefinitions]]) do
        table.insert(event_listeners, listener)
    end
end


-- ** GUI EVENTS **
-- These events go out to the single handler that registered for it.
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
}  ---@type table<defines.events, string>

local gui_timeouts = {
    on_gui_click = 2,
    on_gui_confirmed = 20
}  ---@type table<string, MapTick>

local special_gui_handlers = {}

special_gui_handlers.on_gui_closed = (function(event, _, _)
    return (event.gui_type == defines.gui_type.custom and event.element.visible)
end)

special_gui_handlers.on_gui_confirmed = (function(_, player, action_name)
    if action_name then return true end  -- run the standard handler if one is found

    -- Otherwise, close the currently open modal dialog if possible
    if lib.globals.ui_state(player).modal_dialog_type ~= nil then
        lib.gui.close_dialog(player, "submit")
    end
    return false
end)

---@class GUIEventDefinition
---@field name string
---@field handler GUIEventHandler | GUIActionEventHandler
---@field actions_table table<string, GUIActionDefinition>?
---@field timeout MapTick?

---@alias GUIEventHandler fun(player: LuaPlayer, tags: Tags, event: EventData)
---@alias GUIActionEventHandler fun(player: LuaPlayer, tags: Tags, action: string)

---@class GUIActionDefinition
---@field shortcut string?
---@field limitations ActionLimitations?
---@field show boolean?

-- Compile and format the list of GUI actions
for _, listener in pairs(event_listeners) do
    if not listener.gui then goto continue end
    for event_name, actions in pairs(listener.gui) do
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
                        shortcut_string = lib.actions.shortcut_string(modifier_action.shortcut),
                        show = modifier_action.show
                    }
                    table.insert(action_table.actions, action_details)

                    if modifier_action.shortcut then
                        action_table.shortcuts[modifier_action.shortcut] = action_details
                    end
                end
                action_table.tooltip = lib.actions.generate_tooltip(action_table.actions)
            end

            if MODIFIER_ACTIONS[action.name] then error("Duplicate action: " .. action.name) end
            MODIFIER_ACTIONS[action.name] = action_table
        end
    end
    ::continue::
end


local mouse_click_map = {
    [defines.mouse_button_type.left] = "left",
    [defines.mouse_button_type.right] = "right",
    [defines.mouse_button_type.middle] = "middle"
}

---@param event EventData.on_gui_click
---@return string
local function convert_click_to_string(event)
    local modifier_click = mouse_click_map[event.button]  ---@type string
    if event.shift then modifier_click = "shift-" .. modifier_click end
    if event.alt then modifier_click = "alt-" .. modifier_click end
    if event.control then modifier_click = "control-" .. modifier_click end
    return modifier_click
end

---@class GUIEventTable
---@field handler GUIEventHandler | GUIActionEventHandler
---@field actions GUIActionTable
---@field shortcuts table<string, GUIActionTable>
---@field tooltip LocalisedString
---@field timeout MapTick

---@class GUIActionTable
---@field name string
---@field limitations ActionLimitations
---@field shortcut_string LocalisedString
---@field show boolean?

---@class GUIEventData: EventData
---@field player_index PlayerIndex
---@field element LuaGuiElement?

---@param event GUIEventData
local function handle_gui_event(event)
    if not event.element then return end

    -- GUI events always have an associated player
    local player = game.get_player(event.player_index)  ---@cast player -nil

    -- Guard against an event being called before the player is initialized
    if not storage.players[event.player_index] then return end

    local tags = event.element.tags

    -- Close an open context menu on any GUI click
    if event.name == defines.events.on_gui_click and
            not tags.on_gui_click ~= "choose_context_action" then
        modal_dialog.close_context_menu(player)
    end

    if tags.mod ~= "fp" then return end

    -- The event table actually contains its identifier, not its name
    local event_name = gui_identifier_map[event.name]  ---@as string
    local action_name = tags[event_name]  ---@as string?

    -- If a special handler is set, it needs to return true before proceeding with the registered handlers
    local special_handler = special_gui_handlers[event_name]
    if special_handler and special_handler(event, player, action_name) == false then return end

    -- Special handlers need to run even without an action handler, so we
    -- wait until this point to check whether there is an associated action
    if not action_name then return end  -- meaning this event type has no action on this element
    local action_table = MODIFIER_ACTIONS[action_name] or {}

    -- Check if rate limiting allows this action to proceed
    if lib.actions.rate_limited(player, event.tick, action_name, action_table.timeout) then return end

    -- Special modifier handling for on_gui_click if configured
    if event_name == "on_gui_click" and action_table.actions then
        local click_event = event  ---@as EventData.on_gui_click
        local click = convert_click_to_string(click_event)

        if click == "right" then
            modal_dialog.open_context_menu(player, tags, action_name,
                action_table.actions, click_event.cursor_display_location)
        else
            local modifier_action = action_table.shortcuts[click]
            if not modifier_action then return end  -- meaning the used modifiers do not have an associated action

            local active_limitations = lib.actions.current_limitations(player)
            if lib.actions.allowed(modifier_action.limitations, active_limitations) then
                action_table.handler(player, tags, modifier_action.name)
            end
        end
    else
        action_table.handler(player, tags, event)  -- gets event as third parameter
    end

    -- Only refresh messages if the event wasn't a hover event
    if event_name ~= "on_gui_hover" and event_name ~= "on_gui_leave" then lib.messages.refresh(player) end
end

for event_id, _ in pairs(gui_identifier_map) do script.on_event(event_id, handle_gui_event) end


-- ** PLAYER EVENTS **
-- These events go out to every handler that has subscribed to it by ID or name.
local player_identifier_map = {
    -- Standard events
    [defines.events.on_gui_opened] = "on_gui_opened",
    [defines.events.on_player_display_resolution_changed] = "on_player_display_resolution_changed",
    [defines.events.on_player_display_scale_changed] = "on_player_display_scale_changed",
    [defines.events.on_player_selected_area] = "on_player_selected_area",
    [defines.events.on_player_cursor_stack_changed] = "on_player_cursor_stack_changed",
    [defines.events.on_player_main_inventory_changed] = "on_player_main_inventory_changed",
    [defines.events.on_lua_shortcut] = "on_lua_shortcut",

    -- Translation events
    [defines.events.on_player_joined_game] = "on_player_joined_game",
    [defines.events.on_player_locale_changed] = "on_player_locale_changed",
    [defines.events.on_string_translated] = "on_string_translated",
    [lib.translator.on_player_dictionaries_ready] = "on_player_dictionaries_ready",

    -- Keyboard shortcuts
    ["fp_toggle_interface"] = "fp_toggle_interface",
    ["fp_toggle_compact_view"] = "fp_toggle_compact_view",
    ["fp_toggle_pause"] = "fp_toggle_pause",
    ["fp_refresh_production"] = "fp_refresh_production",
    ["fp_up_floor"] = "fp_up_floor",
    ["fp_top_floor"] = "fp_top_floor",
    ["fp_toggle_fold_out_subfloors"] = "fp_toggle_fold_out_subfloors",
    ["fp_cycle_production_views"] = "fp_cycle_production_views",
    ["fp_reverse_cycle_production_views"] = "fp_reverse_cycle_production_views",
    ["fp_confirm_dialog"] = "fp_confirm_dialog",
    ["fp_confirm_gui"] = "fp_confirm_gui",
    ["fp_focus_searchfield"] = "fp_focus_searchfield",
    ["fp_toggle_calculator"] = "fp_toggle_calculator"
}  ---@type table<(defines.events | string), string>

local player_timeouts = {
    fp_refresh_production = 20,
    fp_confirm_dialog = 20,
    fp_confirm_gui = 20
}  ---@type table<string, MapTick>

local special_player_handlers = {}

special_player_handlers.on_gui_opened = (function(event)
    -- This should only fire when a UI not associated with FP is opened, so FP's dialogs can close properly
    return (event.gui_type ~= defines.gui_type.custom or not event.element or event.element.tags.mod ~= "fp")
end)

---@alias PlayerEventHandler fun(player: LuaPlayer, event: PlayerEventData)

local player_event_cache = {}  ---@type table<string, PlayerEventTable>
-- Compile the list of player handlers
for _, listener in pairs(event_listeners) do
    if not listener.player then goto continue end
    for event_name, handler in pairs(listener.player) do
        player_event_cache[event_name] = player_event_cache[event_name] or {
            registered_handlers = {},
            special_handler = special_player_handlers[event_name],
            timeout = player_timeouts[event_name]
        }

        table.insert(player_event_cache[event_name].registered_handlers, handler)
    end
    ::continue::
end

---@class PlayerEventTable
---@field registered_handlers PlayerEventHandler[]
---@field special_handler fun(event: PlayerEventData)?
---@field timeout MapTick?

---@class PlayerEventData: EventData
---@field player_index PlayerIndex
---@field input_name string?

---@param event PlayerEventData
local function handle_player_event(event)
    local event_name = event.input_name or event.name
    local string_name = player_identifier_map[event_name] or event_name
    local event_handlers = player_event_cache[string_name]
    if not event_handlers then return end  -- make sure the given event is even handled

    -- Guard against an event being called before the player is initialized
    if not storage.players[event.player_index] then return end
    local player = game.get_player(event.player_index)   ---@cast player -nil

    -- Close context menu on any keyboard shortcut
    if event.input_name then modal_dialog.close_context_menu(player) end

    -- Check if the action is allowed to be carried out by rate limiting
    if lib.actions.rate_limited(player, event.tick, event_name, event_handlers.timeout) then return end

    -- If a special handler is set, it needs to return true before proceeding with the registered handlers
    if event_handlers.special_handler and event_handlers.special_handler(event) == false then return end

    ::player_created::
    for _, registered_handler in pairs(event_handlers.registered_handlers) do
        registered_handler(player, event)  -- send actual event
    end

    -- Only refresh messages if this event was a keyboard shortcut
    if event.input_name then lib.messages.refresh(player) end
end

for event_id, _ in pairs(player_identifier_map) do script.on_event(event_id, handle_player_event) end


-- ** GAME EVENTS **
-- These events go out to every handler that has subscribed to it by ID.
local game_identifier_map = {
    [defines.events.on_player_created] = "on_player_created",
    [defines.events.on_player_removed] = "on_player_removed",
    [defines.events.on_tick] = "on_tick",
    [defines.events.on_singleplayer_init] = "on_singleplayer_init",
    [defines.events.on_multiplayer_init] = "on_multiplayer_init",
    [defines.events.on_research_finished] = "on_research_finished"
}  ---@type table<defines.events, string>

---@alias GameEventHandler fun(event: EventData)

local game_event_cache = {}  ---@type table<string, GameEventHandler[]>
-- Compile the list of game handlers
for _, listener in pairs(event_listeners) do
    if listener.game then
        for event_name, handler in pairs(listener.game) do
            game_event_cache[event_name] = game_event_cache[event_name] or {}
            table.insert(game_event_cache[event_name], handler)
        end
    end
end

---@param event EventData
local function handle_game_event(event)
    local event_name = game_identifier_map[event.name]
    local event_handlers = game_event_cache[event_name]
    if not event_handlers then return end  -- make sure the given event is even handled

    for _, registered_handler in pairs(event_handlers) do
        registered_handler(event)  -- send actual event
    end
end

for event_id, _ in pairs(game_identifier_map) do script.on_event(event_id, handle_game_event) end


-- ** DIALOG EVENTS **
---@class ModalDialogEvent
---@field dialog string
---@field metadata fun(modal_data: ModalData): ModalDialogSettings
---@field early_abort_check? fun(player: LuaPlayer, modal_data: ModalData): boolean
---@field open fun(player: LuaPlayer, modal_data: ModalData)
---@field close? fun(player: LuaPlayer, action: GUICloseAction)

-- These custom events handle opening and closing modal dialogs
local dialog_event_cache = {}  ---@type table<string, ModalDialogEvent>
-- Compile the list of dialog actions
for _, listener in pairs(event_listeners) do
    if listener.dialog then
        dialog_event_cache[listener.dialog.dialog] = listener.dialog
    end
end

---@param base any
---@param overrides any
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

-- Make modal dialog actions available as global functions
GLOBAL_HANDLERS["open_modal_dialog"] = (function(player, metadata)
    local modal_dialog_type = lib.globals.ui_state(player).modal_dialog_type
    if modal_dialog_type ~= nil then return end

    local listener = dialog_event_cache[metadata.dialog]

    if listener.metadata ~= nil then  -- collect additional metadata
        local additional_metadata = listener.metadata(metadata.modal_data)
        apply_metadata_overrides(metadata, additional_metadata)
    end

    modal_dialog.enter(player, metadata, listener.open, listener.early_abort_check)
end)

GLOBAL_HANDLERS["close_modal_dialog"] = (function(player, action, skip_opened)
    local modal_dialog_type = lib.globals.ui_state(player).modal_dialog_type
    if modal_dialog_type == nil then return end

    local listener = dialog_event_cache[modal_dialog_type]
    modal_dialog.exit(player, action, skip_opened, listener.close)
end)

-- Save special GUI events as pseudo-events
GLOBAL_HANDLERS["run_gui_build"] = handle_player_event
GLOBAL_HANDLERS["run_gui_refresh"] = handle_player_event


-- ** GLOBAL HANDLERS **
-- In some situations, you need to be able to refer to a function indirectly by string name.
-- As functions can't be stored in storage, these need to be collected and stored in a central place
-- so code that wants to call them knows where to find them. This collects and stores these functions.
for _, listener in pairs(event_listeners) do
    if listener.global then
        for name, handler in pairs(listener.global) do
            GLOBAL_HANDLERS[name] = handler
        end
    end
end

-- These are not registered as events, instead just made available to call directly
