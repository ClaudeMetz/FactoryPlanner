require("generic_dialogs")
require("tutorial_dialog")
require("preferences_dialog")
require("utility_dialog")
require("picker_dialog")
require("recipe_dialog")
require("matrix_dialog")
require("porter_dialog")
require("subfactory_dialog")
require("machine_dialog")
require("beacon_dialog")

modal_dialog = {}

-- ** LOCAL UTIL **
local function create_base_modal_dialog(player, dialog_settings, modal_data)
    local modal_elements = modal_data.modal_elements

    local frame_modal_dialog = player.gui.screen.add{type="frame", direction="vertical",
        tags={mod="fp", on_gui_closed="close_modal_dialog"}}
    frame_modal_dialog.style.minimal_width = 240
    modal_elements.modal_frame = frame_modal_dialog

    -- Title bar
    if dialog_settings.caption ~= nil then
        local flow_title_bar = frame_modal_dialog.add{type="flow", direction="horizontal",
            tags={mod="fp", on_gui_click="re-center_modal_dialog"}}
        flow_title_bar.drag_target = frame_modal_dialog
        flow_title_bar.add{type="label", caption=dialog_settings.caption, style="frame_title",
            ignored_by_interaction=true}

        flow_title_bar.add{type="empty-widget", style="flib_titlebar_drag_handle", ignored_by_interaction=true}

        if dialog_settings.search_handler_name then  -- add a search field if requested
            modal_data.search_handler_name = dialog_settings.search_handler_name
            modal_data.next_search_tick = nil  -- used for rate limited search

            local searchfield = flow_title_bar.add{type="textfield", style="search_popup_textfield",
                tags={mod="fp", on_gui_text_changed="modal_searchfield"}}
            searchfield.style.width = 140
            searchfield.style.top_margin = -3
            ui_util.setup_textfield(searchfield)
            modal_elements.search_textfield = searchfield
            modal_dialog.set_searchfield_state(player)

            local search_button = flow_title_bar.add{type="sprite-button", tooltip={"fp.search_button_tt"},
                tags={mod="fp", on_gui_click="focus_modal_searchfield"}, sprite="utility/search_white",
                hovered_sprite="utility/search_black", clicked_sprite="utility/search_black",
                style="frame_action_button", mouse_button_filter={"left"}}
            search_button.style.left_margin = 4
        end

        if not dialog_settings.show_submit_button then  -- add X-to-close button if this is not a submit dialog
            local close_button = flow_title_bar.add{type="sprite-button", tooltip={"fp.close_button_tt"},
                tags={mod="fp", on_gui_click="close_modal_dialog", action="cancel"}, sprite="utility/close_white",
                hovered_sprite="utility/close_black", clicked_sprite="utility/close_black", style="frame_action_button",
                mouse_button_filter={"left"}}
            close_button.style.left_margin = 4
            close_button.style.padding = 1
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

    if dialog_settings.show_submit_button then  -- if there is a submit button, there should be a button bar
        -- Button bar
        local button_bar = frame_modal_dialog.add{type="flow", direction="horizontal",
            style="dialog_buttons_horizontal_flow"}
        button_bar.style.horizontal_spacing = 0

        -- Cancel button
        local button_cancel = button_bar.add{type="button", tags={mod="fp", on_gui_click="close_modal_dialog",
            action="cancel"}, style="back_button", caption={"fp.cancel"}, tooltip={"fp.cancel_dialog_tt"},
            mouse_button_filter={"left"}}
        button_cancel.style.minimal_width = 0
        button_cancel.style.padding = {1, 12, 0, 12}

        -- Delete button and spacers
        if dialog_settings.show_delete_button then
            local left_drag_handle = button_bar.add{type="empty-widget", style="flib_dialog_footer_drag_handle"}
            left_drag_handle.drag_target = frame_modal_dialog

            local button_delete = button_bar.add{type="button", caption={"fp.delete"}, style="red_button",
                tags={mod="fp", on_gui_click="close_modal_dialog", action="delete"}, mouse_button_filter={"left"}}
            button_delete.style.font = "default-dialog-button"
            button_delete.style.height = 32
            button_delete.style.minimal_width = 0
            button_delete.style.padding = {0, 8}

            -- If there is a delete button present, we need to set a minimum dialog width for it to look good
            frame_modal_dialog.style.minimal_width = 340
        end

        -- One 'drag handle' should always be visible
        local right_drag_handle = button_bar.add{type="empty-widget", style="flib_dialog_footer_drag_handle"}
        right_drag_handle.drag_target = frame_modal_dialog

        -- Submit button
        local button_submit = button_bar.add{type="button", tags={mod="fp", on_gui_click="close_modal_dialog",
            action="submit"}, caption={"fp.submit"}, tooltip={"fp.confirm_dialog_tt"}, style="confirm_button",
            mouse_button_filter={"left"}}
        button_submit.style.minimal_width = 0
        button_submit.style.padding = {1, 8, 0, 12}
        modal_elements.dialog_submit_button = button_submit
    end

    return frame_modal_dialog
end

local function apply_setting_overrides(base, overrides)
    for k, v in pairs(overrides) do
        local base_v = base[k]
        if type(base_v) == "table" and type(v) == "table" then
            apply_setting_overrides(base_v, v)
        else
            base[k] = v
        end
    end
end


-- ** TOP LEVEL **
-- Opens a barebone modal dialog and calls upon the given function to populate it
function modal_dialog.enter(player, dialog_settings)
    local ui_state = data_util.get("ui_state", player)

    if ui_state.modal_dialog_type ~= nil then
        -- If a dialog is currently open, and this one wants to be queued, do so
        if dialog_settings.allow_queueing then ui_state.queued_dialog_settings = dialog_settings end
        return
    end

    ui_state.modal_data = dialog_settings.modal_data or {}

    local dialog_object = _G[dialog_settings.type .. "_dialog"]
    if dialog_object.dialog_settings ~= nil then  -- collect additional settings
        local additional_settings = dialog_object.dialog_settings(ui_state.modal_data)
        apply_setting_overrides(dialog_settings, additional_settings)
    end

    local early_abort = dialog_object.early_abort_check  -- abort early if necessary
    if early_abort ~= nil and early_abort(player, ui_state.modal_data) then
        --ui_state.modal_data = nil  -- TODO this should be reset, but that breaks the stupid queueing stuff .........
        title_bar.refresh_message(player)  -- make sure eventual messages are shown
        return
    end

    ui_state.modal_dialog_type = dialog_settings.type
    ui_state.modal_data.modal_elements = {}
    ui_state.modal_data.confirmed_dialog = false

    -- Create interface_dimmer first so the layering works out correctly
    local interface_dimmer = player.gui.screen.add{type="frame", style="fp_frame_semitransparent",
        tags={mod="fp", on_gui_click="re-layer_interface_dimmer"}, visible=(not dialog_settings.skip_dimmer)}
    interface_dimmer.style.size = ui_state.main_dialog_dimensions
    interface_dimmer.location = ui_state.main_elements.main_frame.location
    ui_state.modal_data.modal_elements.interface_dimmer = interface_dimmer

    -- Create modal dialog framework and let the dialog itself fill it out
    local frame_modal_dialog = create_base_modal_dialog(player, dialog_settings, ui_state.modal_data)
    dialog_object.open(player, ui_state.modal_data)
    player.opened = frame_modal_dialog
    frame_modal_dialog.force_auto_center()  -- seems to be necessary now, not sure why
end

-- Handles the closing process of a modal dialog, reopening the main dialog thereafter
function modal_dialog.exit(player, action, skip_player_opened)
    local ui_state = data_util.get("ui_state", player)
    if ui_state.modal_dialog_type == nil then return end

    local modal_elements = ui_state.modal_data.modal_elements
    local submit_button = modal_elements.dialog_submit_button

    -- Stop exiting if trying to submit while submission is disabled
    if action == "submit" and (submit_button and not submit_button.enabled) then return end

    -- Call the closing function for this dialog, if it exists
    local closing_function = _G[ui_state.modal_dialog_type .. "_dialog"].close
    if closing_function ~= nil then closing_function(player, action) end

    -- Unregister the delayed search handler if present
    local search_tick = ui_state.modal_data.next_search_tick
    if search_tick ~= nil then data_util.nth_tick.remove(search_tick) end

    ui_state.modal_dialog_type = nil
    ui_state.modal_data = nil

    modal_elements.interface_dimmer.destroy()
    modal_elements.modal_frame.destroy()
    ui_state.modal_elements = nil

    if not skip_player_opened then player.opened = ui_state.main_elements.main_frame end
    title_bar.refresh_message(player)

    if ui_state.queued_dialog_settings ~= nil then
        modal_dialog.enter(player, ui_state.queued_dialog_settings)
        ui_state.queued_dialog_settings = nil
    end
end


function modal_dialog.set_searchfield_state(player)
    local player_table = data_util.get("table", player)
    if not player_table.ui_state.modal_dialog_type then return end
    local searchfield = player_table.ui_state.modal_data.modal_elements.search_textfield
    if not searchfield then return end

    local status = (player_table.translation_tables ~= nil)
    searchfield.enabled = status  -- disables on nil and false
    searchfield.tooltip = (status) and {"fp.searchfield_tt"} or {"fp.warning_with_icon", {"fp.searchfield_not_ready_tt"}}
end

function modal_dialog.set_submit_button_state(modal_elements, enabled, message)
    local caption = (enabled) and {"fp.submit"} or {"fp.warning_with_icon", {"fp.submit"}}
    local tooltip = (enabled) and {"fp.confirm_dialog_tt"} or {"fp.warning_with_icon", message}

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

    -- player.opened needs to be set because on_gui_closed sets it to nil
    player.opened = modal_elements.modal_frame
    modal_elements.modal_frame.ignored_by_interaction = false
    modal_elements.modal_frame.force_auto_center()

    local frame_main_dialog = ui_state.main_elements.main_frame
    frame_main_dialog.visible = true

    main_dialog.set_pause_state(player, frame_main_dialog)
end


function NTH_TICK_HANDLERS.run_delayed_modal_search(metadata)
    local player = game.get_player(metadata.player_index)
    local modal_data = data_util.get("modal_data", player)
    if not modal_data or not modal_data.modal_elements then return end

    local searchfield = modal_data.modal_elements.search_textfield
    local search_term = searchfield.text:gsub("^%s*(.-)%s*$", "%1"):lower()
    SEARCH_HANDLERS[modal_data.search_handler_name](player, search_term)
end


-- ** EVENTS **
modal_dialog.gui_events = {
    on_gui_click = {
        {
            name = "re-layer_interface_dimmer",
            handler = (function(player, _, _)
                data_util.get("modal_elements", player).modal_frame.bring_to_front()
            end)
        },
        {
            name = "re-center_modal_dialog",
            handler = (function(player, _, event)
                if event.button == defines.mouse_button_type.middle then
                    local modal_elements = data_util.get("modal_elements", player)
                    modal_elements.modal_frame.force_auto_center()
                end
            end)
        },
        {
            name = "close_modal_dialog",
            handler = (function(player, tags, _)
                modal_dialog.exit(player, tags.action)
            end)
        },
        {
            name = "focus_modal_searchfield",
            handler = (function(player, _, _)
                ui_util.select_all(data_util.get("modal_elements", player).search_textfield)
            end)
        }
    },
    on_gui_text_changed = {
        {
            name = "modal_searchfield",
            timeout = MODAL_SEARCH_LIMITING,
            handler = (function(player, _, metadata)
                local modal_data = data_util.get("modal_data", player)
                local search_tick = modal_data.search_tick
                if search_tick ~= nil then data_util.nth_tick.remove(search_tick) end

                local search_term = metadata.text:gsub("^%s*(.-)%s*$", "%1"):lower()
                SEARCH_HANDLERS[modal_data.search_handler_name](player, search_term)

                -- Set up delayed search update to circumvent issues caused by rate limiting
                modal_data.next_search_tick = data_util.nth_tick.add((game.tick + MODAL_SEARCH_LIMITING),
                    "run_delayed_modal_search", {player_index=player.index})
            end)
        }
    },
    on_gui_closed = {
        {
            name = "close_modal_dialog",
            handler = (function(player, _, event)
                local ui_state = data_util.get("ui_state", player)

                if ui_state.flags.selection_mode then
                    modal_dialog.leave_selection_mode(player)
                else
                    -- Here, we need to distinguish between submitting a dialog with E or ESC
                    modal_dialog.exit(player, (ui_state.modal_data.confirmed_dialog) and "submit" or "cancel")
                    -- If the dialog was not closed, it means submission was disabled, and we need to re-set .opened
                    if event.element.valid then player.opened = event.element end
                end

                -- Reset .confirmed_dialog if this event didn't actually lead to the dialog closing
                if event.element.valid then ui_state.modal_data.confirmed_dialog = false end
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

    fp_confirm_gui = (function(player, _)
        -- Note that a GUI was closed by confirming, so it'll try submitting on_gui_closed
        local modal_data = data_util.get("modal_data", player)
        if modal_data ~= nil then modal_data.confirmed_dialog = true end
    end),

    fp_focus_searchfield = (function(player, _)
        local ui_state = data_util.get("ui_state", player)

        if ui_state.modal_dialog_type ~= nil then
            local textfield_search = ui_state.modal_data.modal_elements.search_textfield
            if textfield_search then ui_util.select_all(textfield_search) end
        end
    end)
}
