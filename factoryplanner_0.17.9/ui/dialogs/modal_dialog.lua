require("tutorial_dialog")
require("preferences_dialog")
require("subfactory_dialog")
require("notes_dialog")
require("prototype_picker_dialog")
require("item_picker_dialog")
require("recipe_picker_dialog")
require("chooser_dialog")

-- Opens a barebone modal dialog and calls upon the given function to populate it
function enter_modal_dialog(player, dialog_settings)
    toggle_main_dialog(player)

    local player_table = global.players[player.index]
    player_table.modal_dialog_type = dialog_settings.type
    player_table.selected_object = dialog_settings.object
    player_table.current_activity = nil
    
    local conditions_function = _G["get_" .. player_table.modal_dialog_type .. "_condition_instructions"]
    local condition_instructions = (conditions_function ~= nil) and conditions_function(player) or nil
    local flow_modal_dialog = create_base_modal_dialog(player, condition_instructions, dialog_settings)
    
    player.opened = flow_modal_dialog.parent
    _G["open_" .. player_table.modal_dialog_type .. "_dialog"](flow_modal_dialog)
end

-- Handles the closing process of a modal dialog, reopening the main dialog thereafter
function exit_modal_dialog(player, button, data)
    local player_table = global.players[player.index]
    local dialog_type = player_table.modal_dialog_type
    
    local center = player.gui.center
    local flow_modal_dialog, preserve = nil, false
    -- If no normal modal dialog exists, a preserved one has to be open
    if player.gui.center["fp_frame_modal_dialog"] == nil then
        flow_modal_dialog = center["fp_frame_modal_dialog_" .. dialog_type]["flow_modal_dialog"]
        preserve = true
    else
        flow_modal_dialog = center["fp_frame_modal_dialog"]["flow_modal_dialog"]
    end
    
    local closing_function = _G["close_" .. dialog_type .. "_dialog"]
    if button == "submit" then
        -- First checks if the entered form data is correct
        local form_data = check_modal_dialog_data(flow_modal_dialog, dialog_type)
        if form_data ~= nil then  -- meaning correct form data has been entered
            for name, dataset in pairs(form_data) do data[name] = dataset end
            closing_function(flow_modal_dialog, button, data)  -- can't be nil in this case
        else return end  -- so the modal dialog doesn't close

    elseif button == "delete" or button == "cancel" then
        if closing_function ~= nil then closing_function(flow_modal_dialog, button, data) end
    end
    
    -- Close modal dialog
    player_table.modal_dialog_type = nil
    player_table.selected_object = nil
    player_table.modal_data = nil
    player_table.context.line = nil
    
    if preserve then flow_modal_dialog.parent.visible = false
    else flow_modal_dialog.parent.destroy() end

    toggle_main_dialog(player)
end


-- Checks the entered form data for errors and returns it if it's all correct, else returns nil
function check_modal_dialog_data(flow_modal_dialog, dialog_type)
    local player = game.get_player(flow_modal_dialog.player_index)
    local conditions_function = _G["get_" .. dialog_type .. "_condition_instructions"]
    local condition_instructions = (conditions_function ~= nil) and conditions_function(player) or nil

    if condition_instructions ~= nil then
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
    if dialog_settings.preserve then frame_name = frame_name .. "_" .. dialog_settings.type end
    
    if center[frame_name] ~= nil then  -- Meaning an existing preserved dialog is being opened
        -- Reset condition label colors
        local table_conditions = center[frame_name]["table_modal_dialog_conditions"]
        for _, child in pairs(table_conditions.children) do
            ui_util.set_label_color(child, "default_label")
        end

        -- Show preserved modal dialog
        center[frame_name].visible = true
        flow_modal_dialog = center[frame_name]["flow_modal_dialog"]
    else
        frame_modal_dialog = center.add{type="frame", name=frame_name, direction="vertical"}

        -- Conditions table
        local table_conditions = frame_modal_dialog.add{type="table", name="table_modal_dialog_conditions", column_count=1}
        if condition_instructions ~= nil then
            table_conditions.style.bottom_margin = 6
            for n, condition in ipairs(condition_instructions.conditions) do
                local currently_editing = (dialog_settings.object ~= nil)
                if not (currently_editing and (not condition.show_on_edit)) then
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
          style="back_button", mouse_button_filter={"left"}}
        button_cancel.style.maximal_width = 90
        button_cancel.style.left_padding = 12
        button_cancel.style.right_margin = 8

        if dialog_settings.close then button_cancel.caption = {"button-text.close"}
        else button_cancel.caption = {"button-text.cancel"} end

        button_bar.add{type="frame", name="frame_modal_dialog_spacer_1", direction="horizontal",
          style="fp_footer_filler"}

        local button_delete = button_bar.add{type="button", name="fp_button_modal_dialog_delete", 
          caption={"button-text.delete"}, style="red_button", mouse_button_filter={"left"}}
        button_delete.style.font = "default-dialog-button"
        button_delete.style.height = 32
        button_delete.style.maximal_width = 80

        local button_submit = button_bar.add{type="button", name="fp_button_modal_dialog_submit", 
          caption={"button-text.submit"}, style="confirm_button", mouse_button_filter={"left"}}
        button_submit.style.maximal_width = 90
        button_submit.style.left_margin = 8
    end

    -- Adjust visibility of the submit and delete buttons and the spacer
    local button_bar = center[frame_name]["flow_modal_dialog_button_bar"]
    button_bar["fp_button_modal_dialog_delete"].visible = dialog_settings.delete or false
    button_bar["frame_modal_dialog_spacer_1"].visible = not (dialog_settings.delete or false)
    button_bar["fp_button_modal_dialog_submit"].visible = dialog_settings.submit or false

    return flow_modal_dialog
end