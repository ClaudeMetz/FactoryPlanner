require("tutorial_dialog")
require("preferences_dialog")
require("subfactory_dialog")
require("notes_dialog")
require("prototype_picker_dialog")
require("item_picker_dialog")
require("recipe_picker_dialog")
require("chooser_dialog")
require("modules_dialog")

-- Global variable to write down the dialogs that should not be deleted when closed
cached_dialogs = {"fp_frame_modal_dialog_item_picker", "fp_frame_modal_dialog_recipe_picker"}

-- Opens a barebone modal dialog and calls upon the given function to populate it
function enter_modal_dialog(player, dialog_settings)
    local ui_state = get_ui_state(player)
    ui_state.modal_dialog_type = dialog_settings.type
    ui_state.selected_object = dialog_settings.object
    ui_state.modal_data = dialog_settings.modal_data or {}
    ui_state.current_activity = nil
    
    local conditions_function = _G["get_" .. ui_state.modal_dialog_type .. "_condition_instructions"]
    local condition_instructions = (conditions_function ~= nil) and conditions_function(ui_state.modal_data) or nil
    local flow_modal_dialog = create_base_modal_dialog(player, condition_instructions, dialog_settings)
    
    toggle_modal_dialog(player, flow_modal_dialog.parent)
    _G["open_" .. ui_state.modal_dialog_type .. "_dialog"](flow_modal_dialog)
end

-- Handles the closing process of a modal dialog, reopening the main dialog thereafter
function exit_modal_dialog(player, button, data)
    local ui_state = get_ui_state(player)
    local dialog_type = ui_state.modal_dialog_type
    local screen = player.gui.screen
    if dialog_type == nil then return end  -- cancel operation if no modal dialog is open

    local flow_modal_dialog, preserve = nil, false
    local cached_frame = screen["fp_frame_modal_dialog_" .. dialog_type]
    -- First, see if the current dialog_type has a cached frame
    if cached_frame ~= nil and cached_frame.valid then
        flow_modal_dialog = cached_frame["flow_modal_dialog"]
        preserve = true
    else
        -- If not, check if a general frame exists
        local frame = screen["fp_frame_modal_dialog"]
        if frame ~= nil and frame.valid then
            flow_modal_dialog = frame["flow_modal_dialog"]
        -- If not, no modal dialog is open, so none can be closed
        else return end
    end
    
    local closing_function = _G["close_" .. dialog_type .. "_dialog"]
    -- If closing_function is nil here, this dialog doesn't have a confirm-button, and if it is closed with
    -- a submit-action (by a confirmation-action), it should exectue the cancel-action instead
    if button == "submit" and closing_function ~= nil then
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
    ui_state.modal_dialog_type = nil
    ui_state.selected_object = nil
    ui_state.modal_data = nil
    ui_state.context.line = nil
    
    if preserve then flow_modal_dialog.parent.visible = false
    else flow_modal_dialog.parent.destroy() end

    toggle_modal_dialog(player, nil)
end


-- Checks the entered form data for errors and returns it if it's all correct, else returns nil
function check_modal_dialog_data(flow_modal_dialog, dialog_type)
    local player = game.get_player(flow_modal_dialog.player_index)
    local ui_state = get_ui_state(player)
    local conditions_function = _G["get_" .. dialog_type .. "_condition_instructions"]
    local condition_instructions = (conditions_function ~= nil) and conditions_function(ui_state.modal_data) or nil

    if condition_instructions ~= nil then
        -- Get form data
        local form_data = {}
        for name, f_data in pairs(condition_instructions.data) do
            form_data[name] = f_data(flow_modal_dialog)
        end

        -- Check all conditions
        local error_found, first_error_instructions = false, nil
        local table_conditions = flow_modal_dialog.parent["table_modal_dialog_conditions"]
        for _, condition_element in ipairs(table_conditions.children) do
            local n = tonumber(string.match(condition_element.name, "%d+"))
            local instruction = condition_instructions.conditions[n]
            if instruction.check(form_data) then
                ui_util.set_label_color(condition_element, "red")
                error_found = true
                if first_error_instructions == nil then first_error_instructions = instruction end
            else
                ui_util.set_label_color(condition_element, "default_label")
            end
        end

        if error_found then
            -- Re-focus an element, if specified
            local refocus = first_error_instructions.refocus
            if refocus then refocus(flow_modal_dialog, form_data) end
            return nil
        else
            return form_data
        end

    else return {} end
end


-- Creates barebones modal dialog
function create_base_modal_dialog(player, condition_instructions, dialog_settings)
    local frame_name, flow_modal_dialog, cached = "fp_frame_modal_dialog", nil, false
    local cached_frame_name = "fp_frame_modal_dialog_" .. dialog_settings.type

    -- See if the dialog to open is a cached one
    for _, cached_dialog in pairs(cached_dialogs) do
        if cached_dialog == cached_frame_name then
            frame_name = cached_frame_name
            cached = true
            break
        end
    end
    
    local screen = player.gui.screen
    -- If this dialog should be cached and exists, make it visible
    if cached and screen[frame_name] ~= nil then
        frame_modal_dialog = screen[frame_name]

        -- Reset condition label colors
        local table_conditions = frame_modal_dialog["table_modal_dialog_conditions"]
        for _, child in pairs(table_conditions.children) do
            ui_util.set_label_color(child, "default_label")
        end

        -- Show preserved modal dialog
        frame_modal_dialog.visible = true
        flow_modal_dialog = frame_modal_dialog["flow_modal_dialog"]

    -- Otherwise, create a whole new one with the appropriate name
    else
        frame_modal_dialog = screen.add{type="frame", name=frame_name, direction="vertical"}

        -- Conditions table
        local table_conditions = frame_modal_dialog.add{type="table", name="table_modal_dialog_conditions", column_count=1}
        if condition_instructions ~= nil then
            table_conditions.style.bottom_margin = 6
            for n, condition in ipairs(condition_instructions.conditions) do
                local currently_editing = (dialog_settings.object ~= nil)
                if not (currently_editing and (not condition.show_on_edit)) then
                    table_conditions.add{type="label", name="label_instruction_" .. n, caption=condition.label}
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

        local action = dialog_settings.close and "close" or "cancel"
        button_cancel.caption = {"button-text." .. action}
        button_cancel.tooltip = {"tooltip." .. action .. "_dialog"}

        -- Add first set of spacers, one of them will always be hidden
        button_bar.add{type="empty-widget", name="empty-widget_modal_dialog_spacer_1", style="fp_footer_filler"}
        local flow_spacer_1 = button_bar.add{type="flow", name="flow_modal_dialog_spacer_1", direction="horizontal"}
        flow_spacer_1.style.horizontally_stretchable = true

        local button_delete = button_bar.add{type="button", name="fp_button_modal_dialog_delete", 
          caption={"button-text.delete"}, style="red_button", mouse_button_filter={"left"}}
        button_delete.style.font = "default-dialog-button"
        button_delete.style.height = 32
        button_delete.style.maximal_width = 80

        -- Add second spacer, will only be used if the delete button is visible
        local flow_spacer_2 = button_bar.add{type="flow", name="flow_modal_dialog_spacer_2", direction="horizontal"}
        flow_spacer_2.style.horizontally_stretchable = true

        local button_submit = button_bar.add{type="button", name="fp_button_modal_dialog_submit", caption={"button-text.submit"},
          tooltip={"tooltip.confirm_dialog"}, style="confirm_button", mouse_button_filter={"left"}}
        button_submit.style.maximal_width = 90
        button_submit.style.left_margin = 8
    end

    frame_modal_dialog.auto_center = true
    -- Adjust visibility of the submit and delete buttons and the spacer
    local button_bar = frame_modal_dialog["flow_modal_dialog_button_bar"]
    button_bar["fp_button_modal_dialog_submit"].visible = dialog_settings.submit or false

    local delete = dialog_settings.delete or false
    button_bar["fp_button_modal_dialog_delete"].visible = delete
    button_bar["flow_modal_dialog_spacer_1"].visible = delete
    button_bar["flow_modal_dialog_spacer_2"].visible = delete
    button_bar["empty-widget_modal_dialog_spacer_1"].visible = not delete

    return flow_modal_dialog
end