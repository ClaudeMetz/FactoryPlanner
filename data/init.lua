require("subfactory")

-- Initiates all global necessary variables
function data_init()
    global["main_dialog_dimensions"] = {width = 1200, height = nil}
    global["selected_subfactory_id"] = 1
    if not global["currently_editing"] then global["currently_editing"] = false end
    if not global["currently_deleting"] then global["currently_deleting"] = false end

    if global["subfactories"] == nil then global["subfactories"] = {} end
    
    -- Enables dev mode features including rebuilding of UI instead of hiding/showing
    global["devmode"] = false
end
