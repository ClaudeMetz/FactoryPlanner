require("data.classes.Collection")
require("data.classes.Item")
require("data.classes.TopLevelItem")
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
require("data.util")
require("data.calc")

margin_of_error = 1e-8  -- Margin of error for floating point calculations
devmode = true  -- Enables certain conveniences for development

-- Sets up global data structure of the mod
script.on_init(function()
    global_init()
end)

-- Prompts migrations, a GUI and prototype reload, and a validity check on all subfactories
script.on_configuration_changed(function()
    handle_configuration_change()
end)

-- Creates some lua-global tables for convenience and performance
script.on_load(function()
    run_on_load()
end)

-- Fires when a player loads into a game for the first time
script.on_event(defines.events.on_player_created, function(event)
    local player = game.get_player(event.player_index)

    -- Sets up the player_table for the new player
    update_player_table(player, global)

    -- Sets up the GUI for the new player
    player_gui_init(player)

    -- Runs setup if developer mode is active
    data_util.run_dev_config(player)
end)

-- Fires when a player is irreversibly removed from a game
script.on_event(defines.events.on_player_removed, function(event)
    -- Removes the player from the global table
    global.players[event.player_index] = nil
end)


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
    item_recipe_map = generator.item_recipe_map()
    identifier_item_map = generator.idenfifier_item_map()
    module_tier_map = generator.module_tier_map()
    sorted_objects = {
        items = generator.sorted_items(),
        recipes = generator.sorted_recipes()
    }
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
                update_calculations(player, subfactory)
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

        ui_util.message.enqueue(player, {"label.hint_tutorial"}, "hint", 5)

    else  -- existing player, only need to update
        reload_data()

        -- If any subfactories exist, select the first one
        local subfactories = Factory.get_in_order(player_table.factory, "Subfactory")
        if #subfactories > 0 then data_util.context.set_subfactory(player, subfactories[1]) end
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
    settings_table.belts_or_lanes = settings["fp_view_belts_or_lanes"].value
    settings_table.default_timescale = settings["fp_default_timescale"].value
    settings_table.round_button_numbers = settings["fp_round_button_numbers"].value
    settings_table.indicate_rounding = tonumber(settings["fp_indicate_rounding"].value)
end

-- Reloads the user preferences, incorporating previous preferences if possible
function reload_preferences(player, table)
    local preferences = global.players[player.index].preferences

    preferences.tutorial_mode = preferences.tutorial_mode or true
    preferences.ignore_barreling_recipes = preferences.ignore_barreling_recipes or false
    preferences.ignore_recycling_recipes = preferences.ignore_recycling_recipes or false
    preferences.enable_recipe_comments = preferences.enable_recipe_comments or false
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
    
    ui_state_table.modal_dialog_type = nil  -- The internal modal dialog type
    ui_state_table.selected_object = nil  -- The object relevant for a modal dialog
    ui_state_table.modal_data = nil  -- Data that can be set for a modal dialog to use
    ui_state_table.current_activity = nil  -- The current unique main dialog activity
    ui_state_table.floor_total = false  -- Whether the floor or subfactory totals are displayed
    ui_state_table.archive_open = false  -- Wether the players subfactory archive is currently open
    ui_state_table.view_state = nil  -- The state of the production views
    ui_state_table.message_queue = {}  -- The general message queue
    ui_state_table.recipe_filter_preferences = 
      {disabled = false, hidden = false}  -- The preferred state of both recipe filters
    ui_state_table.context = data_util.context.create(player)  -- The currently displayed set of data
    ui_state_table.main_dialog_dimensions = nil  -- Can only be calculated after on_init
    ui_state_table.flow_modal_dialog_height = nil  -- Will be determined when opening modal dialogs
    ui_state_table.item_picker_location = nil  -- Used to remember the item picker location
end


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

-- The context is part of the ui state, but used frequently enough to warrant a getter
function get_context(player)
    return global.players[player.index].ui_state.context
end