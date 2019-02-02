require("subfactory")
require("product")

-- Initiates all global variables
function data_init()
    -- if-statement as a measure of curing a bit of my paranoia
    if global["subfactories"] == nil then global["subfactories"] = {} end

    global["main_dialog_dimensions"] = {width = 1200, height = nil}
    global["mods_changed"] = true  -- Prompts the recipe dialog to load the first time

    global["modal_dialog_type"] = nil
    global["current_activity"] = nil

    global["selected_subfactory_id"] = 0
    global["selected_product_id"] = 0
    global["selected_item_group_name"] = nil
    
    global["subfactory_order"] = {} -- remove in next update
    
    global["devmode"] = true
end


-- Sets up environment for development purposes
function run_dev_config()
    local id = add_subfactory(nil, "iron-plate")
    local p1 = add_product(id, "electronic-circuit", 400)
    change_product_amount_produced(id, p1, 600)
    local p2 = add_product(id, "advanced-circuit", 200)
    change_product_amount_produced(id, p2, 200)
    local p3 = add_product(id, "processing-unit", 100)
    change_product_amount_produced(id, p3, 60)
    local p4 = add_product(id, "uranium-235", 20)
    change_product_amount_produced(id, p4, 0)

    add_subfactory("Beta", nil)
    add_subfactory("Gamma", "copper-plate")

    global["selected_subfactory_id"] = 1
    update_subfactory_order()
end