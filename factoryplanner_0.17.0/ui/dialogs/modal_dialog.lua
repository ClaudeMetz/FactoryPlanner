require("preferences_dialog")
require("recipe_picker_dialog")

-- Opens a barebone modal dialog and calls upon the given function to populate it
function enter_modal_dialog(player, dialog_settings)
    toggle_main_dialog(player)

    local player_table = global.players[player.index]
    player_table.modal_dialog_type = dialog_settings.type
    player_table.selected_object = dialog_settings.object
    player_table.current_activity = nil

    dialog_settings.edit = (dialog_settings.object ~= nil)
    if not dialog_settings.preserve then dialog_settings.type = nil end 
    local condition_instructions = _G["get_" .. player_table.modal_dialog_type .. "_condition_instructions"](player)

    local flow_modal_dialog = create_base_modal_dialog(player, condition_instructions, dialog_settings)
    player.opened = flow_modal_dialog.parent
    _G["open_" .. player_table.modal_dialog_type .. "_dialog"](flow_modal_dialog)
end

-- Handles the closing process of a modal dialog, reopening the main dialog thereafter
function exit_modal_dialog(player, button, data)
    local player_table = global.players[player.index]
    local dialog_type = player_table.modal_dialog_type
    local center = player.gui.center
    local flow_modal_dialog, preserve

    if player.gui.center["fp_frame_modal_dialog"] == nil then
        flow_modal_dialog = center["fp_frame_modal_dialog_" .. dialog_type]["flow_modal_dialog"]
        preserve = true
    else
        flow_modal_dialog = center["fp_frame_modal_dialog"]["flow_modal_dialog"]
    end

    if button == "submit" then
        -- First checks if the entered form data is correct
        local form_data = check_modal_dialog_data(flow_modal_dialog, dialog_type)
        if form_data ~= nil then  -- meaning correct form data has been entered
            for name, dataset in pairs(form_data) do data[name] = dataset end
            _G["close_" .. dialog_type .. "_dialog"](flow_modal_dialog, button, data)
        else return end  -- so the modal dialog doesn't close

    elseif button == "delete" or button == "cancel" then
        _G["close_" .. dialog_type .. "_dialog"](flow_modal_dialog, button, data)
    end

    -- Close modal dialog
    player_table.modal_dialog_type = nil
    player_table.selected_object = nil
    if preserve then flow_modal_dialog.parent.visible = false
    else flow_modal_dialog.parent.destroy() end
    toggle_main_dialog(player)
end


-- Checks the entered form data for errors and returns it if it's all correct, else returns nil
function check_modal_dialog_data(flow_modal_dialog, dialog_type)
    local player = game.players[flow_modal_dialog.player_index]
    local condition_instructions = _G["get_" .. dialog_type .. "_condition_instructions"](player)

    if #condition_instructions.conditions ~= 0 then
        -- Get form data
        local form_data = {}
        for name, f_data in pairs(condition_instructions.data) do
            form_data[name] = f_data(flow_modal_dialog)
        end

        -- Check all conditions
        local error_found = false
        local table_conditions = flow_modal_dialog.parent["table_modal_dialog_conditions"]
        for _, condition_element in ipairs(table_conditions.children) do
            local n = tonumber(string.match(condition_element.name, "%d+"))
            if condition_instructions.conditions[n].check(form_data) then
                ui_util.set_label_color(condition_element, "red")
                error_found = true
            else
                ui_util.set_label_color(condition_element, "default_label")
            end
        end

        if error_found then return nil
        else return form_data end

    else return {} end
end


-- Creates barebones modal dialog
function create_base_modal_dialog(player, condition_instructions, dialog_settings)
    local center = player.gui.center
    local flow_modal_dialog

    local frame_name = "fp_frame_modal_dialog"
    if dialog_settings.type ~= nil then frame_name = frame_name .. "_" .. dialog_settings.type end

    if center[frame_name] ~= nil then
        center[frame_name].visible = true
        flow_modal_dialog = center[frame_name]["flow_modal_dialog"]
    else
        frame_modal_dialog = center.add{type="frame", name=frame_name, direction="vertical"}

        -- Conditions table
        if #condition_instructions.conditions ~= 0 then
            local table_conditions = frame_modal_dialog.add{type="table", name="table_modal_dialog_conditions", column_count=1}
            table_conditions.style.bottom_margin = 6
            for n, condition in ipairs(condition_instructions.conditions) do
                if not (dialog_settings.edit and (not condition.show_on_edit)) then
                    table_conditions.add{type="label", name="label_subfactory_instruction_" .. n, caption=condition.label}
                end
            end
        end

        -- Main flow to be filled by specific modal dialog creator
        flow_modal_dialog = frame_modal_dialog.add{type="scroll-pane", name="flow_modal_dialog", direction="vertical"}
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
    end

    return flow_modal_dialog
end