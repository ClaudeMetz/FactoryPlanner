modal_dialog = {}

---@alias ModalDialogType string

---@class ModalData
---@field modal_elements table
---@field search_handler_name string?
---@field next_search_tick MapTick?
---@field reset_handler_name string?
---@field dialog_maximal_height number
---@field confirmed_dialog boolean

---@class ModalDialogSettings
---@field caption LocalisedString?
---@field search_handler_name string?
---@field reset_handler_name string?
---@field subheader_text LocalisedString?
---@field subheader_tooltip LocalisedString?
---@field disable_scroll_pane boolean?
---@field secondary_frame boolean?
---@field show_submit_button boolean?
---@field show_delete_button boolean?

---@class ExitModalDialogTags
---@field action GUICloseAction

---@alias GUICloseAction "submit" | "cancel" | "delete"

-- ** LOCAL UTIL **
---@param player LuaPlayer
---@param dialog_settings ModalDialogSettings
---@param modal_data ModalData
---@return LuaGuiElement
local function create_base_dialog(player, dialog_settings, modal_data)
    local modal_elements = modal_data.modal_elements

    local frame_modal_dialog = player.gui.screen.add{type="frame", direction="vertical",
        tags={mod="fp", on_gui_closed="close_modal_dialog"}}
    frame_modal_dialog.style.minimal_width = 220
    modal_elements.modal_frame = frame_modal_dialog

    -- Title bar
    if dialog_settings.caption then
        local flow_title_bar = frame_modal_dialog.add{type="flow", direction="horizontal", style="frame_header_flow",
            tags={mod="fp", on_gui_click="re-center_modal_dialog"}}
        flow_title_bar.drag_target = frame_modal_dialog
        flow_title_bar.add{type="label", caption=dialog_settings.caption, style="fp_label_frame_title",
            ignored_by_interaction=true}

        flow_title_bar.add{type="empty-widget", style="fflib_titlebar_drag_handle", ignored_by_interaction=true}

        if dialog_settings.search_handler_name then  -- add a search field if requested
            modal_data.search_handler_name = dialog_settings.search_handler_name
            modal_data.next_search_tick = nil  -- used for rate limited search

            local searchfield = flow_title_bar.add{type="textfield", style="search_popup_textfield",
                tags={mod="fp", on_gui_text_changed="modal_searchfield"}}
            searchfield.style.size = {150, 26}
            searchfield.style.top_margin = -1
            modal_elements.search_textfield = searchfield
            modal_dialog.set_searchfield_state(player)

            flow_title_bar.add{type="sprite-button", tooltip={"fp.search_button_tt"},
                tags={mod="fp", on_gui_click="focus_modal_searchfield"}, sprite="utility/search",
                style="fp_button_frame", mouse_button_filter={"left"}}
        end

        -- Titlebar flow
        local titlebar_flow = flow_title_bar.add{type="flow", direction="horizontal"}
        titlebar_flow.visible = false
        modal_elements.titlebar_flow = titlebar_flow

        if dialog_settings.reset_handler_name then  -- add a reset button if requested
            modal_data.reset_handler_name = dialog_settings.reset_handler_name

            local reset_toggle = flow_title_bar.add{type="sprite-button", tooltip={"fp.reset_toggle_tt"},
                tags={mod="fp", on_gui_click="modal_dialog_toggle_reset"}, sprite="utility/reset",
                style="tool_button_red", mouse_button_filter={"left"}}
            reset_toggle.style.size = 24
            reset_toggle.style.padding = 1
            modal_elements.toggle_reset = reset_toggle

            local reset_confirm = flow_title_bar.add{type="sprite-button", tooltip={"fp.reset_confirm_tt"},
                tags={mod="fp", on_gui_click="modal_dialog_confirm_reset"}, sprite="utility/check_mark",
                style="fflib_tool_button_light_green", visible=false, mouse_button_filter={"left"}}
            reset_confirm.style.size = 24
            reset_confirm.style.padding = -1
            modal_elements.confirm_reset = reset_confirm
        end

        if not dialog_settings.show_submit_button then  -- add X-to-close button if this is not a submit dialog
            local close_button = flow_title_bar.add{type="sprite-button", tooltip={"fp.close_button_tt"},
                tags={mod="fp", on_gui_click="exit_modal_dialog", action="cancel"}, sprite="utility/close",
                style="fp_button_frame", mouse_button_filter={"left"}}
            close_button.style.padding = 1
        end
    end

    local flow_content = frame_modal_dialog.add{type="flow", direction="horizontal"}
    flow_content.style.horizontal_spacing = 12

    -- Content frame
    local content_frame = flow_content.add{type="frame", direction="vertical", style="inside_shallow_frame"}
    content_frame.style.vertically_stretchable = true

    if dialog_settings.subheader_text then
        local subheader = content_frame.add{type="frame", direction="horizontal", style="subheader_frame"}
        subheader.style.horizontally_stretchable = true
        subheader.style.padding = 12
        subheader.add{type="label", caption=dialog_settings.subheader_text,
            tooltip=dialog_settings.subheader_tooltip, style="semibold_label"}
    end

    local scroll_pane = content_frame.add{type="scroll-pane", style="fflib_naked_scroll_pane"}
    if dialog_settings.disable_scroll_pane then scroll_pane.vertical_scroll_policy = "never" end
    modal_elements.content_frame = scroll_pane

    -- Secondary frame
    if dialog_settings.secondary_frame then
        local frame_secondary = flow_content.add{type="frame", direction="vertical", style="inside_shallow_frame"}

        local scroll_pane_secondary = frame_secondary.add{type="scroll-pane", style="fflib_naked_scroll_pane"}
        scroll_pane_secondary.style.padding = 12

        modal_elements.secondary_frame = scroll_pane_secondary
    end

    -- Auxiliary flow
    modal_elements.auxiliary_flow = frame_modal_dialog.add{type="flow", direction="vertical"}

    local ui_state = lib.globals.ui_state(player)
    local dialog_max_height = ui_state.main_dialog_dimensions--[[@cast -nil]].height * 0.96
    modal_data.dialog_maximal_height = dialog_max_height
    frame_modal_dialog.style.maximal_height = dialog_max_height  ---@as integer

    if dialog_settings.show_submit_button then  -- if there is a submit button, there should be a button bar
        -- Button bar
        local button_bar = frame_modal_dialog.add{type="flow", direction="horizontal",
            style="dialog_buttons_horizontal_flow"}

        -- Cancel button
        local tags = {mod="fp", on_gui_click="exit_modal_dialog", action="cancel"}  ---@type ExitModalDialogTags
        local button_cancel = button_bar.add{type="button", tags=tags, style="back_button", caption={"fp.cancel"}, tooltip={"fp.cancel_dialog_tt"}, mouse_button_filter={"left"}}
        button_cancel.style.minimal_width = 0
        button_cancel.style.padding = {1, 12, 0, 12}

        -- Delete button and spacers
        if dialog_settings.show_delete_button then
            local left_drag_handle = button_bar.add{type="empty-widget", style="fflib_dialog_footer_drag_handle"}
            left_drag_handle.drag_target = frame_modal_dialog

            local tags = {mod="fp", on_gui_click="exit_modal_dialog", action="delete"}  ---@type ExitModalDialogTags
            local button_delete = button_bar.add{type="button", tags=tags, caption={"fp.delete"},
                style="red_button", mouse_button_filter={"left"}}
            button_delete.style.font = "default-dialog-button"
            button_delete.style.height = 32
            button_delete.style.minimal_width = 0
            button_delete.style.padding = {0, 8}

            -- If there is a delete button present, we need to set a minimum dialog width for it to look good
            frame_modal_dialog.style.minimal_width = 340
        end

        -- One 'drag handle' should always be visible
        local right_drag_handle = button_bar.add{type="empty-widget", style="fflib_dialog_footer_drag_handle"}
        right_drag_handle.drag_target = frame_modal_dialog

        -- Submit button
        local tags = {mod="fp", on_gui_click="exit_modal_dialog", action="submit"}  ---@type ExitModalDialogTags
        local button_submit = button_bar.add{type="button", tags=tags, caption={"fp.submit"},
            tooltip={"fp.confirm_dialog_tt"}, style="confirm_button", mouse_button_filter={"left"}}
        button_submit.style.minimal_width = 0
        button_submit.style.padding = {1, 8, 0, 12}
        modal_elements.dialog_submit_button = button_submit
    end

    return frame_modal_dialog
end

-- ** TOP LEVEL **
-- Opens a barebone modal dialog and calls upon the given function to populate it
---@param player LuaPlayer
---@param metadata table
---@param dialog_open fun(player: LuaPlayer, modal_data: ModalData)
---@param early_abort? fun(player: LuaPlayer, modal_data: ModalData): boolean
function modal_dialog.enter(player, metadata, dialog_open, early_abort)
    if early_abort ~= nil and early_abort(player, metadata.modal_data or {}) then return end

    local ui_state = lib.globals.ui_state(player)
    ui_state.modal_data = metadata.modal_data or {}
    ui_state.modal_data.modal_elements = {}
    ui_state.modal_data.confirmed_dialog = false

    -- Create interface_dimmer first so the layering works out correctly
    if main_dialog.is_in_focus(player) then
        local interface_dimmer = player.gui.screen.add{type="frame", style="fp_frame_semitransparent",
            tags={mod="fp", on_gui_click="re-layer_interface_dimmer"}, visible=(not metadata.skip_dimmer)}
        interface_dimmer.style.size = ui_state.main_dialog_dimensions
        interface_dimmer.location = ui_state.main_elements.main_frame.location
        ui_state.modal_data.modal_elements.interface_dimmer = interface_dimmer
    end

    -- Create modal dialog framework and let the dialog itself fill it out
    ui_state.modal_dialog_type = metadata.dialog
    local frame_modal_dialog = create_base_dialog(player, metadata, ui_state.modal_data)
    dialog_open(player, ui_state.modal_data)

    frame_modal_dialog.force_auto_center()
    player.opened = frame_modal_dialog
end

-- Handles the closing process of a modal dialog, reopening the main dialog thereafter
---@param player LuaPlayer
---@param action GUICloseAction
---@param skip_opened boolean
---@param dialog_close? fun(player: LuaPlayer, action: GUICloseAction)
function modal_dialog.exit(player, action, skip_opened, dialog_close)
    local ui_state = lib.globals.ui_state(player)  -- dialog guaranteed to be open
    ---@cast ui_state.modal_data -nil

    local modal_elements = ui_state.modal_data.modal_elements
    local submit_button = modal_elements.dialog_submit_button

    -- Stop exiting if trying to submit while submission is disabled
    if action == "submit" and (submit_button and not submit_button.enabled) then return end

    -- Call the closing function for this dialog, if it has one
    if dialog_close ~= nil then dialog_close(player, action) end

    -- Unregister the delayed search handler if present
    local search_tick = ui_state.modal_data.next_search_tick
    if search_tick ~= nil then lib.nth_tick.cancel(search_tick) end

    ui_state.modal_dialog_type = nil
    ui_state.modal_data = nil

   if modal_elements.interface_dimmer then modal_elements.interface_dimmer.destroy() end
    modal_elements.modal_frame.destroy()

    if not skip_opened then player.opened = ui_state.main_elements.main_frame end
end


---@param player LuaPlayer
---@param menu_tags Tags
---@param handler string
---@param actions GUIActionTable
---@param location GuiLocation
function modal_dialog.open_context_menu(player, menu_tags, handler, actions, location)
    local ui_state = lib.globals.ui_state(player)
    local frame_modal_dialog = player.gui.screen.add{type="frame", direction="vertical",
        tags={mod="fp", on_gui_closed="close_context_menu"}, style="fp_naked_frame"}
    frame_modal_dialog.style.padding = 0  -- make sure the visible part starts right on the cursor
    ui_state.context_menu = frame_modal_dialog

    local button_flow = frame_modal_dialog.add{type="flow", direction="vertical"}
    button_flow.style.vertical_spacing = 0

    local action_counter = 0
    local active_limitations = lib.actions.current_limitations(player)

    for _, action in pairs(actions) do
        if lib.actions.allowed(action.limitations, active_limitations) then
            local caption = {"fp.tt_title", {"fp.action_" .. action.name}}
            ---@class ChooseContextActionTags
            ---@field tags Tags
            ---@field handler string
            ---@field action string
            local tags = {mod="fp", on_gui_click="choose_context_action", tags=menu_tags,
                handler=handler, action=action.name}
            local button = button_flow.add{type="button", tags=tags, style="list_box_item",
                mouse_button_filter={"left"}}
            button.style.width = MAGIC_NUMBERS.context_menu_width

            local flow = button.add{type="flow", direction="horizontal"}
            flow.style.width = MAGIC_NUMBERS.context_menu_width
            flow.style.right_padding = 20
            flow.add{type="label", caption=caption, style="bold_label"}
            flow.add{type="empty-widget", style="fflib_horizontal_pusher"}
            flow.add{type="label", caption=action.shortcut_string}

            action_counter = action_counter + 1
        end
    end
    local dialog_height = action_counter * 28
    button_flow.style.height = dialog_height

    -- Make sure the dialog doesn't go off-screen at the bottom or the right
    ---@cast location {x: number, y: number}
    local scaled_dialog_height = dialog_height * player.display_scale
    local distance_to_bottom = player.display_resolution.height - location.y
    if distance_to_bottom < scaled_dialog_height then location.y = location.y - scaled_dialog_height end

    local scaled_dialog_width = MAGIC_NUMBERS.context_menu_width * player.display_scale
    local distance_to_right = player.display_resolution.width - location.x
    if distance_to_right < scaled_dialog_width then location.x = location.x - scaled_dialog_width end

    frame_modal_dialog.location = location  ---@as GuiLocation
    player.opened = frame_modal_dialog
end

---@param player LuaPlayer
function modal_dialog.close_context_menu(player)
    local ui_state = lib.globals.ui_state(player)
    if not ui_state.context_menu then return end

    ui_state.context_menu.destroy()
    ui_state.context_menu = nil

    if ui_state.modal_dialog_type ~= nil then
        player.opened = ui_state.modal_data--[[@cast -nil]].modal_elements.modal_frame
    else
        player.opened = ui_state.main_elements.main_frame
    end
end


---@param player LuaPlayer
function modal_dialog.set_searchfield_state(player)
    local player_table = lib.globals.player_table(player)
    if not player_table.ui_state.modal_dialog_type then return end
    local modal_data = player_table.ui_state.modal_data  ---@as ModalData
    local searchfield = modal_data.modal_elements.search_textfield
    if not searchfield then return end

    local status = (player_table.translation_tables ~= nil)
    searchfield.enabled = status  -- disables on nil and false
    searchfield.tooltip = (status) and {"fp.searchfield_tt"} or {"fp.warning_with_icon", {"fp.searchfield_not_ready_tt"}}
end

---@param player LuaPlayer
function modal_dialog.run_search(player)
    local modal_data = lib.globals.modal_data(player)
    if not modal_data or not modal_data.modal_elements then return end

    local searchfield = modal_data.modal_elements.search_textfield
    local search_term = helpers.multilingual_to_lower(searchfield.text)
    local trimmed_search_term = search_term:gsub("^%s*(.-)%s*$", "%1")
    GLOBAL_HANDLERS[modal_data.search_handler_name](player, trimmed_search_term)
end

---@param modal_elements table
---@param enabled boolean
---@param message LocalisedString
function modal_dialog.set_submit_button_state(modal_elements, enabled, message)
    local caption = (enabled) and {"fp.submit"} or {"fp.warning_with_icon", {"fp.submit"}}
    local tooltip = (enabled) and {"fp.confirm_dialog_tt"} or {"fp.warning_with_icon", message}

    local button = modal_elements.dialog_submit_button
    button.style.left_padding = (enabled) and 12 or 6
    button.enabled = enabled
    button.caption = caption
    button.tooltip = tooltip
end


---@param player LuaPlayer
---@param selector_name string
function modal_dialog.enter_selection_mode(player, selector_name)
    local ui_state = lib.globals.ui_state(player)
    ---@cast ui_state.modal_data -nil

    player.clear_cursor()
    player.cursor_stack--[[@cast -nil]].set_stack(selector_name)
    ui_state.active_selector = selector_name

    local frame_main_dialog = ui_state.main_elements.main_frame
    frame_main_dialog.visible = false
    main_dialog.set_pause_state(player, frame_main_dialog, true)

    local modal_elements = ui_state.modal_data.modal_elements
    modal_elements.interface_dimmer.visible = false

    modal_elements.modal_frame.ignored_by_interaction = true
    modal_elements.modal_frame.location = {25, 50}
end


---@param player LuaPlayer
function modal_dialog.leave_selection_mode(player)
    local ui_state = lib.globals.ui_state(player)
    ---@cast ui_state.modal_data -nil

    ---@cast player.cursor_stack -nil
    if player.cursor_stack.valid_for_read and
            player.cursor_stack.name == ui_state.active_selector then
        player.cursor_stack.clear()
    end
    ui_state.active_selector = nil

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
local listeners = {}  ---@type ListenerDefinitions

listeners.gui = {
    on_gui_click = {
        {
            name = "re-layer_interface_dimmer",
            handler = function(player, _, _)
                lib.globals.modal_elements(player).modal_frame.bring_to_front()
            end
        },
        {
            name = "re-center_modal_dialog",
            handler = function(player, _, event)
                ---@cast event EventData.on_gui_click
                if event.button == defines.mouse_button_type.middle then
                    local modal_elements = lib.globals.modal_elements(player)
                    modal_elements.modal_frame.force_auto_center()
                end
            end
        },
        {
            name = "exit_modal_dialog",
            handler = function(player, tags, _)
                ---@cast tags ExitModalDialogTags
                lib.gui.close_dialog(player, tags.action)
            end
        },
        {
            name = "choose_context_action",
            handler = function(player, tags, _)
                ---@cast tags ChooseContextActionTags
                modal_dialog.close_context_menu(player)
                MODIFIER_ACTIONS[tags.handler].handler(player, tags.tags, tags.action)
            end
        },
        {
            name = "focus_modal_searchfield",
            handler = function(player, _, _)
                lib.gui.select_all(lib.globals.modal_elements(player).search_textfield)
            end
        },
        {
            name = "modal_dialog_toggle_reset",
            handler = function(player, _, _)
                local modal_elements = lib.globals.modal_elements(player)
                modal_elements.toggle_reset.visible = false
                modal_elements.confirm_reset.visible = true
            end
        },
        {
            name = "modal_dialog_confirm_reset",
            handler = function(player, _, _)
                local modal_data = lib.globals.modal_data(player)  ---@as ModalData
                modal_data.modal_elements.toggle_reset.visible = true
                modal_data.modal_elements.confirm_reset.visible = false
                GLOBAL_HANDLERS[modal_data.reset_handler_name](player)
            end
        }
    },
    on_gui_text_changed = {
        {
            name = "modal_searchfield",
            timeout = MAGIC_NUMBERS.modal_search_rate_limit,
            handler = function(player, _, _)
                local modal_data = lib.globals.modal_data(player)  ---@as ModalData
                local search_tick = modal_data.next_search_tick
                if search_tick ~= nil then lib.nth_tick.cancel(search_tick) end

                modal_dialog.run_search(player)

                -- Set up delayed search update to circumvent issues caused by rate limiting
                local desired_tick = game.tick + MAGIC_NUMBERS.modal_search_rate_limit

                ---@class RunDelayedModalSearchMetadata
                ---@field player_index PlayerIndex
                local metadata = {player_index=player.index}
                modal_data.next_search_tick = lib.nth_tick.register(desired_tick,
                    "run_delayed_modal_search", metadata)
            end
        }
    },
    on_gui_closed = {
        {
            name = "close_modal_dialog",
            handler = function(player, _, event)
                ---@cast event EventData.on_gui_closed
                local element = event.element  ---@as LuaGuiElement

                local ui_state = lib.globals.ui_state(player)
                ---@cast ui_state.modal_data -nil

                if ui_state.active_selector ~= nil then
                    modal_dialog.leave_selection_mode(player)
                elseif ui_state.context_menu == nil then  -- don't close if opening context menu
                    -- Here, we need to distinguish between submitting a dialog with E or ESC
                    local action = (ui_state.modal_data.confirmed_dialog) and "submit" or "cancel"
                    lib.gui.close_dialog(player, action)
                    -- If the dialog was not closed, it means submission was disabled, and we need to re-set .opened
                    if element.valid then player.opened = element end
                end

                -- Reset .confirmed_dialog if this event didn't actually lead to the dialog closing
                if element.valid and ui_state.modal_data then ui_state.modal_data.confirmed_dialog = false end
            end
        },
        {
            name = "close_context_menu",
            handler = modal_dialog.close_context_menu
        }
    }
}  ---@as GUIListenerDefinition

listeners.player = {
    fp_confirm_dialog = function(player, _)
        if lib.globals.ui_state(player).active_selector == nil then
            lib.gui.close_dialog(player, "submit")
        end
    end,

    fp_confirm_gui = function(player, _)
        -- Note that a GUI was closed by confirming, so it'll try submitting on_gui_closed
        local modal_data = lib.globals.modal_data(player)
        if modal_data ~= nil then modal_data.confirmed_dialog = true end
    end,

    fp_focus_searchfield = function(player, _)
        local ui_state = lib.globals.ui_state(player)

        if ui_state.modal_dialog_type ~= nil then  ---@cast ui_state.modal_data -nil
            local textfield_search = ui_state.modal_data.modal_elements.search_textfield
            if textfield_search then lib.gui.select_all(textfield_search) end
        end
    end
}

listeners.global = {
    run_delayed_modal_search = function(metadata)
        ---@cast metadata RunDelayedModalSearchMetadata
        local player = game.get_player(metadata.player_index)  ---@as LuaPlayer
        modal_dialog.run_search(player)
    end
}

return { listeners }
