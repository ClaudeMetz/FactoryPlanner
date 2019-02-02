-- Opens a barebone modal dialog and calls upon the given function to populate it
function enter_modal_dialog(player, type, submit_button, delete_button, args)
    global["modal_dialog_type"] = type
    toggle_main_dialog(player)
    local flow_modal_dialog = create_base_modal_dialog(player, submit_button, delete_button)
    _G["open_" .. type .. "_dialog"](flow_modal_dialog, args)
end

-- Handles the closing process of a modal dialog, reopening the main dialog thereafter
function exit_modal_dialog(player, button)
    local frame_modal_dialog = player.gui.center["fp_frame_modal_dialog"]
    local type = global["modal_dialog_type"]
    local closing = false
    
    if button == "submit" then
        local flow_modal_dialog = frame_modal_dialog["flow_modal_dialog"]

        -- First checks if the entered data is correct
        local data = _G["check_" .. type .. "_data"](flow_modal_dialog)
        if data ~= nil then  -- meaning correct data has been entered
            _G["submit_" .. type .. "_dialog"](flow_modal_dialog, data)
            closing = true
        end

    elseif button == "delete" then
        _G["delete_" .. type .. "_dialog"]()
        closing = true

    elseif button == "cancel" then
        -- Run cleanup if necessary
        local cleanup = _G["cleanup_" .. type .. "_dialog"]
        if cleanup ~= nil then cleanup() end

        closing = true
    end

    if closing then
        global["modal_dialog_type"] = nil
        global["current_activity"] = nil
        frame_modal_dialog.destroy()
        toggle_main_dialog(player)
    end
end

-- Creates barebones modal dialog
function create_base_modal_dialog(player, submit_button, delete_button)
    local frame_modal_dialog = player.gui.center.add{type="frame", name="fp_frame_modal_dialog", direction="vertical"}
    local flow_modal_dialog = frame_modal_dialog.add{type="flow", name="flow_modal_dialog", direction="vertical"}

    local button_bar = frame_modal_dialog.add{type="flow", name="flow_modal_dialog_button_bar", direction="horizontal"}
    button_bar.style.minimal_width = 220

    button_bar.add{type="button", name="fp_button_modal_dialog_cancel", caption={"button-text.cancel"}, 
        style="fp_button_with_spacing"}

    local flow_spacer_1 = button_bar.add{type="flow", name="flow_modal_dialog_spacer_1", direction="horizontal"}
    flow_spacer_1.style.horizontally_stretchable = true

    if delete_button then
        local button_delete = button_bar.add{type="button", name="fp_button_modal_dialog_delete", 
          caption={"button-text.delete"}, style="fp_button_with_spacing"}
        button_delete.style.font="default-game"
        set_label_color(button_delete, "red")
    end

    local flow_spacer_1 = button_bar.add{type="flow", name="flow_modal_dialog_spacer_2", direction="horizontal"}
    flow_spacer_1.style.horizontally_stretchable = true

    if submit_button then
        button_bar.add{type="button", name="fp_button_modal_dialog_submit", caption={"button-text.submit"}, 
            style="fp_button_with_spacing"}
    end

    return flow_modal_dialog
end