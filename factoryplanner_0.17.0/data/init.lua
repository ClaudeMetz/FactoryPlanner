require("data.util")
require("data.classes.Factory")
require("data.classes.Subfactory")
require("data.classes.Ingredient")
require("data.classes.Product")
require("data.classes.Byproduct")
require("data.classes.Floor")
require("data.classes.Line")


-- Initiates all factorio-global variables
function global_init()
    global.players = {}

    global.all_recipes = data_util.generate_all_recipes()
    global.all_machines = data_util.generate_all_machines()

    global.devmode = true
end

-- Creates and initiates a new player in the database if he doesn't exist yet
function player_init(player)
    if global.players[player.index] == nil then
        global.players[player.index] = {}
        local player_table = global.players[player.index]

        player_table.factory = Factory.init()
        player_table.main_dialog_dimensions = {width = nil, height = 1000}

        player_table.default_machines = {}
        data_util.update_default_machines(player)

        player_table.modal_dialog_type = nil
        player_table.current_activity = nil
        player_table.queued_hint_message = ""

        player_table.selected_subfactory_id = 0
        player_table.selected_product_name = nil
        player_table.selected_item_group_name = nil
        player_table.selected_line_id = 0
    end
end

-- Resets the GUI state of the given player, if there is any
function player_reset(player)
    if global.players[player.index] ~= nil then
        local player_table = global.players[player.index]

        player_table.modal_dialog_type = nil
        player_table.current_activity = nil
        player_table.queued_hint_message = ""

        player_table.selected_product_name = nil
        player_table.selected_item_group_name = nil
        player_table.selected_line_id = 0
    end
end

-- Removes given player irreversibly from the database
function player_remove(player)
    global.players[player.index] = nil
end

-- Runs through all updates that need to be made after the config changed
function handle_configuration_change()
    global.all_recipes = data_util.generate_all_recipes()
    global.all_machines = data_util.generate_all_machines()

    for index, player in pairs(game.players) do
        local space_tech = player.force.technologies["space-science-pack"].researched
        if space_tech then global.all_recipes["fp-space-science-pack"].enabled = true end

        player_reset(player)
        player_gui_reset(player)

        player_init(player)
        player_gui_init(player)

        Factory.update_validity(player)
        data_util.update_default_machines(player)
    end
end


-- Initiates the data table with some values for development purposes
function run_dev_config(player)
    local player_table = global.players[player.index]

    if global.devmode then
        Factory.add_subfactory(player, Subfactory.init("", {type="item", name="iron-plate"}))
        Factory.add_subfactory(player, Subfactory.init("Beta", nil))
        Factory.add_subfactory(player, Subfactory.init("Gamma", {type="item", name="electronic-circuit"}))
        player_table.selected_subfactory_id = 1

        local subfactory_id, id = player_table.selected_subfactory_id, nil

        id = Subfactory.add(player, subfactory_id, Product.init({name="electronic-circuit", type="item"}, 400))
        Product.add_to_amount_produced(player, subfactory_id, id, 600)
        id = Subfactory.add(player, subfactory_id, Product.init({name="advanced-circuit", type="item"}, 200))
        Product.add_to_amount_produced(player, subfactory_id, id, 200)
        id = Subfactory.add(player, subfactory_id, Product.init({name="processing-unit", type="item"}, 100))
        Product.add_to_amount_produced(player, subfactory_id, id, 60)
        Subfactory.add(player, subfactory_id, Product.init({name="uranium-235", type="item"}, 40))

        Subfactory.add(player, subfactory_id, Ingredient.init({name="copper-plate", type="item"}, 800))
        Subfactory.add(player, subfactory_id, Ingredient.init({name="iron-plate", type="item"}, 400))

        id = Subfactory.add(player, subfactory_id, Byproduct.init({name="heavy-oil", type="fluid"}, 600))
        id = Subfactory.add(player, subfactory_id, Byproduct.init({name="light-oil", type="fluid"}, 750))

        Floor.add_line(player, subfactory_id, 1, Line.init(player, global.all_recipes["electronic-circuit"]))
        Floor.add_line(player, subfactory_id, 1, Line.init(player, global.all_recipes["advanced-circuit"]))
    end
end