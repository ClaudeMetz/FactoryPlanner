require("ui.main.title_bar")
require("ui.main.subfactory_list")
require("ui.main.subfactory_info")
require("ui.main.item_boxes")
require("ui.main.production_box")
require("ui.main.production_table")
require("ui.main.production_handler")
require("ui.base.view_state")

main_dialog = {}

-- ** LOCAL UTIL **
-- Accepts custom width and height parameters so dimensions can be tried out without needing to change actual settings
local function determine_main_dimensions(player, products_per_row, subfactory_list_rows)
    local settings = data_util.settings(player)
    products_per_row = products_per_row or settings.products_per_row
    subfactory_list_rows = subfactory_list_rows or settings.subfactory_list_rows

    -- Width of the larger ingredients-box, which has twice the buttons per row
    local boxes_width_1 = (products_per_row * 2 * ITEM_BOX_BUTTON_SIZE) + (2 * ITEM_BOX_PADDING)
    -- Width of the two smaller product+byproduct-boxes
    local boxes_width_2 = 2 * ((products_per_row * ITEM_BOX_BUTTON_SIZE) + (2 * ITEM_BOX_PADDING))
    local width = SUBFACTORY_LIST_WIDTH + boxes_width_1 + boxes_width_2 + ((2+3) * FRAME_SPACING)

    local subfactory_list_height = SUBFACTORY_SUBHEADER_HEIGHT + (subfactory_list_rows * SUBFACTORY_LIST_ELEMENT_HEIGHT)
    local height = TITLE_BAR_HEIGHT + subfactory_list_height + SUBFACTORY_INFO_HEIGHT + ((2+1) * FRAME_SPACING)

    return {width=width, height=height}
end

-- Downscale width and height mod settings until the main interface fits onto the player's screen
function main_dialog.shrinkwrap_interface(player)
    local resolution, scale = player.display_resolution, player.display_scale
    local actual_resolution = {width=math.ceil(resolution.width / scale), height=math.ceil(resolution.height / scale)}

    local mod_settings = data_util.settings(player)
    local products_per_row = mod_settings.products_per_row
    local subfactory_list_rows = mod_settings.subfactory_list_rows

    local function dimensions() return determine_main_dimensions(player, products_per_row, subfactory_list_rows) end

    while (actual_resolution.width * 0.95) < dimensions().width do
        products_per_row = products_per_row - 1
    end
    while (actual_resolution.height * 0.95) < dimensions().height do
        subfactory_list_rows = subfactory_list_rows - 2
    end

    local setting_prototypes = game.mod_setting_prototypes
    local width_minimum = setting_prototypes["fp_products_per_row"].allowed_values[1] --[[@as number]]
    local height_minimum = setting_prototypes["fp_subfactory_list_rows"].allowed_values[1] --[[@as number]]

    local live_settings = settings.get_player_settings(player)
    live_settings["fp_products_per_row"] = {value = math.max(products_per_row, width_minimum)}
    live_settings["fp_subfactory_list_rows"] = {value = math.max(subfactory_list_rows, height_minimum)}
end


-- ** TOP LEVEL **
function main_dialog.rebuild(player, default_visibility)
    local ui_state = data_util.ui_state(player)
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
    ui_util.properly_center_frame(player, frame_main_dialog, dimensions)


    -- Create the actual dialog structure
    main_elements.flows = {}

    local top_horizontal = frame_main_dialog.add{type="flow", direction="horizontal"}
    main_elements.flows["top_horizontal"] = top_horizontal

    local main_horizontal = frame_main_dialog.add{type="flow", direction="horizontal"}
    main_horizontal.style.horizontal_spacing = FRAME_SPACING
    main_elements.flows["main_horizontal"] = main_horizontal

    local left_vertical = main_horizontal.add{type="flow", direction="vertical"}
    left_vertical.style.vertical_spacing = FRAME_SPACING
    main_elements.flows["left_vertical"] = left_vertical

    local right_vertical = main_horizontal.add{type="flow", direction="vertical"}
    right_vertical.style.vertical_spacing = FRAME_SPACING
    main_elements.flows["right_vertical"] = right_vertical

    view_state.rebuild_state(player)  -- initializes the view_state
    ui_util.raise_build(player, "main_dialog", nil)  -- tells all elements to build themselves
    title_bar.refresh_message(player)

    if interface_visible then player.opened = frame_main_dialog end
    main_dialog.set_pause_state(player, frame_main_dialog)
end

function main_dialog.toggle(player, skip_opened)
    local ui_state = data_util.ui_state(player)
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
        title_bar.refresh_message(player)

        -- Make sure FP is not behind some vanilla interfaces
        if new_dialog_visibility then frame_main_dialog.bring_to_front() end
    end
end


-- Returns true when the main dialog is open while no modal dialogs are
function main_dialog.is_in_focus(player)
    local frame_main_dialog = data_util.main_elements(player).main_frame
    return (frame_main_dialog ~= nil and frame_main_dialog.valid and frame_main_dialog.visible
        and data_util.ui_state(player).modal_dialog_type == nil)
end

-- Sets the game.paused-state as is appropriate
function main_dialog.set_pause_state(player, frame_main_dialog, force_false)
    -- Don't touch paused-state if this is a multiplayer session or the editor is active
    if game.is_multiplayer() or player.controller_type == defines.controllers.editor then return end

    game.tick_paused = (data_util.preferences(player).pause_on_interface and not force_false)
        and frame_main_dialog.visible or false
end


function NTH_TICK_HANDLERS.interface_toggle(metadata)
    local player = game.get_player(metadata.player_index)
    local compact_view = data_util.flags(player).compact_view
    if compact_view then compact_dialog.toggle(player)
    else main_dialog.toggle(player) end
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
                if DEVMODE then  -- implicit mod reload for easier development
                    ui_util.reset_player_gui(player)  -- destroys all FP GUIs
                    ui_util.toggle_mod_gui(player)  -- fixes the mod gui button after its been destroyed
                    game.reload_mods()  -- toggle needs to be delayed by a tick since the reload is not instant
                    game.print("Mods reloaded")
                    data_util.nth_tick.add((game.tick + 1), "interface_toggle", {player_index=player.index})
                else  -- call the interface toggle function directly
                    NTH_TICK_HANDLERS.interface_toggle({player_index=player.index})
                end
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
        local ui_state = data_util.ui_state(player)

        -- With that in mind, if there's a modal dialog open, we were in selection mode, and need to close the dialog
        if ui_state.modal_dialog_type ~= nil then ui_util.raise_close_dialog(player, "cancel", true) end

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
        if event.prototype_name == "fp_open_interface" and not data_util.flags(player).compact_view then
            main_dialog.toggle(player)
        end
    end),

    fp_toggle_interface = (function(player, _)
        if not data_util.flags(player).compact_view then main_dialog.toggle(player) end
    end),

    -- This needs to be in a single place, otherwise the events cancel each other out
    fp_toggle_compact_view = (function(player, _)
        local ui_state = data_util.ui_state(player)
        local flags = ui_state.flags
        local subfactory = ui_state.context.subfactory

        local main_focus = main_dialog.is_in_focus(player)
        local compact_focus = compact_dialog.is_in_focus(player)

        -- Open the compact view if this toggle is pressed when neither dialog
        -- is open as that makes the most sense from a user perspective
        if not main_focus and not compact_focus then
            flags.compact_view = true
            compact_dialog.toggle(player)

        elseif flags.compact_view and compact_focus then
            compact_dialog.toggle(player)
            main_dialog.toggle(player)
            ui_util.raise_refresh(player, "production", nil)
            flags.compact_view = false

        elseif main_focus and subfactory ~= nil and subfactory.valid then
            main_dialog.toggle(player)
            compact_dialog.toggle(player)  -- toggle also refreshes
            flags.compact_view = true
        end
    end),

    refresh_gui_element = (function(player, event)
        -- TODO refreshes no matter the context, which isn't correct really
        -- Will be removed with the messages system refactor
        title_bar.refresh_message(player)
    end)
}

return { listeners }
