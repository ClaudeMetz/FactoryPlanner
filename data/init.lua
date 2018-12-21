require("subfactory")

-- Initiates all global necessary variables
function data_init()
    global["main_dialog_dimensions"] = {width = 1200, height = nil}
    if global["modal_dialog_open"] == nil then global["modal_dialog_open"] = false end
    global["selected_subfactory_id"] = 1
    global["currently_editing"] = false
    global["currently_deleting"] = false

    if global["subfactories"] == nil then global["subfactories"] = {} end
    
    -- Enables dev mode features including rebuilding of UI instead of hiding/showing
    global["devmode"] = false
end