require("data.classes.Collection")
require("data.classes.Item")
require("data.classes.Factory")
require("data.classes.Subfactory")
require("data.classes.Floor")
require("data.classes.Line")
require("data.util")
require("data.generator")
require("data.calc")
require("migrations.handler")


-- Initiates all factorio-global variables
function global_init()
    global.mod_version = game.active_mods["factoryplanner"]

    global.players = {}

    global.all_items = generator.all_items()
    -- Recipes are generated on player init because they depend on their force
    global.all_machines = generator.all_machines()

    --global.devmode = true
    global.margin_of_error = 1e-10
end

-- Creates and initiates a new player in the database if he doesn't exist yet
function player_init(player)
    if global.players[player.index] == nil then
        global.players[player.index] = {}
        local player_table = global.players[player.index]

        player_table.factory = Factory.init()
        player_table.main_dialog_dimensions = {width = nil, height = 1000}

        player_table.settings = {}
        reload_settings(player)

        player_table.default_machines = {}
        data_util.machines.update_default(player)

        -- Creates recipes if there are none for the force of this player
        global.all_recipes = generator.all_recipes(false)

       reset_gui_state(player)
       queue_message(player, {"label.hint_tutorial"}, "hint")
    end
end

-- Resets the GUI state of the given player, if he exists
function player_reset(player)
    local player_table = global.players[player.index]
    if player_table ~= nil then
        reset_gui_state(player)

        -- If any subfactories exist, select the first one
        local subfactories = Factory.get_in_order(player_table.factory, "Subfactory")
        if #subfactories > 0 then data_util.context.set_subfactory(player, subfactories[1]) end
    end
end

-- Removes given player irreversibly from the database
function player_remove(player)
    global.players[player.index] = nil
end

-- Writes the current user mod settings to their player_table
function reload_settings(player)
    local settings = settings.get_player_settings(player)
    local settings_table = global.players[player.index].settings

    settings_table.items_per_row = tonumber(settings["fp_subfactory_items_per_row"].value)
    settings_table.show_hints = settings["fp_show_hints"].value
    settings_table.show_disabled_recipe = settings["fp_show_disabled_recipe"].value
end

-- (Re)sets the GUI state of the given player
function reset_gui_state(player)
    local player_table = global.players[player.index]

    player_table.modal_dialog_type = nil  -- The internal modal dialog type
    player_table.selected_object = nil  -- The object relevant for a modal dialog
    player_table.modal_data = nil  -- Data that can be set for a modal dialog to use
    player_table.current_activity = nil  -- The current unique main dialog activity
    player_table.queued_message = nil  -- The next general message to be displayed
    player_table.context = data_util.context.create(player)  -- The currently displayed set of data
end

-- Runs through all updates that need to be made after the config changed
function handle_configuration_change()
    global.mod_version = game.active_mods["factoryplanner"]

    global.all_items = generator.all_items()
    global.all_recipes = generator.all_recipes(true)
    global.all_machines = generator.all_machines()

    for index, player in pairs(game.players) do
        local space_tech = player.force.technologies["space-science-pack"].researched
        if space_tech then global.all_recipes[player.force.name]["fp-space-science-pack"].enabled = true end

        player_reset(player)
        player_gui_reset(player)

        player_init(player)
        player_gui_init(player)

        local factory = global.players[player.index].factory
        attempt_factory_migration(factory)
        Factory.update_validity(factory, player)
        data_util.machines.update_default(player)

        for _, subfactory in ipairs(Factory.get_in_order(factory, "Subfactory")) do
            if subfactory.valid then update_calculations(player, subfactory) end
        end
    end
end