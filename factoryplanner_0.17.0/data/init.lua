require("data.classes.Collection")
require("data.classes.Item")
require("data.classes.Factory")
require("data.classes.Subfactory")
require("data.classes.Floor")
require("data.classes.Line")
require("data.util")
require("data.generator")
require("data.calc")


-- Initiates all factorio-global variables
function global_init()
    global.players = {}

    global.all_items = generator.all_items()
    -- Recipes are generated on player init because they depend on their force
    global.all_machines = generator.all_machines()

    --global.devmode = true
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

        player_table.modal_dialog_type = nil  -- The internal modal dialog type
        player_table.selected_object = nil  -- The object relevant for a modal dialog
        player_table.current_activity = nil  -- The current unique main dialog activity
        player_table.queued_hint_message = ""  -- The next hint message to be displayed
        player_table.context = data_util.context.create()  -- The currently displayed set of data
    end
end

-- Resets the GUI state of the given player, if there is any
function player_reset(player)
    if global.players[player.index] ~= nil then
        local player_table = global.players[player.index]

        player_table.modal_dialog_type = nil
        player_table.selected_object = nil
        player_table.current_activity = nil
        player_table.queued_hint_message = ""
        player_table.context = data_util.context.create()
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
    settings_table.show_disabled_recipe = settings["fp_show_disabled_recipe"].value
end

-- Runs through all updates that need to be made after the config changed
function handle_configuration_change()
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

        Factory.update_validity(global.players[player.index].factory, player)
        data_util.machines.update_default(player)
    end
end


-- Initiates the data table with some values for development purposes
function run_dev_config(player)
    if global.devmode then
        local player_table = global.players[player.index]
        local factory = player_table.factory

        local subfactory = Factory.add(factory, Subfactory.init("", {type="item", name="iron-plate"}))
        Factory.add(factory, Subfactory.init("Beta", nil))
        Factory.add(factory, Subfactory.init("Gamma", {type="item", name="electronic-circuit"}))
        data_util.context.set_subfactory(player, subfactory)

        local prod1 = Subfactory.add(subfactory, Item.init({name="electronic-circuit", type="item"}, nil, "Product", 0))
        prod1.required_amount = 400
        local prod2 = Subfactory.add(subfactory, Item.init({name="heavy-oil", type="fluid"}, nil, "Product", 0))
        prod2.required_amount = 100
        local prod3 = Subfactory.add(subfactory, Item.init({name="uranium-235", type="item"}, nil, "Product", 0))
        prod3.required_amount = 10

        local floor = Subfactory.get(subfactory, "Floor", 1)
        local recipe = global.all_recipes[player.force.name]["electronic-circuit"]
        local machine = data_util.machines.get_default(player, recipe.category)
        Floor.add(floor, Line.init(recipe, machine))
    end
end