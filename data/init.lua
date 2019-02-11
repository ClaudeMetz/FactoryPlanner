require("Factory")
require("Subfactory")
require("Product")
require("util")

-- Initiates all global variables
function data_init()
    global.factory = Factory.init()

    global["mods_changed"] = true  -- Prompts the recipe dialog to load the first time

    global["main_dialog_dimensions"] = {width = 1200, height = nil}
    global["modal_dialog_type"] = nil
    global["current_activity"] = nil

    global["selected_subfactory_id"] = 0
    global["selected_product_id"] = 0
    global["selected_item_group_name"] = nil
    
    global["devmode"] = true
end


-- Sets up environment for development purposes
function run_dev_config()
    Factory.add_subfactory(Subfactory.init("", {type="item", name="iron-plate"}))
    Factory.add_subfactory(Subfactory.init("Beta", nil))
    Factory.add_subfactory(Subfactory.init("Gamma", {type="item", name="copper-plate"}))
    global["selected_subfactory_id"] = 1

    local subfactory_id = global["selected_subfactory_id"]
    local id = Subfactory.add(subfactory_id, Product.init("electronic-circuit", 400))
    Product.add_to_amount_produced(subfactory_id, id, 600)
    id = Subfactory.add(subfactory_id, Product.init("advanced-circuit", 200))
    Product.add_to_amount_produced(subfactory_id, id, 200)
    id = Subfactory.add(subfactory_id, Product.init("processing-unit", 100))
    Product.add_to_amount_produced(subfactory_id, id, 60)
    id = Subfactory.add(subfactory_id, Product.init("uranium-235", 40))
end