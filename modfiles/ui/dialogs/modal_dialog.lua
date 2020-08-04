require("generic_dialogs")
require("tutorial_dialog")
require("preferences_dialog")
require("subfactory_dialog")
require("utility_dialog")
require("product_dialog")
require("recipe_dialog")
require("modules_dialog")
require("porter_dialog")

modal_dialog = {}

-- ** LOCAL UTIL **
-- Creates barebones modal dialog
local function create_base_modal_dialog(player, condition_instructions, dialog_settings, modal_data)
    local frame_modal_dialog = player.gui.screen.add{type="frame", name="fp_frame_modal_dialog", direction="vertical"}
    frame_modal_dialog.caption = dialog_settings.caption or nil
    frame_modal_dialog.auto_center = true
    modal_data.ui_elements.frame = frame_modal_dialog

    -- Conditions table
    local table_conditions = frame_modal_dialog.add{type="table", name="table_modal_dialog_conditions",
      column_count=1, visible=false}
    table_conditions.style.bottom_margin = 6

    local conditions_height = 0
    if condition_instructions ~= nil and condition_instructions.conditions ~= nil then
        table_conditions.visible = true

        for n, condition in ipairs(condition_instructions.conditions) do
            local currently_editing = (dialog_settings.object ~= nil)
            if not (currently_editing and (not condition.show_on_edit)) then
                table_conditions.add{type="label", name="label_instruction_" .. n, caption=condition.label}
            end
        end

        conditions_height = table_size(condition_instructions.conditions) * 30
    end


    -- Main flow to be filled by specific modal dialog creator
    local flow_modal_dialog = frame_modal_dialog.add{type="scroll-pane", name="flow_modal_dialog", direction="vertical"}
    if dialog_settings.disable_scroll_pane then flow_modal_dialog.vertical_scroll_policy = "never" end
    modal_data.ui_elements.flow_modal_dialog = flow_modal_dialog

    local main_dialog_dimensions = get_ui_state(player).main_dialog_dimensions
    modal_data.dialog_maximal_height = (main_dialog_dimensions.height - conditions_height - 60) * 0.9
    flow_modal_dialog.style.maximal_height = modal_data.dialog_maximal_height


    -- Button bar
    local button_bar = frame_modal_dialog.add{type="flow", name="flow_modal_dialog_button_bar", direction="horizontal",
      style="dialog_buttons_horizontal_flow"}
    button_bar.style.minimal_width = 220

    -- Cancel/Back button
    local button_cancel = button_bar.add{type="button", name="fp_button_modal_dialog_cancel", style="back_button",
      mouse_button_filter={"left"}}
    button_cancel.style.maximal_width = 90
    button_cancel.style.left_padding = 12
    button_cancel.style.right_margin = 8

    local action = dialog_settings.submit and "cancel" or "back"
    button_cancel.caption = {"fp." .. action}
    button_cancel.tooltip = {"fp." .. action .. "_dialog"}

    -- Delete button and spacers
    if dialog_settings.delete then
        local flow_spacer_1 = button_bar.add{type="flow", name="flow_modal_dialog_spacer_1", direction="horizontal"}
        flow_spacer_1.style.horizontally_stretchable = true

        local button_delete = button_bar.add{type="button", name="fp_button_modal_dialog_delete",
          caption={"fp.delete"}, style="red_button", mouse_button_filter={"left"}}
        button_delete.style.font = "default-dialog-button"
        button_delete.style.height = 32
        button_delete.style.maximal_width = 80

        local flow_spacer_2 = button_bar.add{type="flow", name="flow_modal_dialog_spacer_2", direction="horizontal"}
        flow_spacer_2.style.horizontally_stretchable = true
    else
        -- This filler-type widget is only needed when no delete button is shown
        button_bar.add{type="empty-widget", name="empty-widget_modal_dialog_spacer_1", style="fp_footer_filler"}
    end

    -- Submit button
    if dialog_settings.submit then
        local button_submit = button_bar.add{type="button", name="fp_button_modal_dialog_submit", caption={"fp.submit"},
          tooltip={"fp.confirm_dialog"}, style="confirm_button", mouse_button_filter={"left"}}
        button_submit.style.minimal_width = 0
        button_submit.style.left_margin = 8
        button_submit.style.padding = {1, 8, 0, 12}
        modal_data.ui_elements.dialog_submit_button = button_submit
    end

    return flow_modal_dialog
end

-- Checks the entered form data for errors and returns it if it's all correct, else returns nil
local function check_modal_dialog_data(flow_modal_dialog, dialog_type)
    local player = game.get_player(flow_modal_dialog.player_index)
    local ui_state = get_ui_state(player)
    local conditions_function = _G[dialog_type .. "_dialog"].condition_instructions
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
                first_error_instructions = first_error_instructions or instruction
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

-- Changes the main dialog in reaction to a modal dialog being opened/closed
local function toggle_modal_dialog(player, frame_modal_dialog)
    local frame_main_dialog = player.gui.screen["fp_frame_main_dialog"]

    -- If the frame parameter is not nil, the given modal dialog has been opened
    if frame_modal_dialog ~= nil then
        player.opened = frame_modal_dialog
        frame_main_dialog.ignored_by_interaction = true
    else
        player.opened = frame_main_dialog
        frame_main_dialog.ignored_by_interaction = false
    end
end


-- ** TOP LEVEL **
-- Opens a barebone modal dialog and calls upon the given function to populate it
function modal_dialog.enter(player, dialog_settings)
    if player.gui.screen["fp_frame_modal_dialog"] then return end

    local ui_state = get_ui_state(player)
    ui_state.modal_dialog_type = dialog_settings.type
    ui_state.modal_data = dialog_settings.modal_data or {}
    ui_state.modal_data.ui_elements = {}

    local dialog_object = _G[ui_state.modal_dialog_type .. "_dialog"]

    local conditions_function = dialog_object.condition_instructions
    local condition_instructions = (conditions_function ~= nil) and conditions_function(ui_state.modal_data) or nil

    if dialog_object.dialog_settings then
        local additional_settings = dialog_object.dialog_settings(ui_state.modal_data)
        dialog_settings = util.merge{dialog_settings, additional_settings}
    end

    local flow_modal_dialog = create_base_modal_dialog(player, condition_instructions,
      dialog_settings, ui_state.modal_data)

    toggle_modal_dialog(player, flow_modal_dialog.parent)
    -- TODO remove flow_modal_dialog when every dialog has been updated
    dialog_object.open(player, flow_modal_dialog, ui_state.modal_data)

    local frame_modal_dialog = player.gui.screen["fp_frame_modal_dialog"]
    if dialog_settings.force_auto_center and frame_modal_dialog then
        frame_modal_dialog.force_auto_center()
    end
end

-- Handles the closing process of a modal dialog, reopening the main dialog thereafter
function modal_dialog.exit(player, button_action, data)
    local ui_state = get_ui_state(player)
    local dialog_type = ui_state.modal_dialog_type

    local frame_modal_dialog, flow_modal_dialog = player.gui.screen["fp_frame_modal_dialog"], nil
    if frame_modal_dialog ~= nil and frame_modal_dialog.valid then
        flow_modal_dialog = frame_modal_dialog["flow_modal_dialog"]
    else return end  -- If no modal dialog is open, none can be closed

    -- Cancel action if it is not possible on this dialog, or the button is disabled
    local submit_button = flow_modal_dialog.parent["flow_modal_dialog_button_bar"]["fp_button_modal_dialog_submit"]
    if button_action == "submit" and (not submit_button or not submit_button.enabled) then return end

    local closing_function = _G[dialog_type .. "_dialog"].close
    if closing_function ~= nil then
        if button_action == "submit" then
            -- First checks if the entered form data is correct
            local form_data = check_modal_dialog_data(flow_modal_dialog, dialog_type)
            if form_data ~= nil then  -- meaning correct form data has been entered
                for name, dataset in pairs(form_data) do data[name] = dataset end
                closing_function(player, button_action, data)  -- can't be nil in this case
            else return end  -- so the modal dialog doesn't close

        else  -- deleting and closing needs the closing function to run
            closing_function(player, button_action, data)
        end
    end

    -- Close modal dialog
    ui_state.modal_dialog_type = nil
    ui_state.modal_data = nil
    ui_state.context.line = nil
    flow_modal_dialog.parent.destroy()

    titlebar.refresh_message(player)
    toggle_modal_dialog(player, nil)
end


-- Sets selection mode and configures the related GUI's
function modal_dialog.set_selection_mode(player, state)
    local ui_state = get_ui_state(player)

    if ui_state.modal_dialog_type == "beacon" then
        ui_state.flags.selection_mode = state

        local frame_main_dialog = player.gui.screen["fp_frame_main_dialog"]
        frame_main_dialog.visible = not state

        local frame_modal_dialog = player.gui.screen["fp_frame_modal_dialog"]
        frame_modal_dialog.ignored_by_interaction = state

        if state == true then
            frame_modal_dialog.location = {25, 50}
            main_dialog.set_pause_state(player, frame_main_dialog, true)
        else
            frame_modal_dialog.force_auto_center()
            player.opened = frame_modal_dialog
            main_dialog.set_pause_state(player, frame_main_dialog)
        end
    end
end

function modal_dialog.set_submit_button_state(ui_elements, enabled, message)
    local caption = (enabled) and {"fp.submit"} or {"fp.warning_with_icon", {"fp.submit"}}
    local tooltip = (enabled) and {"fp.confirm_dialog"} or {"fp.warning_with_icon", message}

    local button = ui_elements.dialog_submit_button
    button.style.left_padding = (enabled) and 12 or 6
    button.enabled = enabled
    button.caption = caption
    button.tooltip = tooltip
end