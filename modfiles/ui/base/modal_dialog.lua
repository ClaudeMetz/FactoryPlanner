modal_dialog = {}

---@alias ModalDialogType string

-- ** LOCAL UTIL **
local function create_base_modal_dialog(player, dialog_settings, modal_data)
    local modal_elements = modal_data.modal_elements

    local frame_modal_dialog = player.gui.screen.add{type="frame", direction="vertical",
        tags={mod="fp", on_gui_closed="close_modal_dialog"}}
    frame_modal_dialog.style.minimal_width = 220
    modal_elements.modal_frame = frame_modal_dialog

    -- Title bar
    if dialog_settings.caption ~= nil then
        local flow_title_bar = frame_modal_dialog.add{type="flow", direction="horizontal", style="frame_header_flow",
            tags={mod="fp", on_gui_click="re-center_modal_dialog"}}
        flow_title_bar.drag_target = frame_modal_dialog
        flow_title_bar.add{type="label", caption=dialog_settings.caption, style="fp_label_frame_title",
            ignored_by_interaction=true}

        flow_title_bar.add{type="empty-widget", style="flib_titlebar_drag_handle", ignored_by_interaction=true}

        if dialog_settings.search_handler_name then  -- add a search field if requested
            modal_data.search_handler_name = dialog_settings.search_handler_name
            modal_data.next_search_tick = nil  -- used for rate limited search

            local searchfield = flow_title_bar.add{type="textfield", style="search_popup_textfield",
                tags={mod="fp", on_gui_text_changed="modal_searchfield"}}
            searchfield.style.width = 140
            searchfield.style.top_margin = -3
            modal_elements.search_textfield = searchfield
            modal_dialog.set_searchfield_state(player)

            local search_button = flow_title_bar.add{type="sprite-button", tooltip={"fp.search_button_tt"},
                tags={mod="fp", on_gui_click="focus_modal_searchfield"}, sprite="utility/search",
                style="frame_action_button", mouse_button_filter={"left"}}
            search_button.style.left_margin = 4
        end

        if dialog_settings.reset_handler_name then  -- add a reset button if requested
            modal_data.reset_handler_name = dialog_settings.reset_handler_name

            local reset_button = flow_title_bar.add{type="sprite-button", tooltip={"fp.reset_button_tt"},
                tags={mod="fp", on_gui_click="reset_modal_dialog"}, sprite="utility/reset",
                style="tool_button_red", mouse_button_filter={"left"}}
            reset_button.style.size = 24
            reset_button.style.padding = 1
        end

        if not dialog_settings.show_submit_button then  -- add X-to-close button if this is not a submit dialog
            local close_button = flow_title_bar.add{type="sprite-button", tooltip={"fp.close_button_tt"},
                tags={mod="fp", on_gui_click="close_modal_dialog", action="cancel"}, sprite="utility/close",
                style="frame_action_button", mouse_button_filter={"left"}}
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
    local dialog_max_height = (util.globals.ui_state(player).main_dialog_dimensions.height - 80) * 0.95
    modal_data.dialog_maximal_height = dialog_max_height
    main_content_element.style.maximal_height = dialog_max_height

    if dialog_settings.show_submit_button then  -- if there is a submit button, there should be a button bar
        -- Button bar
        local button_bar = frame_modal_dialog.add{type="flow", direction="horizontal",
            style="dialog_buttons_horizontal_flow"}

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

local function run_delayed_modal_search(metadata)
    local player = game.get_player(metadata.player_index)  --[[@as LuaPlayer]]
    local modal_data = util.globals.modal_data(player)
    if not modal_data or not modal_data.modal_elements then return end

    local searchfield = modal_data.modal_elements.search_textfield
    local search_term = searchfield.text:gsub("^%s*(.-)%s*$", "%1"):lower()
    GLOBAL_HANDLERS[modal_data.search_handler_name](player, search_term)
end


-- ** TOP LEVEL **
-- Opens a barebone modal dialog and calls upon the given function to populate it
function modal_dialog.enter(player, metadata, dialog_open, early_abort)
    if early_abort ~= nil and early_abort(player, metadata.modal_data or {}) then return end

    local ui_state = util.globals.ui_state(player)
    ui_state.modal_dialog_type = metadata.dialog
    ui_state.modal_data = metadata.modal_data or {}
    ui_state.modal_data.modal_elements = {}
    ui_state.modal_data.confirmed_dialog = false

    -- Create interface_dimmer first so the layering works out correctly
    local interface_dimmer = player.gui.screen.add{type="frame", style="fp_frame_semitransparent",
        tags={mod="fp", on_gui_click="re-layer_interface_dimmer"}, visible=(not metadata.skip_dimmer)}
    interface_dimmer.style.size = ui_state.main_dialog_dimensions
    interface_dimmer.location = ui_state.main_elements.main_frame.location
    ui_state.modal_data.modal_elements.interface_dimmer = interface_dimmer

    -- Create modal dialog framework and let the dialog itself fill it out
    local frame_modal_dialog = create_base_modal_dialog(player, metadata, ui_state.modal_data)
    dialog_open(player, ui_state.modal_data)
    player.opened = frame_modal_dialog
    frame_modal_dialog.force_auto_center()  -- seems to be necessary now, not sure why
end

-- Handles the closing process of a modal dialog, reopening the main dialog thereafter
function modal_dialog.exit(player, action, skip_opened, dialog_close)
    local ui_state = util.globals.ui_state(player)  -- dialog guaranteed to be open

    local modal_elements = ui_state.modal_data.modal_elements
    local submit_button = modal_elements.dialog_submit_button

    -- Stop exiting if trying to submit while submission is disabled
    if action == "submit" and (submit_button and not submit_button.enabled) then return end

    -- Call the closing function for this dialog, if it has one
    if dialog_close ~= nil then dialog_close(player, action) end

    -- Unregister the delayed search handler if present
    local search_tick = ui_state.modal_data.next_search_tick
    if search_tick ~= nil then util.nth_tick.cancel(search_tick) end

    ui_state.modal_dialog_type = nil
    ui_state.modal_data = nil

    modal_elements.interface_dimmer.destroy()
    modal_elements.modal_frame.destroy()

    if not skip_opened then player.opened = ui_state.main_elements.main_frame end
end


function modal_dialog.set_searchfield_state(player)
    local player_table = util.globals.player_table(player)
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
    local ui_state = util.globals.ui_state(player)
    ui_state.selection_mode = true
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
    local ui_state = util.globals.ui_state(player)
    ui_state.selection_mode = false
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


-- ** EVENTS **
local listeners = {}

listeners.gui = {
    on_gui_click = {
        {
            name = "re-layer_interface_dimmer",
            handler = (function(player, _, _)
                util.globals.modal_elements(player).modal_frame.bring_to_front()
            end)
        },
        {
            name = "re-center_modal_dialog",
            handler = (function(player, _, event)
                if event.button == defines.mouse_button_type.middle then
                    local modal_elements = util.globals.modal_elements(player)
                    modal_elements.modal_frame.force_auto_center()
                end
            end)
        },
        {
            name = "close_modal_dialog",
            handler = (function(player, tags, _)
                util.raise.close_dialog(player, tags.action)
            end)
        },
        {
            name = "focus_modal_searchfield",
            handler = (function(player, _, _)
                util.gui.select_all(util.globals.modal_elements(player).search_textfield)
            end)
        },
        {
            name = "reset_modal_dialog",
            handler = (function(player, _, _)
                local modal_data = util.globals.modal_data(player)  --[[@as table]]
                GLOBAL_HANDLERS[modal_data.reset_handler_name](player)
            end)
        }
    },
    on_gui_text_changed = {
        {
            name = "modal_searchfield",
            timeout = MAGIC_NUMBERS.modal_search_rate_limit,
            handler = (function(player, _, metadata)
                local modal_data = util.globals.modal_data(player)  --[[@as table]]
                local search_tick = modal_data.search_tick
                if search_tick ~= nil then util.nth_tick.cancel(search_tick) end

                local search_term = metadata.text:gsub("^%s*(.-)%s*$", "%1"):lower()
                GLOBAL_HANDLERS[modal_data.search_handler_name](player, search_term)

                -- Set up delayed search update to circumvent issues caused by rate limiting
                local desired_tick = game.tick + MAGIC_NUMBERS.modal_search_rate_limit
                modal_data.next_search_tick = util.nth_tick.register(desired_tick,
                    "run_delayed_modal_search", {player_index=player.index})
            end)
        }
    },
    on_gui_closed = {
        {
            name = "close_modal_dialog",
            handler = (function(player, _, event)
                local ui_state = util.globals.ui_state(player)

                if ui_state.selection_mode then
                    modal_dialog.leave_selection_mode(player)
                else
                    -- Here, we need to distinguish between submitting a dialog with E or ESC
                    util.raise.close_dialog(player, (ui_state.modal_data.confirmed_dialog) and "submit" or "cancel")
                    -- If the dialog was not closed, it means submission was disabled, and we need to re-set .opened
                    if event.element.valid then player.opened = event.element end
                end

                -- TODO Not sure why I need this check, possibly a multiplayer latency thing?
                if not ui_state.modal_data then return end

                -- Reset .confirmed_dialog if this event didn't actually lead to the dialog closing
                if event.element.valid then ui_state.modal_data.confirmed_dialog = false end
            end)
        }
    }
}

listeners.misc = {
    fp_confirm_dialog = (function(player, _)
        if not util.globals.ui_state(player).selection_mode then
            util.raise.close_dialog(player, "submit")
        end
    end),

    fp_confirm_gui = (function(player, _)
        -- Note that a GUI was closed by confirming, so it'll try submitting on_gui_closed
        local modal_data = util.globals.modal_data(player)
        if modal_data ~= nil then modal_data.confirmed_dialog = true end
    end),

    fp_focus_searchfield = (function(player, _)
        local ui_state = util.globals.ui_state(player)

        if ui_state.modal_dialog_type ~= nil then
            local textfield_search = ui_state.modal_data.modal_elements.search_textfield
            if textfield_search then util.gui.select_all(textfield_search) end
        end
    end)
}

listeners.global = {
    run_delayed_modal_search = run_delayed_modal_search
}

return { listeners }
