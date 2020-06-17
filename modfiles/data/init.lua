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
require("data.handlers.builder")
require("data.handlers.generator")
require("data.handlers.loader")
require("data.handlers.migrator")
require("data.handlers.prototyper")
require("data.handlers.remote")
require("data.calculation.interface")

init = {}

-- ** LOCAL UTIL **
-- Reloads the user preferences, incorporating previous preferences if possible
local function reload_preferences(player)
    local preferences = global.players[player.index].preferences

    preferences.pause_on_interface = preferences.pause_on_interface or false
    preferences.tutorial_mode = preferences.tutorial_mode or true
    preferences.recipe_filters = preferences.recipe_filters or {disabled = false, hidden = false}

    preferences.ignore_barreling_recipes = preferences.ignore_barreling_recipes or false
    preferences.ignore_recycling_recipes = preferences.ignore_recycling_recipes or false
    preferences.ingredient_satisfaction = preferences.ingredient_satisfaction or false
    preferences.round_button_numbers = preferences.round_button_numbers or false

    preferences.optional_production_columns = preferences.optional_production_columns or
      {["pollution"] = false, ["line_comments"] = false}

    preferences.mb_defaults = preferences.mb_defaults or
      {module = nil, beacon = nil, beacon_count = nil}

    preferences.default_prototypes = preferences.default_prototypes or {}
    preferences.default_prototypes = {
        belts = preferences.default_prototypes.belts or prototyper.defaults.get_fallback("belts"),
        beacons = preferences.default_prototypes.beacons or prototyper.defaults.get_fallback("beacons"),
        fuels = preferences.default_prototypes.fuels or prototyper.defaults.get_fallback("fuels"),
        machines = preferences.default_prototypes.machines or prototyper.defaults.get_fallback("machines")
    }
end

-- (Re)sets the UI state of the given player
local function reset_ui_state(player)
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


-- Makes sure that the given player has a player_table and a reset gui state
-- The table attribute specified what table the data should be loaded from (either global or new)
local function update_player_table(player)
    local function reload_data()
        init.reload_settings(player)  -- reloads the settings of the player
        reload_preferences(player) -- reloads and adjusts the player's preferences
        reset_ui_state(player)  -- Resets the player's UI state
    end

    local player_table = global.players[player.index]
    if player_table == nil then  -- new player
        global.players[player.index] = {}
        player_table = global.players[player.index]

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


-- Destroys all GUI's so they are loaded anew the next time they are shown
local function reset_player_gui(player)
    local screen = player.gui.screen
    local guis = {
        mod_gui.get_button_flow(player)["fp_button_toggle_interface"],
        screen["fp_frame_main_dialog"],
        screen["fp_frame_modal_dialog"],
        screen["fp_frame_modal_dialog_product"],  -- TODO remove when this dialog is added back as a cached one
        unpack(cached_dialogs)
    }

    for _, gui in pairs(guis) do
        if type(gui) == "string" then gui = screen[gui] end
        if gui ~= nil and gui.valid then gui.destroy() end
    end
end


-- Initiates all factorio-global variables
local function global_init()
    global.mod_version = game.active_mods["factoryplanner"]
    global.players = {}

    -- Run through the prototyper without the need to apply (run) it on any player
    prototyper.setup()
    prototyper.finish()

    -- Create player tables for all existing players
    for _, player in pairs(game.players) do
        update_player_table(player)
    end
end

-- Runs through all updates that need to be made after the config changed
local function handle_configuration_change()
    prototyper.setup()  -- Setup prototyper
    migrator.attempt_global_migration()  -- Migrate global

    -- Runs through all players, even new ones (those with no player_table)
    for _, player in pairs(game.players) do
        -- Migrate player_table data
        migrator.attempt_player_table_migration(player)

        -- Create or update player_table
        local player_table = update_player_table(player)

        -- Run the prototyper on the player
        prototyper.run(player_table)

        reset_player_gui(player)  -- Destroys all existing GUI's
        ui_util.mod_gui.create(player)  -- Recreates the mod-GUI
    end

    -- Complete prototyper process by saving new data to global
    prototyper.finish()

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


-- ** TOP LEVEL **
-- Writes the current user mod settings to their player_table
function init.reload_settings(player)
    local settings = settings.get_player_settings(player)
    -- Delete the whole table first in case a setting got removed
    global.players[player.index].settings = {}
    local settings_table = global.players[player.index].settings

    settings_table.show_gui_button = settings["fp_display_gui_button"].value
    settings_table.items_per_row = tonumber(settings["fp_subfactory_items_per_row"].value)
    settings_table.recipes_at_once = tonumber(settings["fp_floor_recipes_at_once"].value)
    settings_table.alt_action = settings["fp_alt_action"].value
    settings_table.default_timescale = settings["fp_default_timescale"].value
    settings_table.belts_or_lanes = settings["fp_view_belts_or_lanes"].value
    settings_table.indicate_rounding = tonumber(settings["fp_indicate_rounding"].value)
end


-- ** EVENTS **
-- Sets up global data structure of the mod
script.on_init(global_init)

-- Prompts migrations, a GUI and prototype reload, and a validity check on all subfactories
script.on_configuration_changed(handle_configuration_change)

-- Creates some lua-global tables for convenience and performance
script.on_load(loader.run)


-- Fires when a player loads into a game for the first time
script.on_event(defines.events.on_player_created, function(event)
    local player = game.get_player(event.player_index)

    -- Sets up the player_table for the new player
    update_player_table(player)

    -- Sets up the mod-GUI for the new player
    ui_util.mod_gui.create(player)

    -- Runs setup if developer mode is active
    builder.dev_config(player)
end)

-- Fires when a player is irreversibly removed from a game
script.on_event(defines.events.on_player_removed, function(event)
    -- Removes the player from the global table
    global.players[event.player_index] = nil
end)


-- ** GLOBAL UTIL **
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




-- TODO move when classes are re-done
-- Updates validity of every class specified by the classes parameter
function run_validation_updates(parent, classes)
    local valid = true
    for type, class in pairs(classes) do
        if not Collection.update_validity(parent[type], class) then
            valid = false
        end
    end
    return valid
end

-- Tries to repair every specified class, deletes them if this is unsuccessfull
function run_invalid_dataset_repair(player, parent, classes)
    for type, class in pairs(classes) do
        Collection.repair_invalid_datasets(parent[type], player, class, parent)
    end
end