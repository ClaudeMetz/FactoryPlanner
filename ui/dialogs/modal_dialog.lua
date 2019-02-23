-- Opens a barebone modal dialog and calls upon the given function to populate it
function enter_modal_dialog(player, dialog_type, submit_button, delete_button, args)
    global["modal_dialog_type"] = dialog_type
    toggle_main_dialog(player)
    local condition_instructions = _G["get_" .. dialog_type .. "_condition_instructions"]()
    local flow_modal_dialog = create_base_modal_dialog(player, condition_instructions, args.edit, submit_button, delete_button)
    _G["open_" .. dialog_type .. "_dialog"](flow_modal_dialog, args)
end

-- Handles the closing process of a modal dialog, reopening the main dialog thereafter
function exit_modal_dialog(player, button)
    local flow_modal_dialog = player.gui.center["fp_frame_modal_dialog"]["flow_modal_dialog"]
    local dialog_type = global["modal_dialog_type"]

    if button == "submit" then
        -- First checks if the entered data is correct
        local data = check_modal_dialog_data(flow_modal_dialog, dialog_type)
        if data ~= nil then  -- meaning correct data has been entered
            _G["close_" .. dialog_type .. "_dialog"](flow_modal_dialog, button, data)
        else return end  -- so modal dialog doesn't close

    elseif button == "delete" or button == "cancel" then
        _G["close_" .. dialog_type .. "_dialog"](flow_modal_dialog, button, nil)
    end

    -- Close modal dialog
    global["modal_dialog_type"] = nil
    global["current_activity"] = nil
    flow_modal_dialog.parent.destroy()
    toggle_main_dialog(player)
end


-- Checks the entered data for errors and returns it if it's all correct, else returns nil
function check_modal_dialog_data(flow_modal_dialog, dialog_type)
    local condition_instructions = _G["get_" .. dialog_type .. "_condition_instructions"]()

    -- Get data
    local data = {}
    for name, f_data in pairs(condition_instructions.data) do
        data[name] = f_data(flow_modal_dialog)
    end

    -- Check all conditions
    local error_found = false
    local table_conditions = flow_modal_dialog.parent["table_modal_dialog_conditions"]
    for _, condition_element in ipairs(table_conditions.children) do
        local n = tonumber(string.match(condition_element.name, "%d+"))
        if condition_instructions.conditions[n].check(data) then
            ui_util.set_label_color(condition_element, "red")
            error_found = true
        else
            ui_util.set_label_color(condition_element, "white")
        end
    end

    if error_found then return nil
    else return data end
end


-- Creates barebones modal dialog
function create_base_modal_dialog(player, condition_data, editing, submit_button, delete_button)
    local frame_modal_dialog = player.gui.center.add{type="frame", name="fp_frame_modal_dialog", direction="vertical"}

    -- Conditions table
    local table_conditions = frame_modal_dialog.add{type="table", name="table_modal_dialog_conditions", column_count=1}
    table_conditions.style.bottom_padding = 6
    for n, condition in ipairs(condition_data.conditions) do
        if not (editing and (not condition.show_on_edit)) then
            table_conditions.add{type="label", name="label_subfactory_instruction_" .. n, caption=condition.label}
        end
    end

    -- Main flow to be filled by specific modal dialog creator
    local flow_modal_dialog = frame_modal_dialog.add{type="flow", name="flow_modal_dialog", direction="vertical"}

    -- Button bar
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
        ui_util.set_label_color(button_delete, "red")
    end

    local flow_spacer_2 = button_bar.add{type="flow", name="flow_modal_dialog_spacer_2", direction="horizontal"}
    flow_spacer_2.style.horizontally_stretchable = true

    if submit_button then
        button_bar.add{type="button", name="fp_button_modal_dialog_submit", caption={"button-text.submit"}, 
            style="fp_button_with_spacing"}
    end

    return flow_modal_dialog
end