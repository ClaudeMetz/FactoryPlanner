main_dialog = {}

---@param player LuaPlayer
---@return DisplayResolution
function main_dialog.get_dimensions(player)
    local preferences = lib.globals.preferences(player)
    local scaled_resolution = lib.gui.calculate_scaled_resolution(player)
    local width = math.floor(scaled_resolution.width * preferences.main_width_percentage / 100)
    local height = math.floor(scaled_resolution.height * preferences.main_height_percentage / 100)

    return {width = width, height = height}  ---@as DisplayResolution
end


---@param player LuaPlayer
---@return integer
function main_dialog.get_content_width(player)
    return main_dialog.get_dimensions(player).width - MAGIC_NUMBERS.list_width - (3 * MAGIC_NUMBERS.frame_spacing)
end


---@param metadata InterfaceToggleMetadata
local function interface_toggle(metadata)
    local player = game.get_player(metadata.player_index)  ---@as LuaPlayer
    local compact_view = lib.globals.ui_state(player).compact_view
    if compact_view then compact_dialog.toggle(player)
    else main_dialog.toggle(player) end
end


---@param player LuaPlayer
---@param default_visibility boolean
function main_dialog.rebuild(player, default_visibility)
    local ui_state = lib.globals.ui_state(player)
    local main_elements = ui_state.main_elements

    local interface_visible = default_visibility
    local main_frame = main_elements.main_frame
    -- Delete the existing interface if there is one
    if main_frame ~= nil then
        if main_frame.valid then
            interface_visible = main_frame.visible
            main_frame.destroy()
        end

        ui_state.main_elements = {}  -- reset all main element references
        main_elements = ui_state.main_elements
    end

    -- Create and configure the top-level frame
    local frame_main_dialog = player.gui.screen.add{type="frame", direction="vertical",
        visible=interface_visible, tags={mod="fp", on_gui_closed="close_main_dialog"},
        name="fp_frame_main_dialog"}
    main_elements["main_frame"] = frame_main_dialog

    local dimensions = main_dialog.get_dimensions(player)
    frame_main_dialog.style.size = {dimensions.width, dimensions.height}
    main_dialog.center(player)

    -- Create the actual dialog structure
    local frame_spacing = MAGIC_NUMBERS.frame_spacing
    main_elements.flows = {}

    local top_horizontal = frame_main_dialog.add{type="flow", direction="horizontal"}
    main_elements.flows["top_horizontal"] = top_horizontal

    local main_horizontal = frame_main_dialog.add{type="flow", direction="horizontal"}
    main_horizontal.style.horizontal_spacing = frame_spacing
    main_horizontal.style.vertically_stretchable = true
    main_elements.flows["main_horizontal"] = main_horizontal

    local left_vertical = main_horizontal.add{type="flow", direction="vertical"}
    left_vertical.style.vertical_spacing = frame_spacing
    left_vertical.style.width = MAGIC_NUMBERS.list_width
    left_vertical.style.vertically_stretchable = true
    main_elements.flows["left_vertical"] = left_vertical

    local right_vertical = main_horizontal.add{type="flow", direction="vertical"}
    right_vertical.style.vertical_spacing = frame_spacing
    right_vertical.style.width = main_dialog.get_content_width(player)
    main_elements.flows["right_vertical"] = right_vertical

    item_views.rebuild_data(player)
    lib.gui.run_build(player, "main_dialog", nil)  -- tells all elements to build themselves
    item_views.rebuild_interface(player)

    modal_dialog.refresh_layering(player)
    if interface_visible and not ui_state.modal_data and not ui_state.context_menu then
        player.opened = frame_main_dialog
    end
    main_dialog.set_pause_state(player, frame_main_dialog)
end

---@param player LuaPlayer
---@param skip_opened boolean?
function main_dialog.toggle(player, skip_opened)
    local ui_state = lib.globals.ui_state(player)
    local frame_main_dialog = ui_state.main_elements.main_frame

    if frame_main_dialog == nil or not frame_main_dialog.valid then
        main_dialog.rebuild(player, true)  -- sets opened and paused-state itself

    -- Don't toggle if a modal dialog or context menu is opened
    elseif ui_state.modal_dialog_type == nil and ui_state.context_menu == nil then
        local new_dialog_visibility = not frame_main_dialog.visible
        frame_main_dialog.visible = new_dialog_visibility
        if not skip_opened then  -- flag used only for hacky internal reasons
            player.opened = (new_dialog_visibility) and frame_main_dialog or nil
        end

        main_dialog.set_pause_state(player, frame_main_dialog)

        -- Make sure FP is not behind some vanilla interfaces
        if new_dialog_visibility then frame_main_dialog.bring_to_front() end
    end
end

-- Centers main dialog properly, ignoring the hotbar
---@param player LuaPlayer
function main_dialog.center(player)
    local ui_state = lib.globals.ui_state(player)
    local main_frame = ui_state.main_elements.main_frame
    if not main_frame or not main_frame.valid then return end
    local dimensions = main_dialog.get_dimensions(player)

    local resolution, scale = player.display_resolution, player.display_scale
    local x_offset = ((resolution.width - (dimensions.width * scale)) / 2)
    local y_offset = ((resolution.height - (dimensions.height * scale)) / 2)
    main_frame.location = {x_offset, y_offset}
end

---@param player LuaPlayer
local function resize_main_dialog(player)
    local main_elements = lib.globals.main_elements(player)
    local main_frame = main_elements.main_frame
    if not main_frame or not main_frame.valid then return end

    main_dialog.rebuild(player, false)
end


-- Returns true when the main dialog is open while no modal dialogs are
---@param player LuaPlayer
---@return boolean
function main_dialog.is_in_focus(player)
    local frame_main_dialog = lib.globals.main_elements(player).main_frame  ---@as LuaGuiElement
    return (frame_main_dialog ~= nil and frame_main_dialog.valid and frame_main_dialog.visible
        and lib.globals.ui_state(player).modal_dialog_type == nil)
end

-- Sets the game.paused-state as is appropriate
---@param player LuaPlayer
---@param frame_main_dialog LuaGuiElement
---@param force_false boolean?
function main_dialog.set_pause_state(player, frame_main_dialog, force_false)
    -- Don't touch paused-state if this is a multiplayer session or the editor is active
    if game.is_multiplayer() or player.physical_controller_type == defines.controllers.editor then return end
    if not frame_main_dialog or not frame_main_dialog.valid then return end

    game.tick_paused = (lib.globals.preferences(player).pause_on_interface and not force_false)
        and frame_main_dialog.visible or false
end

-- General handler for setting a previously stored tooltip on any element
---@param player LuaPlayer
---@param element LuaGuiElement
function main_dialog.set_tooltip(player, element)
    local ui_state = lib.globals.ui_state(player)
    local tags = element.tags

    -- Split into contexts so they can be cleared when the GUI is rebuilt
    local tooltips = ui_state.tooltips[tags.context]
    if tooltips[element.index] ~= nil then
        local tooltip = tooltips[element.index]
        tooltips[element.index] = nil

        -- Add actions tooltip if applicable
        local handler_name = tags.on_gui_click  ---@as string?
        local registered_handler = handler_name and GUI_HANDLERS[handler_name] or nil
        if registered_handler and registered_handler.actions then
            local action_tooltip = lib.actions.generate_tooltip(registered_handler.actions,
                tags.flags--[[@as GUIActionFlags?]])
            if #action_tooltip > 1 then tooltip = {"", tooltip, "\n", action_tooltip} end
        end

        element.tooltip = tooltip
    end
end

-- Centralized here to avoid another global variable
---@param player LuaPlayer
---@param force_false boolean
function main_dialog.toggle_districts_view(player, force_false)
    local ui_state = lib.globals.ui_state(player)
    ui_state.districts_view = not ui_state.districts_view and not force_false

    lib.gui.run_refresh(player, "district_list")
end


-- ** EVENTS **
local listeners = {}  ---@type ListenerDefinitions

listeners.gui = {
    on_gui_closed = {
        {
            name = "close_main_dialog",
            handler = function(player, _, _)
                main_dialog.toggle(player)
            end
        }
    },
    on_gui_click = {
        {
            name = "mod_gui_toggle_interface",
            handler = function(player, _, _)
                interface_toggle({player_index=player.index})
            end
        }
    },
    on_gui_hover = {
        {
            name = "set_tooltip",
            handler = function(player, _, event)
                ---@cast event EventData.on_gui_hover
                main_dialog.set_tooltip(player, event.element)
            end
        }
    }
}  ---@as GUIListenerDefinition

listeners.player = {
    -- The game closes the modal before opening another GUI, so close the main dialog too
    on_gui_opened = function(player, _)
        if main_dialog.is_in_focus(player) then main_dialog.toggle(player, true) end
    end,

    on_lua_shortcut = function(player, event)
        ---@cast event EventData.on_lua_shortcut
        if event.prototype_name == "fp_open_interface" and not lib.globals.ui_state(player).compact_view then
            main_dialog.toggle(player)
        end
    end,

    on_player_display_resolution_changed = resize_main_dialog,
    on_player_display_scale_changed = resize_main_dialog,

    fp_toggle_interface = function(player, _)
        if not lib.globals.ui_state(player).compact_view then main_dialog.toggle(player) end
    end,

    -- This needs to be in a single place, otherwise the events cancel each other out
    fp_toggle_compact_view = function(player, _)
        local ui_state = lib.globals.ui_state(player)
        local factory = lib.context.get(player, "Factory")

        local main_focus = main_dialog.is_in_focus(player)
        local compact_focus = compact_dialog.is_in_focus(player)

        -- Open the compact view if this toggle is pressed when neither dialog
        -- is open as that makes the most sense from a user perspective
        if not main_focus and not compact_focus then
            ui_state.compact_view = true
            compact_dialog.toggle(player)

        elseif ui_state.compact_view and compact_focus then
            compact_dialog.toggle(player)
            main_dialog.toggle(player)
            lib.gui.run_refresh(player, "production")
            ui_state.compact_view = false

        elseif factory ~= nil and factory.valid then
            main_dialog.toggle(player)
            compact_dialog.toggle(player)  -- toggle also refreshes
            ui_state.compact_view = true
        end
    end
}

listeners.game = {
    on_singleplayer_init = function(_)
        for _, player in pairs(game.players) do
            main_dialog.rebuild(player, false)
        end
    end,

    on_multiplayer_init = function(_)
        for _, player in pairs(game.players) do
            main_dialog.rebuild(player, false)
        end
    end
}

listeners.global = {
    interface_toggle = interface_toggle
}

return { listeners }
