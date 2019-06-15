require("data.classes.Collection")
require("data.classes.Item")
require("data.classes.Factory")
require("data.classes.Subfactory")
require("data.classes.Floor")
require("data.classes.Line")
require("data.util")
require("data.generator")
require("data.loader")
require("data.calc")
require("migrations.handler")

-- Margin of error for floating poing calculations
margin_of_error = 1e-10
--devmode = true

-- Initiates all factorio-global variables
function global_init()
    global.mod_version = game.active_mods["factoryplanner"]
    global.players = {}

    -- Run through the loader without need to apply (run) it on any player
    loader.setup()
    loader.finish()
end

-- Runs through all updates that need to be made after the config changed
function handle_configuration_change()
    loader.setup()  -- Setup loader
    attempt_global_migration()  -- Migrate global

    -- Runs through all players, even new ones (those with no player_table)
    for index, player in pairs(game.players) do
        local player_table = global.players[index]

        attempt_player_table_migration(player)  -- Migrate player_table data
        update_player_table(player)  -- Create or update the player table
        loader.run(player_table)  -- Run the loader on the player

        player_gui_reset(player)  -- Destroys all existing GUI's
        player_gui_init(player)  -- Initializes some parts of the GUI
        
        -- Update validity of the whole factory (no repair yet)
        Factory.update_validity(player_table.factory, player)

        -- Update calculations in case some recipes changed
        for _, subfactory in ipairs(Factory.get_in_order(player_table.factory, "Subfactory")) do
            if subfactory.valid then update_calculations(player, subfactory) end
        end

        -- Update custom space science recipe state
        local space_tech = player.force.technologies["space-science-pack"].researched
        if space_tech then global.all_recipes[player.force.name]["fp-space-science-pack"].enabled = true end
    end

    -- Complete loader process by saving new data to global
    loader.finish()
end


-- Makes sure that the given player has a player_table and a reset gui state
function update_player_table(player)
    local function reload_data()
        reload_settings(player)  -- reloads the settings of the player
        reload_preferences(player) -- reloads and adjusts the player's preferences
        reset_ui_state(player)  -- Resets the player's UI state
    end

    local player_table = global.players[player.index]
    if player_table == nil then  -- new player
        global.players[player.index] = {}
        local player_table = global.players[player.index]
        player_table.index = player.index
        player_table.mod_version = global.mod_version

        player_table.factory = Factory.init()

        player_table.settings = {}
        player_table.preferences = {}
        player_table.ui_state = {}
        reload_data()

        -- Creates recipes if there are none for the force of this player
        global.all_recipes = generator.all_recipes(false)

        queue_message(player, {"label.hint_tutorial"}, "hint")

    else  -- existing player, only need to update
        reload_data()

        -- If any subfactories exist, select the first one
        local subfactories = Factory.get_in_order(player_table.factory, "Subfactory")
        if #subfactories > 0 then data_util.context.set_subfactory(player, subfactories[1]) end
    end
end

-- Writes the current user mod settings to their player_table
function reload_settings(player)
    -- Delete the whole table first in case a setting got removed
    global.players[player.index].settings = {}
    local settings_table = global.players[player.index].settings
    
    local settings = settings.get_player_settings(player)
    settings_table.show_gui_button = settings["fp_display_gui_button"].value
    settings_table.items_per_row = tonumber(settings["fp_subfactory_items_per_row"].value)
    settings_table.recipes_at_once = tonumber(settings["fp_floor_recipes_at_once"].value)
    settings_table.show_hints = settings["fp_show_hints"].value
    settings_table.belts_or_lanes = settings["fp_view_belts_or_lanes"].value
end

-- Reloads the user preferences, incorporating previous preferences if possible
function reload_preferences(player)
    local preferences = global.players[player.index].preferences
    preferences.ignore_barreling_recipes = preferences.ignore_barreling_recipes or false
    preferences.preferred_belt_id = preferences.preferred_belt_id or data_util.base_data.preferred_belt()
    preferences.preferred_fuel_id = preferences.preferred_fuel_id or data_util.base_data.preferred_fuel()
    preferences.default_machines = preferences.default_machines or data_util.base_data.default_machines()
end

-- (Re)sets the UI state of the given player
function reset_ui_state(player)
    -- Delete the whole table first in case ui_state parameter got removed
    global.players[player.index].ui_state = {}
    local ui_state_table = global.players[player.index].ui_state

    ui_util.recalculate_main_dialog_dimensions(player)

    ui_state_table.modal_dialog_type = nil  -- The internal modal dialog type
    ui_state_table.selected_object = nil  -- The object relevant for a modal dialog
    ui_state_table.modal_data = nil  -- Data that can be set for a modal dialog to use
    ui_state_table.current_activity = nil  -- The current unique main dialog activity
    ui_state_table.view_state = nil  -- The state of the production views
    ui_state_table.queued_message = nil  -- The next general message to be displayed
    ui_state_table.recipe_filter_preferences = 
      {disabled = false, hidden = false}  -- The preferred state of both recipe filters
    ui_state_table.context = data_util.context.create(player)  -- The currently displayed set of data
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