require("subfactory")

-- Initiates all global necessary variables
function data_init()
    global["main_dialog_dimensions"] = {width = 1200, height = nil}
    global["modal_dialog_type"] = nil
    global["selected_subfactory_id"] = 1
    global["subfactory_order"] = {}
    global["currently_editing_subfactory"] = false
    global["currently_deleting_subfactory"] = false
    global["currently_changing_timescale"] = false
    global["currently_editing_product_id"] = nil

    -- if statement as a security measure to cure a bit of paranoia
    if global["subfactories"] == nil then global["subfactories"] = {} end
    
    global["devmode"] = true
end
