-- Opens a barebone modal dialog and calls upon the given function to populate it
function enter_modal_dialog(player, dialog_type, dialog_settings, args)
    global.players[player.index].modal_dialog_type = dialog_type
    toggle_main_dialog(player)
    local condition_instructions = _G["get_" .. dialog_type .. "_condition_instructions"](player)
    local flow_modal_dialog = create_base_modal_dialog(player, condition_instructions, args.edit, dialog_settings)
    _G["open_" .. dialog_type .. "_dialog"](flow_modal_dialog, args)
end

-- Handles the closing process of a modal dialog, reopening the main dialog thereafter
function exit_modal_dialog(player, button)
    local player_table = global.players[player.index]
    local flow_modal_dialog = player.gui.center["fp_frame_modal_dialog"]["flow_modal_dialog"]
    local dialog_type = player_table.modal_dialog_type

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
    player_table.modal_dialog_type = nil
    player_table.current_activity = nil
    flow_modal_dialog.parent.destroy()
    toggle_main_dialog(player)
end


-- Checks the entered data for errors and returns it if it's all correct, else returns nil
function check_modal_dialog_data(flow_modal_dialog, dialog_type)
    local player = game.players[flow_modal_dialog.player_index]
    local condition_instructions = _G["get_" .. dialog_type .. "_condition_instructions"](player)

    if #condition_instructions.conditions ~= 0 then
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
                ui_util.set_label_color(condition_element, "default_label")
            end
        end

        if error_found then return nil
        else return data end

    else return {} end
end


-- Creates barebones modal dialog
function create_base_modal_dialog(player, condition_instructions, editing, dialog_settings)
    local frame_modal_dialog = player.gui.center.add{type="frame", name="fp_frame_modal_dialog", direction="vertical"}

    -- Conditions table
    if #condition_instructions.conditions ~= 0 then
        local table_conditions = frame_modal_dialog.add{type="table", name="table_modal_dialog_conditions", column_count=1}
        table_conditions.style.bottom_margin = 6
        for n, condition in ipairs(condition_instructions.conditions) do
            if not (editing and (not condition.show_on_edit)) then
                table_conditions.add{type="label", name="label_subfactory_instruction_" .. n, caption=condition.label}
            end
        end
    end

    -- Main flow to be filled by specific modal dialog creator
    local flow_modal_dialog = frame_modal_dialog.add{type="scroll-pane", name="flow_modal_dialog", direction="vertical"}
    flow_modal_dialog.style.maximal_height = 800

    -- Button bar
    local button_bar = frame_modal_dialog.add{type="flow", name="flow_modal_dialog_button_bar", direction="horizontal"}
    button_bar.style.minimal_width = 220
    button_bar.style.top_margin = 4

    local button_cancel = button_bar.add{type="button", name="fp_button_modal_dialog_cancel",
      style="back_button"}
    button_cancel.style.maximal_width = 90
    button_cancel.style.left_padding = 12

    if dialog_settings.close then button_cancel.caption = {"button-text.close"}
    else button_cancel.caption = {"button-text.cancel"} end

    local flow_spacer_1 = button_bar.add{type="flow", name="flow_modal_dialog_spacer_1", direction="horizontal"}
    flow_spacer_1.style.horizontally_stretchable = true

    if dialog_settings.delete then
        local button_delete = button_bar.add{type="button", name="fp_button_modal_dialog_delete", 
          caption={"button-text.delete"}, style="red_button"}
        button_delete.style.font = "default-dialog-button"
        button_delete.style.height = 32
        button_delete.style.maximal_width = 80
    end

    local flow_spacer_2 = button_bar.add{type="flow", name="flow_modal_dialog_spacer_2", direction="horizontal"}
    flow_spacer_2.style.horizontally_stretchable = true

    if dialog_settings.submit then
        local button_submit = button_bar.add{type="button", name="fp_button_modal_dialog_submit", 
          caption={"button-text.submit"}, style="confirm_button"}
        button_submit.style.maximal_width = 90
    end

    return flow_modal_dialog
end