require("generic_dialogs")
require("tutorial_dialog")
require("preferences_dialog")
require("utility_dialog")
require("picker_dialog")
require("recipe_dialog")
require("matrix_dialog")
require("modules_dialog")
require("porter_dialog")

modal_dialog = {}

-- ** LOCAL UTIL **
local function create_base_modal_dialog(player, dialog_settings, modal_data)
    local modal_elements = modal_data.modal_elements

    local frame_modal_dialog = player.gui.screen.add{type="frame", name="fp_frame_modal_dialog", direction="vertical"}
    frame_modal_dialog.style.minimal_width = 240
    frame_modal_dialog.auto_center = true
    modal_elements.modal_frame = frame_modal_dialog

    -- Title bar
    if dialog_settings.caption ~= nil then
        if dialog_settings.search_function then  -- add a search field if requested
            local flow_title_bar = frame_modal_dialog.add{type="flow", direction="horizontal"}
            flow_title_bar.add{type="label", caption=dialog_settings.caption, style="frame_title"}

            local drag_handle = flow_title_bar.add{type="empty-widget", style="flib_titlebar_drag_handle"}
            drag_handle.drag_target = frame_modal_dialog

            local searchfield = flow_title_bar.add{type="textfield", name="fp_textfield_modal_search",
              style="search_popup_textfield"}
            searchfield.style.width = 180
            searchfield.style.margin = {-3, 4, 0, 0}
            ui_util.setup_textfield(searchfield)
            modal_elements.search_textfield = searchfield

            flow_title_bar.add{type="sprite-button", name="fp_sprite-button_modal_search", sprite="utility/search_white",
              hovered_sprite="utility/search_black", clicked_sprite="utility/search_black",
              tooltip={"fp.search_button_tt"}, style="frame_action_button", mouse_button_filter={"left"}}

            modal_data.search_function = dialog_settings.search_function

        else  -- otherwise, let the frame handle the titlebar
            frame_modal_dialog.caption = dialog_settings.caption or nil
        end
    end

    -- Content frame
    local main_content_element = nil
    if dialog_settings.create_content_frame then
        local content_frame = frame_modal_dialog.add{type="frame", direction="vertical", style="inside_shallow_frame"}
        content_frame.style.vertically_stretchable = true

        if dialog_settings.subheader_text then
            local subheader = content_frame.add{type="frame", direction="horizontal", style="subheader_frame"}
            subheader.style.horizontally_stretchable = true
            subheader.style.padding = {12, 24, 12, 12}
            local label = subheader.add{type="label", caption=dialog_settings.subheader_text,
              tooltip=dialog_settings.subheader_tooltip}
            label.style.font = "default-semibold"
        end

        local scroll_pane = content_frame.add{type="scroll-pane", direction="vertical", style="flib_naked_scroll_pane"}
        if dialog_settings.disable_scroll_pane then scroll_pane.vertical_scroll_policy = "never" end

        modal_elements.content_frame = scroll_pane
        main_content_element = scroll_pane

    else  -- if no content frame is created, simply add a flow that the dialog can add to instead
        local flow = frame_modal_dialog.add{type="flow", direction="vertical"}
        modal_elements.dialog_flow = flow
        main_content_element = flow
    end

    -- Set the maximum height of the main content element
    local dialog_max_height = (data_util.get("ui_state", player).main_dialog_dimensions.height - 80) * 0.95
    modal_data.dialog_maximal_height = dialog_max_height
    main_content_element.style.maximal_height = dialog_max_height

    -- Button bar
    local button_bar = frame_modal_dialog.add{type="flow", direction="horizontal",
      style="dialog_buttons_horizontal_flow"}
    button_bar.style.horizontal_spacing = 0

    -- Cancel/Back button
    local action = dialog_settings.show_submit_button and "cancel" or "back"
    local button_cancel = button_bar.add{type="button", name="fp_button_modal_action_cancel", style="back_button",
      caption={"fp." .. action}, tooltip={"fp." .. action .. "_dialog"}, mouse_button_filter={"left"}}
    button_cancel.style.minimal_width = 0
    button_cancel.style.padding = {1, 12, 0, 12}

    -- Delete button and spacers
    if dialog_settings.show_delete_button then
        button_bar.add{type="empty-widget", style="flib_dialog_footer_drag_handle"}

        local button_delete = button_bar.add{type="button", name="fp_button_modal_action_delete",
          caption={"fp.delete"}, style="red_button", mouse_button_filter={"left"}}
        button_delete.style.font = "default-dialog-button"
        button_delete.style.height = 32
        button_delete.style.minimal_width = 0
        button_delete.style.padding = {0, 8}

        -- If there is a delete button present, we need to set a minimum dialog width for it to look good
        frame_modal_dialog.style.minimal_width = 340
    end
    -- One 'drag handle' should always be visible
    button_bar.add{type="empty-widget", style="flib_dialog_footer_drag_handle"}

    -- Submit button
    if dialog_settings.show_submit_button then
        local button_submit = button_bar.add{type="button", name="fp_button_modal_action_submit", caption={"fp.submit"},
          tooltip={"fp.confirm_dialog"}, style="confirm_button", mouse_button_filter={"left"}}
        button_submit.style.minimal_width = 0
        button_submit.style.padding = {1, 8, 0, 12}
        modal_elements.dialog_submit_button = button_submit
    end

    return frame_modal_dialog
end


-- ** TOP LEVEL **
-- Opens a barebone modal dialog and calls upon the given function to populate it
function modal_dialog.enter(player, dialog_settings)
    local ui_state = data_util.get("ui_state", player)

    if player.gui.screen["fp_frame_modal_dialog"] ~= nil then
        -- If a dialog is currently open, and this one wants to be queued, do so
        if dialog_settings.allow_queueing then
            ui_state.queued_dialog_settings = dialog_settings
        end
        return
    end

    ui_state.modal_dialog_type = dialog_settings.type
    ui_state.modal_data = dialog_settings.modal_data or {}
    ui_state.modal_data.modal_elements = {}

    local dialog_object = _G[ui_state.modal_dialog_type .. "_dialog"]
    if dialog_object.dialog_settings then
        local additional_settings = dialog_object.dialog_settings(ui_state.modal_data)
        dialog_settings = util.merge{dialog_settings, additional_settings}
    end

    local frame_modal_dialog = create_base_modal_dialog(player, dialog_settings, ui_state.modal_data)
    local immediately_closed = dialog_object.open(player, ui_state.modal_data)

    if not immediately_closed then
        local interface_dimmer = player.gui.screen.add{type="frame", name="fp_frame_interface_dimmer",
          style="fp_frame_semitransparent"}
        ui_state.modal_data.modal_elements.interface_dimmer = interface_dimmer

        local dimensions = ui_state.main_dialog_dimensions
        interface_dimmer.style.size = {dimensions.width, dimensions.height}
        interface_dimmer.location = ui_state.main_elements.main_frame.location

        frame_modal_dialog.bring_to_front()
        player.opened = frame_modal_dialog

        if dialog_settings.force_auto_center then
            frame_modal_dialog.force_auto_center()
        end
    end
end

-- Handles the closing process of a modal dialog, reopening the main dialog thereafter
function modal_dialog.exit(player, button_action)
    local ui_state = data_util.get("ui_state", player)
    if ui_state.modal_dialog_type == nil then return end

    local modal_elements = ui_state.modal_data.modal_elements
    local submit_button = modal_elements.dialog_submit_button

    -- If no action is give, submit if possible, otherwise close the dialog
    if button_action == nil then
        button_action = (submit_button and submit_button.enabled)and "submit" or "cancel"

    -- Stop exiting if it is not possible on this dialog, or the button is disabled
    elseif button_action == "submit" and (not submit_button or not submit_button.enabled) then
        return
    end

    -- Call the closing function for this dialog, if it exists
    local closing_function = _G[ui_state.modal_dialog_type .. "_dialog"].close
    if closing_function ~= nil then closing_function(player, button_action) end

    ui_state.modal_dialog_type = nil
    ui_state.modal_data = nil

    modal_elements.modal_frame.destroy()
    if modal_elements.interface_dimmer then modal_elements.interface_dimmer.destroy() end

    player.opened = ui_state.main_elements.main_frame
    title_bar.refresh_message(player)

    if ui_state.queued_dialog_settings ~= nil then
        modal_dialog.enter(player, ui_state.queued_dialog_settings)
        ui_state.queued_dialog_settings = nil
    end
end


function modal_dialog.set_submit_button_state(modal_elements, enabled, message)
    local caption = (enabled) and {"fp.submit"} or {"fp.warning_with_icon", {"fp.submit"}}
    local tooltip = (enabled) and {"fp.confirm_dialog"} or {"fp.warning_with_icon", message}

    local button = modal_elements.dialog_submit_button
    button.style.left_padding = (enabled) and 12 or 6
    button.enabled = enabled
    button.caption = caption
    button.tooltip = tooltip
end


function modal_dialog.enter_selection_mode(player, selector_name)
    local ui_state = data_util.get("ui_state", player)
    ui_state.flags.selection_mode = true
    player.cursor_stack.set_stack(selector_name)

    local frame_main_dialog = ui_state.main_elements.main_frame
    frame_main_dialog.visible = false
    main_dialog.set_pause_state(player, frame_main_dialog, true)

    local modal_elements = ui_state.modal_data.modal_elements
    modal_elements.interface_dimmer.visible = false

    modal_elements.modal_frame.ignored_by_interaction = true
    modal_elements.modal_frame.location = {25, 50}
end

function modal_dialog.leave_selection_mode(player)
    local ui_state = data_util.get("ui_state", player)
    ui_state.flags.selection_mode = false
    player.cursor_stack.set_stack(nil)

    local modal_elements = ui_state.modal_data.modal_elements
    modal_elements.interface_dimmer.visible = true

    -- .opened needs to be set because on_gui_closed sets it to nil
    player.opened = modal_elements.modal_frame
    modal_elements.modal_frame.ignored_by_interaction = false
    modal_elements.modal_frame.force_auto_center()

    local frame_main_dialog = ui_state.main_elements.main_frame
    frame_main_dialog.visible = true
    main_dialog.set_pause_state(player, frame_main_dialog)
end


-- ** EVENTS **
modal_dialog.gui_events = {
    on_gui_click = {
        {
            name = "fp_frame_interface_dimmer",
            handler = (function(player, _, _)
                data_util.get("modal_elements", player).modal_frame.bring_to_front()
            end)
        },
        {
            pattern = "^fp_button_modal_action_[a-z]+$",
            handler = (function(player, element, _)
                local dialog_action = string.gsub(element.name, "fp_button_modal_action_", "")
                modal_dialog.exit(player, dialog_action)
            end)
        },
        {
            name = "fp_sprite-button_modal_search",
            handler = (function(player, _, _)
                ui_util.select_all(data_util.get("modal_elements", player).search_textfield)
            end)
        }
    },
    on_gui_text_changed = {
        {
            name = "fp_textfield_modal_search",
            handler = (function(player, element)
                local search_term = element.text:gsub("^%s*(.-)%s*$", "%1"):lower()
                data_util.get("modal_data", player).search_function(player, search_term)
            end)
        }
    },
    on_gui_closed = {
        {
            name = "fp_frame_modal_dialog",
            handler = (function(player, _)
                local ui_state = data_util.get("ui_state", player)

                if ui_state.flags.selection_mode then
                    modal_dialog.leave_selection_mode(player)
                else
                    -- Calling this without an action will make it choose the appropriate one
                    modal_dialog.exit(player, nil)
                end
            end)
        }
    }
}

modal_dialog.misc_events = {
    fp_confirm_dialog = (function(player, _)
        if not data_util.get("flags", player).selection_mode then
            modal_dialog.exit(player, "submit")
        end
    end),

    fp_focus_searchfield = (function(player, _)
        local ui_state = data_util.get("ui_state", player)

        if ui_state.modal_dialog_type ~= nil then
            local textfield_search = ui_state.modal_data.modal_elements.search_textfield
            if textfield_search then ui_util.select_all(textfield_search) end
        end
    end)
}