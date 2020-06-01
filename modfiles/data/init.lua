require("data.util")
require("data.classes.Collection")
require("data.classes.Item")
require("data.classes.Fuel")
require("data.classes.Recipe")
require("data.classes.Machine")
require("data.classes.Module")
require("data.classes.Beacon")
require("data.classes.Factory")
require("data.classes.Subfactory")
require("data.classes.Floor")
require("data.classes.Line")
require("data.handlers.migrator")
require("data.handlers.generator")
require("data.handlers.loader")
require("data.handlers.builder")
require("data.handlers.remote")
require("data.calculation.interface")

-- Initiates all factorio-global variables
function global_init()
    global.mod_version = game.active_mods["factoryplanner"]
    global.players = {}
    
    -- Run through the loader without the need to apply (run) it on any player
    loader.setup()
    loader.finish()

    -- Create player tables for all existing players
    for index, player in pairs(game.players) do
        update_player_table(player, global)
    end
end

-- Central place to consolidate what should run on_load and on_init
function run_on_load()
    -- Register the RecipeBook event to re-open the main dialog after hitting its back-button
    if remote.interfaces["RecipeBook"] ~= nil then
        script.on_event(remote.call("RecipeBook", "reopen_source_event"), function(event)
            if event.source_data.mod_name == "factoryplanner" then
                toggle_main_dialog(game.get_player(event.player_index))
            end
        end)
    end

    -- Re-register conditional on_nth_tick events
    for _, player_table in pairs(global.players or {}) do
        local last_action = player_table.ui_state.last_action
        if last_action and table_size(last_action) > 0 and last_action.nth_tick ~= nil then
            local rate_limiting_event = ui_util.rate_limiting_events[last_action.event_name]

            script.on_nth_tick(last_action.nth_tick, function(event)
                rate_limiting_event.handler(last_action.element)
                last_action.nth_tick = nil
                last_action.element = nil
                script.on_nth_tick(event.nth_tick, nil)
            end)
        end
    end

    -- Create lua-global tables to pre-cache relevant tables
    ordered_recipe_groups = generator.ordered_recipe_groups()
    recipe_maps = {
        produce = generator.product_recipe_map(),
        consume = generator.ingredient_recipe_map()
    }

    sorted_items = generator.sorted_items()
    identifier_item_map = generator.identifier_item_map()
    
    module_tier_map = generator.module_tier_map()

    top_crafting_machine_sprite = generator.find_crafting_machine_sprite()
end

-- Runs through all updates that need to be made after the config changed
function handle_configuration_change()
    loader.setup()  -- Setup loader
    attempt_global_migration()  -- Migrate global

    -- Runs through all players, even new ones (those with no player_table)
    for index, player in pairs(game.players) do
        -- Migrate player_table data
        attempt_player_table_migration(player)
        
        -- Create or update player_table
        local player_table = update_player_table(player, new)

        -- Run the loader on the player
        loader.run(player_table)

        player_gui_reset(player)  -- Destroys all existing GUI's
        player_gui_init(player)  -- Initializes some parts of the GUI
    end

    -- Complete loader process by saving new data to global
    loader.finish()

    -- Update factory and archive calculations in case some numbers changed
    local factories = {"factory", "archive"}
    for index, player in pairs(game.players) do
        local player_table = global.players[index]
        for _, factory_name in pairs(factories) do
            for _, subfactory in ipairs(Factory.get_in_order(player_table[factory_name], "Subfactory")) do
                calculation.update(player, subfactory, false)
            end
        end
    end
end


-- Makes sure that the given player has a player_table and a reset gui state
-- The table attribute specified what table the data should be loaded from (either global or new)
function update_player_table(player, table)
    local function reload_data()
        reload_settings(player)  -- reloads the settings of the player
        reload_preferences(player, table) -- reloads and adjusts the player's preferences
        reset_ui_state(player)  -- Resets the player's UI state
    end

    local player_table = global.players[player.index]
    if player_table == nil then  -- new player
        global.players[player.index] = {}
        local player_table = global.players[player.index]

        player_table.mod_version = global.mod_version
        player_table.index = player.index

        player_table.factory = Factory.init()
        player_table.archive = Factory.init()

        player_table.settings = {}
        player_table.preferences = {}
        player_table.ui_state = {}
        reload_data()

        ui_util.message.enqueue(player, {"fp.hint_tutorial"}, "hint", 5)

    else  -- existing player, only need to update
        reload_data()

        -- If any subfactories exist, select the first one
        local subfactories = Factory.get_in_order(player_table.factory, "Subfactory")
        if #subfactories > 0 then ui_util.context.set_subfactory(player, subfactories[1]) end
    end
    
    return player_table
end

-- Writes the current user mod settings to their player_table
function reload_settings(player)
    local settings = settings.get_player_settings(player)
    -- Delete the whole table first in case a setting got removed
    global.players[player.index].settings = {}
    local settings_table = global.players[player.index].settings
    
    settings_table.show_gui_button = settings["fp_display_gui_button"].value
    settings_table.pause_on_interface = settings["fp_pause_on_interface"].value
    settings_table.items_per_row = tonumber(settings["fp_subfactory_items_per_row"].value)
    settings_table.recipes_at_once = tonumber(settings["fp_floor_recipes_at_once"].value)
    settings_table.default_timescale = settings["fp_default_timescale"].value
    settings_table.belts_or_lanes = settings["fp_view_belts_or_lanes"].value
    settings_table.indicate_rounding = tonumber(settings["fp_indicate_rounding"].value)
end

-- Reloads the user preferences, incorporating previous preferences if possible
function reload_preferences(player, table)
    local preferences = global.players[player.index].preferences

    preferences.tutorial_mode = preferences.tutorial_mode or true
    preferences.recipe_filters = preferences.recipe_filters or {disabled = false, hidden = false}

    preferences.alt_action = remote_actions.util.validate_alt_action(preferences.alt_action)
    preferences.mb_defaults = preferences.mb_defaults or
      {module = nil, beacon = nil, beacon_count = nil}

    preferences.ignore_barreling_recipes = preferences.ignore_barreling_recipes or false
    preferences.ignore_recycling_recipes = preferences.ignore_recycling_recipes or false
    preferences.ingredient_satisfaction = preferences.ingredient_satisfaction or false
    preferences.round_button_numbers = preferences.round_button_numbers or false
    
    preferences.optional_production_columns = preferences.optional_production_columns or 
      {["pollution"] = false, ["line_comments"] = false}

    preferences.preferred_belt = preferences.preferred_belt or data_util.base_data.preferred_belt(table)
    preferences.preferred_fuel = preferences.preferred_fuel or data_util.base_data.preferred_fuel(table)
    preferences.preferred_beacon = preferences.preferred_beacon or data_util.base_data.preferred_beacon(table)
    preferences.default_machines = preferences.default_machines or data_util.base_data.default_machines(table)
end

-- (Re)sets the UI state of the given player
function reset_ui_state(player)
    -- Delete the whole table first in case ui_state parameter got removed
    global.players[player.index].ui_state = {}
    local ui_state_table = global.players[player.index].ui_state
    
    ui_state_table.main_dialog_dimensions = nil  -- Can only be calculated after on_init
    ui_state_table.current_activity = nil  -- The current unique main dialog activity
    ui_state_table.last_action = {}  -- The last user action, used for rate limiting
    ui_state_table.view_state = nil  -- The state of the production views
    ui_state_table.message_queue = {}  -- The general message queue
    ui_state_table.context = ui_util.context.create(player)  -- The currently displayed set of data
    
    ui_state_table.modal_dialog_type = nil  -- The internal modal dialog type
    ui_state_table.modal_data = nil  -- Data that can be set for a modal dialog to use
    
    ui_state_table.flags = {
        floor_total = false,  -- Whether the floor or subfactory totals are displayed
        archive_open = false,  -- Wether the players subfactory archive is currently open
        selection_mode = false  -- Whether the player is currently using a selector
    }
end


-- Sets up global data structure of the mod
script.on_init(global_init)

-- Prompts migrations, a GUI and prototype reload, and a validity check on all subfactories
script.on_configuration_changed(handle_configuration_change)

-- Creates some lua-global tables for convenience and performance
script.on_load(run_on_load)


-- Fires when a player loads into a game for the first time
script.on_event(defines.events.on_player_created, function(event)
    local player = game.get_player(event.player_index)

    -- Sets up the player_table for the new player
    update_player_table(player, global)

    -- Sets up the GUI for the new player
    player_gui_init(player)

    -- Runs setup if developer mode is active
    builder.dev_config(player)
end)

-- Fires when a player is irreversibly removed from a game
script.on_event(defines.events.on_player_removed, function(event)
    -- Removes the player from the global table
    global.players[event.player_index] = nil
end)


-- Returns the player table for the given player
function get_table(player)
    return global.players[player.index]
end

function get_settings(player)
    return global.players[player.index].settings
end

function get_preferences(player)
    return global.players[player.index].preferences
end

function get_ui_state(player)
    return global.players[player.index].ui_state
end

function get_context(player)
    return global.players[player.index].ui_state.context
end

function get_modal_data(player)
    return global.players[player.index].ui_state.modal_data
end

function get_flags(player)
    return global.players[player.index].ui_state.flags
end