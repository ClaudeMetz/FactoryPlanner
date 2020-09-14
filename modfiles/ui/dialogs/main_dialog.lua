require("ui.elements.title_bar")
require("ui.elements.subfactory_list")
require("ui.elements.subfactory_info")
require("ui.elements.view_state")
require("ui.elements.item_boxes")
require("ui.elements.production_box")

main_dialog = {}

-- ** LOCAL UTIL **
local function determine_main_dialog_dimensions(player)
    local player_table = data_util.get("table", player)

    local products_per_row = player_table.settings.products_per_row
    local subfactory_list_rows = player_table.settings.subfactory_list_rows

    -- Width of the larger ingredients-box, which has twice the buttons per row
    local boxes_width_1 = (products_per_row * 2 * ITEM_BOX_BUTTON_SIZE) + (2 * ITEM_BOX_PADDING)
    -- Width of the two smaller product+byproduct boxes
    local boxes_width_2 = 2 * ((products_per_row * ITEM_BOX_BUTTON_SIZE) + (2 * ITEM_BOX_PADDING))
    local width = SUBFACTORY_LIST_WIDTH + boxes_width_1 + boxes_width_2 + ((2+3) * FRAME_SPACING)

    local title_bar_height = 34 -- not needed anywhere, thus no global necessary
    local subfactory_list_height = SUBFACTORY_SUBHEADER_HEIGHT + (subfactory_list_rows * SUBFACTORY_LIST_ELEMENT_HEIGHT)
    local height = title_bar_height + subfactory_list_height + SUBFACTORY_INFO_HEIGHT + ((2+1) * FRAME_SPACING)

    local dimensions = {width=width, height=height}
    player_table.ui_state.main_dialog_dimensions = dimensions
    return dimensions
end

-- No idea how to write this so it works when in selection mode
local function handle_other_gui_opening(player)
    local frame_main_dialog = data_util.get("main_elements", player).main_frame
    if frame_main_dialog and frame_main_dialog.visible then
        frame_main_dialog.visible = false
        main_dialog.set_pause_state(player, frame_main_dialog)
    end
end


-- ** TOP LEVEL **
main_dialog.gui_events = {
    on_gui_closed = {
        {
            name = "fp_frame_main_dialog",
            handler = (function(player, _)
                main_dialog.toggle(player)
            end)
        }
    },
    on_gui_click = {
        {
            name = "fp_button_toggle_interface",
            handler = (function(player, _, _)
                main_dialog.toggle(player)
            end)
        }
    }
}

main_dialog.misc_events = {
    on_gui_opened = (function(player, _)
        handle_other_gui_opening(player)
    end),

    on_player_display_resolution_changed = (function(player, _)
        main_dialog.rebuild(player, false)
    end),

    on_player_display_scale_changed = (function(player, _)
        main_dialog.rebuild(player, false)
    end),

    on_lua_shortcut = (function(player, event)
        if event.prototype_name == "fp_open_interface" then
            main_dialog.toggle(player)
        end
    end),

    fp_toggle_main_dialog = (function(player, _)
        main_dialog.toggle(player)
    end)
}


function main_dialog.rebuild(player, default_visibility)
    local ui_state = data_util.get("ui_state", player)
    local main_elements = ui_state.main_elements

    local visible = default_visibility
    if main_elements.main_frame ~= nil then
        visible = main_elements.main_frame.visible
        main_elements.main_frame.destroy()

        -- Reset all main element references
        ui_state.main_elements = {}
        main_elements = ui_state.main_elements
    end
    main_elements.flows = {}

    -- Create and configure the top-level frame
    local frame_main_dialog = player.gui.screen.add{type="frame", name="fp_frame_main_dialog",
      visible=visible, direction="vertical"}
    main_elements["main_frame"] = frame_main_dialog

    local dimensions = determine_main_dialog_dimensions(player)
    frame_main_dialog.style.width = dimensions.width
    frame_main_dialog.style.height = dimensions.height
    ui_util.properly_center_frame(player, frame_main_dialog, dimensions.width, dimensions.height)

    if visible then player.opened = frame_main_dialog end
    main_dialog.set_pause_state(player, frame_main_dialog)

    -- Create the actual dialog structure
    view_state.rebuild_state(player)  -- actually initializes it
    title_bar.build(player)

    local main_horizontal = frame_main_dialog.add{type="flow", direction="horizontal"}
    main_horizontal.style.horizontal_spacing = FRAME_SPACING
    main_elements.flows["main_horizontal"] = main_horizontal

    local left_vertical = main_horizontal.add{type="flow", direction="vertical"}
    left_vertical.style.width = SUBFACTORY_LIST_WIDTH
    left_vertical.style.vertical_spacing = FRAME_SPACING
    main_elements.flows["left_vertical"] = left_vertical
    subfactory_list.build(player)
    subfactory_info.build(player)

    local right_vertical = main_horizontal.add{type="flow", direction="vertical"}
    right_vertical.style.vertical_spacing = FRAME_SPACING
    main_elements.flows["right_vertical"] = right_vertical
    item_boxes.build(player)
    production_box.build(player)  -- also builds the production table

    title_bar.refresh_message(player)
end

function main_dialog.refresh(player, element_list)
    -- If element_list is a table, only refresh the specified elements
    if type(element_list) == "table" then
        for _, element_name in pairs(element_list) do
            _G[element_name].refresh(player)
        end
    else
        -- If element_list is nil, refresh everything
        -- If it is equal to "subfactory", refresh everything about the current subfactory
        local subfactory_refresh = (type(element_list == "string") and element_list == "subfactory")
        if not subfactory_refresh then subfactory_list.refresh(player) end

        subfactory_info.refresh(player)
        item_boxes.refresh(player)

        production_box.refresh(player)
        --production_table.refresh(player)
    end

    title_bar.refresh_message(player)
end

function main_dialog.toggle(player)
    local ui_state = data_util.get("ui_state", player)
    local frame_main_dialog = ui_state.main_elements.main_frame

    if frame_main_dialog == nil then
        main_dialog.rebuild(player, true)  -- sets opened and paused-state itself

    elseif ui_state.modal_dialog_type == nil then  -- don't toggle if modal dialog is open
        frame_main_dialog.visible = not frame_main_dialog.visible
        player.opened = (frame_main_dialog.visible) and frame_main_dialog or nil

        main_dialog.set_pause_state(player, frame_main_dialog)
        title_bar.refresh_message(player)
    end
end


-- Returns true when the main dialog is open while no modal dialogs are
function main_dialog.is_in_focus(player)
    local frame_main_dialog = data_util.get("main_elements", player).main_frame
    return (frame_main_dialog ~= nil and frame_main_dialog.visible
      and data_util.get("ui_state", player).modal_dialog_type == nil)
end

-- Sets the game.paused-state as is appropriate
function main_dialog.set_pause_state(player, frame_main_dialog, force_false)
    if not game.is_multiplayer() and player.controller_type ~= defines.controllers.editor then
        if data_util.get("preferences", player).pause_on_interface and not force_false then
            game.tick_paused = frame_main_dialog.visible  -- only pause when the main dialog is open
        else
            game.tick_paused = false
        end
    end
end