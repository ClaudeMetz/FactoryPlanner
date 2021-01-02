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

require("data.handlers.generator")
require("data.handlers.loader")
require("data.handlers.migrator")
require("data.handlers.prototyper")
require("data.handlers.remote")

require("data.calculation.interface")

init = {}

-- ** LOCAL UTIL **
local function reload_settings(player)
    -- Writes the current user mod settings to their player_table, for read-performance
    local settings = settings.get_player_settings(player)
    local settings_table = {}

    local timescale_to_number = {one_second = 1, one_minute = 60, one_hour = 3600}

    settings_table.show_gui_button = settings["fp_display_gui_button"].value
    settings_table.products_per_row = tonumber(settings["fp_products_per_row"].value)
    settings_table.subfactory_list_rows = tonumber(settings["fp_subfactory_list_rows"].value)
    settings_table.alt_action = settings["fp_alt_action"].value
    settings_table.default_timescale = timescale_to_number[settings["fp_default_timescale"].value]
    settings_table.belts_or_lanes = settings["fp_view_belts_or_lanes"].value
    settings_table.prefer_matrix_solver = settings["fp_prefer_matrix_solver"].value

    global.players[player.index].settings = settings_table
end

local function reload_preferences(player)
    -- Reloads the user preferences, incorporating previous preferences if possible
    local preferences = global.players[player.index].preferences

    preferences.pause_on_interface = preferences.pause_on_interface or false
    preferences.tutorial_mode = preferences.tutorial_mode or true
    preferences.utility_scopes = preferences.utility_scopes or {components = "Subfactory"}
    preferences.recipe_filters = preferences.recipe_filters or {disabled = false, hidden = false}

    preferences.ignore_barreling_recipes = preferences.ignore_barreling_recipes or false
    preferences.ignore_recycling_recipes = preferences.ignore_recycling_recipes or false
    preferences.ingredient_satisfaction = preferences.ingredient_satisfaction or false
    preferences.round_button_numbers = preferences.round_button_numbers or false

    preferences.toggle_column = preferences.toggle_column or false
    preferences.done_column = preferences.done_column or false
    preferences.pollution_column = preferences.pollution_column or false
    preferences.line_comment_column = preferences.line_comment_column or false

    preferences.mb_defaults = preferences.mb_defaults or
      {machine = nil, machine_secondary = nil, beacon = nil, beacon_count = nil}

    preferences.default_prototypes = preferences.default_prototypes or {}
    preferences.default_prototypes = {
        belts = preferences.default_prototypes.belts or prototyper.defaults.get_fallback("belts"),
        beacons = preferences.default_prototypes.beacons or prototyper.defaults.get_fallback("beacons"),
        wagons = preferences.default_prototypes.wagons or prototyper.defaults.get_fallback("wagons"),
        fuels = preferences.default_prototypes.fuels or prototyper.defaults.get_fallback("fuels"),
        machines = preferences.default_prototypes.machines or prototyper.defaults.get_fallback("machines")
    }
end

local function reset_ui_state(player)
    local ui_state_table = {}

    ui_state_table.main_dialog_dimensions = nil  -- Can only be calculated after on_init
    ui_state_table.last_action = nil  -- The last user action (used for rate limiting)
    ui_state_table.view_states = nil  -- The state of the production views
    ui_state_table.message_queue = {}  -- The general message queue
    ui_state_table.main_elements = {}  -- References to UI elements in the main interface
    ui_state_table.context = ui_util.context.create(player)  -- The currently displayed set of data

    ui_state_table.modal_dialog_type = nil  -- The internal modal dialog type
    ui_state_table.modal_data = nil  -- Data that can be set for a modal dialog to use
    ui_state_table.queued_dialog_settings = nil  -- Info on dialog to open after the current one closes

    ui_state_table.flags = {
        floor_total = false,  -- Whether the floor or subfactory totals are displayed
        archive_open = false,  -- Wether the players subfactory archive is currently open
        selection_mode = false,  -- Whether the player is currently using a selector
        recalculate_on_subfactory_change = false  -- Whether calculations should re-run
    }

    -- The UI table gets replaced because the whole interface is reset
    global.players[player.index].ui_state = ui_state_table
end


-- Makes sure that the given player has a player_table and a reset gui state
local function update_player_table(player)
    local function reload_data()
        reload_settings(player)  -- reloads the settings of the player
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

        title_bar.enqueue_message(player, {"fp.hint_tutorial"}, "hint", 5, false)

    else  -- existing player, only need to update
        reload_data()

        -- If any subfactories exist, select the first one
        local subfactories = Factory.get_in_order(player_table.factory, "Subfactory")
        if #subfactories > 0 then ui_util.context.set_subfactory(player, subfactories[1]) end
    end

    return player_table
end

-- Destroys all GUIs so they are loaded anew the next time they are shown
local function reset_player_gui(player)
    local mod_gui_button = mod_gui.get_button_flow(player)["fp_button_toggle_interface"]
    if mod_gui_button then mod_gui_button.destroy() end

    -- All mod frames
    for _, gui_element in pairs(player.gui.screen.children) do
        if gui_element.valid and gui_element.get_mod() == "factoryplanner" then
            gui_element.destroy()
        end
    end
end


local function global_init()
    -- Set up a new save for development if necessary
    local freeplay = remote.interfaces["freeplay"]
    if DEVMODE and freeplay then  -- Disable freeplay popup-message
        if freeplay["set_skip_intro"] then remote.call("freeplay", "set_skip_intro", true) end
        if freeplay["set_disable_crashsite"] then remote.call("freeplay", "set_disable_crashsite", true) end
    end

    -- Initiates all factorio-global variables
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

-- Prompts migrations, a GUI and prototype reload, and a validity check on all subfactories
local function handle_configuration_change()
    prototyper.setup()  -- Setup prototyper
    migrator.migrate_global()  -- Migrate global

    -- Runs through all players, even new ones (those with no player_table)
    for _, player in pairs(game.players) do
        -- Migrate player_table data
        migrator.migrate_player_table(player)

        -- Create or update player_table
        local player_table = update_player_table(player)

        -- Migrate the default prototypes for the player
        prototyper.run(player_table)

        -- Update the validity of the entire factory and archive
        Collection.validate_datasets(player_table.factory.Subfactory)
        Collection.validate_datasets(player_table.archive.Subfactory)

        reset_player_gui(player)  -- Destroys all existing GUI's
        ui_util.mod_gui.create(player)  -- Recreates the mod-GUI
    end

    -- Complete prototyper process by saving new data to global
    prototyper.finish()

    -- Update factory and archive calculations in case some numbers changed
    for index, player in pairs(game.players) do
        local player_table = global.players[index]
        for _, factory_name in pairs{"factory", "archive"} do
            for _, subfactory in ipairs(Factory.get_in_order(player_table[factory_name], "Subfactory")) do
                calculation.update(player, subfactory)
            end
        end
    end
end


-- ** TOP LEVEL EVENTS **
script.on_init(global_init)

script.on_configuration_changed(handle_configuration_change)

script.on_load(loader.run)


-- ** PLAYER DATA EVENTS **
script.on_event(defines.events.on_player_created, function(event)
    local player = game.get_player(event.player_index)

    -- Sets up the player_table for the new player
    update_player_table(player)

    -- Sets up the mod-GUI for the new player
    ui_util.mod_gui.create(player)

    -- Add the subfactories that are handy for development
    if DEVMODE then data_util.add_subfactories_by_string(player, DEV_EXPORT_STRING, false) end
end)

script.on_event(defines.events.on_player_removed, function(event)
    global.players[event.player_index] = nil
end)


-- Fires when mods settings change to incorporate them
script.on_event(defines.events.on_runtime_mod_setting_changed, function(event)
    if event.setting_type == "runtime-per-user" then  -- this mod only has per-user settings
        local player = game.get_player(event.player_index)
        reload_settings(player)

        if event.setting == "fp_display_gui_button" then
            ui_util.mod_gui.toggle(player)

        elseif event.setting == "fp_products_per_row" or
          event.setting == "fp_subfactory_list_rows" or
          event.setting == "fp_alt_action" then
            main_dialog.rebuild(player, false)

        elseif event.setting == "fp_view_belts_or_lanes" then
            data_util.update_all_product_definitions(player)
            main_dialog.rebuild(player, false)

        end
    end
end)


-- ** COMMANDS **
-- Allows running the config_changed function manually, to reset stuff (shouldn't be needed actually)
commands.add_command("fp-reset-prototypes", {"command-help.fp_reset_prototypes"}, handle_configuration_change)