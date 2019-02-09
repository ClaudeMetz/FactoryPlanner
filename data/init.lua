require("util")

-- Initiates all global variables
function data_init()
    global["factory"] = Factory()

    global["mods_changed"] = true  -- Prompts the recipe dialog to load the first time

    global["main_dialog_dimensions"] = {width = 1200, height = nil}
    global["modal_dialog_type"] = nil
    global["current_activity"] = nil
    global["selected_item_group_name"] = nil

    global["selected_subfactory_id"] = 0
    global["selected_product_id"] = 0
    
    global["devmode"] = true
end


-- Sets up environment for development purposes
function run_dev_config()
    --[[ global["factory"]:add_subfactory(Subfactory(nil, "iron-plate"))
    global["factory"]:add_subfactory(Subfactory("Beta", nil))
    global["factory"]:add_subfactory(Subfactory("Gamma", "copper-plate"))
    global["selected_subfactory_id"] = 1

    local id
    local subfactory = global["factory"]:get_selected_subfactory()
    id = subfactory:add("product", Product("electronic-circuit", 400))
    subfactory:get("product", id):add_to_amount_produced(600)
    id = subfactory:add("product", Product("advanced-circuit", 200))
    subfactory:get("product", id):add_to_amount_produced(200)
    id = subfactory:add("product", Product("processing-unit", 100))
    subfactory:get("product", id):add_to_amount_produced(60)
    id = subfactory:add("product", Product("uranium-235", 40)) ]]
end