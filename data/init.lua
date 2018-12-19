require("subfactory")

-- Initiates all global necessary variables
function data_init()
    if global["subfactories"] == nil then global["subfactories"] = {} end
    global["selected_subfactory_id"] = 1
    if global["modal_dialog_open"] == nil then global["modal_dialog_open"] = false end
    global["currently_editing"] = false
    global["currently_deleting"] = false

    -- Enables dev mode features including rebuilding of UI instead of hiding/showing
    global["devmode"] = true
end