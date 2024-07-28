require("ui.main.factory_list")
require("ui.base.view_state")

main_dialog = {}

-- Accepts custom width and height parameters so dimensions can be tried out without changing actual preferences
local function determine_main_dimensions(player, products_per_row, factory_list_rows)
    local preferences = util.globals.preferences(player)
    products_per_row = products_per_row or preferences.products_per_row
    factory_list_rows = factory_list_rows or preferences.factory_list_rows
    local frame_spacing = MAGIC_NUMBERS.frame_spacing

    -- Width of the larger ingredients-box, which has twice the buttons per row
    local boxes_width_1 = (products_per_row * 2 * MAGIC_NUMBERS.item_button_size) + (2 * frame_spacing)
    -- Width of the two smaller product+byproduct-boxes
    local boxes_width_2 = 2 * ((products_per_row * MAGIC_NUMBERS.item_button_size) + (2 * frame_spacing))
    local width = MAGIC_NUMBERS.list_width + boxes_width_1 + boxes_width_2 + ((2+3) * frame_spacing)

    local factory_list_height = (factory_list_rows * MAGIC_NUMBERS.list_element_height)
        + MAGIC_NUMBERS.subheader_height
    local height = MAGIC_NUMBERS.title_bar_height + MAGIC_NUMBERS.district_info_height +
        factory_list_height + MAGIC_NUMBERS.factory_info_height + ((2+2) * frame_spacing)

    return {width=width, height=height}
end

-- Downscale width and height preferences until the main interface fits onto the player's screen
function main_dialog.shrinkwrap_interface(player)
    local resolution, scale = player.display_resolution, player.display_scale
    local actual_resolution = {width=math.ceil(resolution.width / scale), height=math.ceil(resolution.height / scale)}
    local preferences = util.globals.preferences(player)

    local width_minimum = PRODUCTS_PER_ROW_OPTIONS[1]
    while (actual_resolution.width * 0.95) < determine_main_dimensions(player).width
            and preferences.products_per_row > width_minimum do
        preferences.products_per_row = preferences.products_per_row - 1
    end

    local height_minimum = FACTORY_LIST_ROWS_OPTIONS[1]
    while (actual_resolution.height * 0.95) < determine_main_dimensions(player).height
            and preferences.factory_list_rows > height_minimum do
        preferences.factory_list_rows = preferences.factory_list_rows - 2
    end

    main_dialog.rebuild(player, false)
end


local function interface_toggle(metadata)
    local player = game.get_player(metadata.player_index)  --[[@as LuaPlayer]]
    local compact_view = util.globals.ui_state(player).compact_view
    if compact_view then compact_dialog.toggle(player)
    else main_dialog.toggle(player) end
end


function main_dialog.rebuild(player, default_visibility)
    local ui_state = util.globals.ui_state(player)
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

    local dimensions = determine_main_dimensions(player)
    ui_state.main_dialog_dimensions = dimensions
    frame_main_dialog.style.size = dimensions
    util.gui.properly_center_frame(player, frame_main_dialog, dimensions)


    -- Create the actual dialog structure
    local frame_spacing = MAGIC_NUMBERS.frame_spacing
    main_elements.flows = {}

    local top_horizontal = frame_main_dialog.add{type="flow", direction="horizontal"}
    main_elements.flows["top_horizontal"] = top_horizontal

    local main_horizontal = frame_main_dialog.add{type="flow", direction="horizontal"}
    main_horizontal.style.horizontal_spacing = frame_spacing
    main_elements.flows["main_horizontal"] = main_horizontal

    local left_vertical = main_horizontal.add{type="flow", direction="vertical"}
    left_vertical.style.vertical_spacing = frame_spacing
    left_vertical.style.width = MAGIC_NUMBERS.list_width
    main_elements.flows["left_vertical"] = left_vertical

    local right_vertical = main_horizontal.add{type="flow", direction="vertical"}
    right_vertical.style.vertical_spacing = frame_spacing
    main_elements.flows["right_vertical"] = right_vertical

    view_state.rebuild_state(player)  -- initializes the view_state
    util.raise.build(player, "main_dialog", nil)  -- tells all elements to build themselves

    if interface_visible then player.opened = frame_main_dialog end
    main_dialog.set_pause_state(player, frame_main_dialog)
end

function main_dialog.toggle(player, skip_opened)
    local ui_state = util.globals.ui_state(player)
    local frame_main_dialog = ui_state.main_elements.main_frame

    if frame_main_dialog == nil or not frame_main_dialog.valid then
        main_dialog.rebuild(player, true)  -- sets opened and paused-state itself

    elseif ui_state.modal_dialog_type == nil then  -- don't toggle if modal dialog is open
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


-- Returns true when the main dialog is open while no modal dialogs are
function main_dialog.is_in_focus(player)
    local frame_main_dialog = util.globals.main_elements(player).main_frame
    return (frame_main_dialog ~= nil and frame_main_dialog.valid and frame_main_dialog.visible
        and util.globals.ui_state(player).modal_dialog_type == nil)
end

-- Sets the game.paused-state as is appropriate
function main_dialog.set_pause_state(player, frame_main_dialog, force_false)
    -- Don't touch paused-state if this is a multiplayer session or the editor is active
    if game.is_multiplayer() or player.controller_type == defines.controllers.editor then return end

    game.tick_paused = (util.globals.preferences(player).pause_on_interface and not force_false)
        and frame_main_dialog.visible or false
end

-- General handler for setting a previously stored tooltip on any element
function main_dialog.set_tooltip(player, element)
    local ui_state = util.globals.ui_state(player)
    local tooltips = ui_state.tooltips[element.tags.context]
    if tooltips[element.index] ~= nil then
        element.tooltip = tooltips[element.index]
        tooltips[element.index] = nil
    end
end

-- Centralized here to avoid another global variable
function main_dialog.toggle_districts_view(player)
    local ui_state = util.globals.ui_state(player)
    ui_state.districts_view = not ui_state.districts_view

    view_state.rebuild_state(player)
    util.raise.refresh(player, "district_info")
end


-- ** EVENTS **
local listeners = {}

listeners.gui = {
    on_gui_closed = {
        {
            name = "close_main_dialog",
            handler = (function(player, _, _)
                main_dialog.toggle(player)
            end)
        }
    },
    on_gui_click = {
        {
            name = "mod_gui_toggle_interface",
            handler = (function(player, _, _)
                interface_toggle({player_index=player.index})
            end)
        }
    },
    on_gui_hover = {
        {
            name = "set_tooltip",
            handler = (function(player, _, event)
                main_dialog.set_tooltip(player, event.element)
            end)
        }
    }
}

listeners.misc = {
    -- Makes sure that another GUI can open properly while a modal dialog is open.
    -- The FP interface can have at most 3 layers of GUI: main interface, modal dialog, selection mode.
    -- We need to make sure opening the technology screen (for example) from any of those layers behaves properly.
    -- We need to consider that if the technology screen is opened (which is the reason we get this event),
    -- the game automtically closes the currently open GUI before calling this one. This means the top layer
    -- that's open at that stage is closed already when we get here. So we're at most at the modal dialog
    -- layer at this point and need to close the things below, if there are any.
    on_gui_opened = (function(player, _)
        local ui_state = util.globals.ui_state(player)

        -- With that in mind, if there's a modal dialog open, we were in selection mode, and need to close the dialog
        if ui_state.modal_dialog_type ~= nil then util.raise.close_dialog(player, "cancel", true) end

        -- Then, at this point we're at most at the stage where the main dialog is open, so close it
        if main_dialog.is_in_focus(player) then main_dialog.toggle(player, true) end
    end),

    on_player_display_resolution_changed = (function(player, _)
        main_dialog.shrinkwrap_interface(player)
        main_dialog.rebuild(player, false)
    end),

    on_player_display_scale_changed = (function(player, _)
        main_dialog.shrinkwrap_interface(player)
        main_dialog.rebuild(player, false)
    end),

    on_lua_shortcut = (function(player, event)
        if event.prototype_name == "fp_open_interface" and not util.globals.ui_state(player).compact_view then
            main_dialog.toggle(player)
        end
    end),

    fp_toggle_interface = (function(player, _)
        if not util.globals.ui_state(player).compact_view then main_dialog.toggle(player) end
    end),

    -- This needs to be in a single place, otherwise the events cancel each other out
    fp_toggle_compact_view = (function(player, _)
        local ui_state = util.globals.ui_state(player)
        local factory = util.context.get(player, "Factory")

        local main_focus = main_dialog.is_in_focus(player)
        local compact_focus = compact_dialog.is_in_focus(player)
        local valid_factory = factory ~= nil and factory.valid

        -- Open the compact view if this toggle is pressed when neither dialog
        -- is open as that makes the most sense from a user perspective
        if not main_focus and not compact_focus then
            ui_state.compact_view = true
            compact_dialog.toggle(player)

        elseif ui_state.compact_view and compact_focus then
            compact_dialog.toggle(player)
            main_dialog.toggle(player)
            util.raise.refresh(player, "production")
            ui_state.compact_view = false

        elseif main_focus and valid_factory and not ui_state.districts_view then
            main_dialog.toggle(player)
            compact_dialog.toggle(player)  -- toggle also refreshes
            ui_state.compact_view = true
        end
    end)
}

listeners.global = {
    interface_toggle = interface_toggle
}

return { listeners }
