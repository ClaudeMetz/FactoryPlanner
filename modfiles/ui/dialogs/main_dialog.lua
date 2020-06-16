require("mod-gui")
require("ui.elements.actionbar")
require("ui.elements.subfactory_bar")
require("ui.elements.error_bar")
require("ui.elements.subfactory_pane")
require("ui.elements.production_titlebar")
require("ui.elements.production_table")

-- Create the always-present GUI button to open the main dialog + devmode setup
function player_gui_init(player)
    local frame_flow = mod_gui.get_button_flow(player)
    if not frame_flow["fp_button_toggle_interface"] then
        frame_flow.add
        {
            type = "button",
            name = "fp_button_toggle_interface",
            caption = "FP",
            tooltip = {"fp.open_main_dialog"},
            style = mod_gui.button_style,
            mouse_button_filter = {"left"}
        }
    end

    -- Incorporates the mod setting for the visibility of the toggle-main-dialog-button
    toggle_button_interface(player)
end

-- Destroys all GUI's so they are loaded anew the next time they are shown
function player_gui_reset(player)
    local screen = player.gui.screen
    local guis = {
        mod_gui.get_button_flow(player)["fp_button_toggle_interface"],
        screen["fp_frame_main_dialog"],
        screen["fp_frame_modal_dialog"],
        screen["fp_frame_modal_dialog_product"],  -- TODO remove when this dialog is added back as a cached one
        unpack(cached_dialogs)
    }

    for _, gui in pairs(guis) do
        if type(gui) == "string" then gui = screen[gui] end
        if gui ~= nil and gui.valid then gui.destroy() end
    end
end


-- Toggles the visibility of the toggle-main-dialog-button
function toggle_button_interface(player)
    local enable = get_settings(player).show_gui_button
    mod_gui.get_button_flow(player)["fp_button_toggle_interface"].visible = enable
end

-- Returns true when the main dialog is open while no modal dialogs are
function is_main_dialog_in_focus(player)
    local main_dialog = player.gui.screen["fp_frame_main_dialog"]
    return (main_dialog ~= nil and main_dialog.visible
      and get_ui_state(player).modal_dialog_type == nil)
end

-- Sets the game.paused-state appropriately
function set_pause_state(player, main_dialog)
    if get_preferences(player).pause_on_interface and not game.is_multiplayer() and
      player.controller_type ~= defines.controllers.editor then
        game.tick_paused = main_dialog.visible  -- only pause when the main dialog is open
    end
end


-- Toggles the main dialog open and closed
function toggle_main_dialog(player)
    -- Won't toggle if a modal dialog is open
    if get_ui_state(player).modal_dialog_type == nil then
        local main_dialog = player.gui.screen["fp_frame_main_dialog"]
        if main_dialog ~= nil then main_dialog.visible = not main_dialog.visible end
        main_dialog = refresh_main_dialog(player)

        player.opened = main_dialog.visible and main_dialog or nil
        set_pause_state(player, main_dialog)
    end
end

-- Changes the main dialog in reaction to a modal dialog being opened/closed
function toggle_modal_dialog(player, frame_modal_dialog)
    local main_dialog = player.gui.screen["fp_frame_main_dialog"]

    -- If the frame parameter is not nil, the given modal dialog has been opened
    if frame_modal_dialog ~= nil then
        player.opened = frame_modal_dialog
        main_dialog.ignored_by_interaction = true
    else
        player.opened = main_dialog
        main_dialog.ignored_by_interaction = false
    end
end

-- Sets selection mode and configures the related GUI's
function set_selection_mode(player, state)
    local ui_state = get_ui_state(player)

    if ui_state.modal_dialog_type == "beacon" then
        ui_state.flags.selection_mode = state
        player.gui.screen["fp_frame_main_dialog"].visible = not state

        local frame_modal_dialog = ui_util.find_modal_dialog(player)
        frame_modal_dialog.ignored_by_interaction = state
        if state == true then
            frame_modal_dialog.location = {25, 50}
        else
            frame_modal_dialog.force_auto_center()
            player.opened = frame_modal_dialog
        end
    end
end


-- Refreshes the entire main dialog, optionally including it's dimensions
-- Creates the dialog if it doesn't exist; Recreates it if needs to
function refresh_main_dialog(player, full_refresh)
    local main_dialog = player.gui.screen["fp_frame_main_dialog"]

    if (main_dialog == nil and not full_refresh) or (main_dialog ~= nil and full_refresh) then
        if main_dialog ~= nil then main_dialog.clear()
        else main_dialog = player.gui.screen.add{type="frame", name="fp_frame_main_dialog", direction="vertical"} end

        local dimensions = ui_util.recalculate_main_dialog_dimensions(player)
        ui_util.properly_center_frame(player, main_dialog, dimensions.width, dimensions.height)
        main_dialog.style.minimal_width = dimensions.width
        main_dialog.style.height = dimensions.height

        set_pause_state(player, main_dialog)  -- Adjust the paused-state accordingly
        local ui_state = get_ui_state(player)
        if ui_state.modal_dialog_type == "beacon" and ui_state.flags.selection_mode then
            leave_beacon_selection(player, 0)  -- Leave the beacon selection mode if it is active
        end

        add_titlebar_to(main_dialog)
        add_actionbar_to(main_dialog)
        add_subfactory_bar_to(main_dialog)
        add_error_bar_to(main_dialog)
        add_subfactory_pane_to(main_dialog)
        add_production_pane_to(main_dialog)

    elseif main_dialog ~= nil and main_dialog.visible then
        -- Re-center the main dialog because it get screwed up sometimes for reasons
        local dimensions = ui_util.recalculate_main_dialog_dimensions(player)
        ui_util.properly_center_frame(player, main_dialog, dimensions.width, dimensions.height)

        -- Refresh the elements on top of the hierarchy, which refresh everything below them
        refresh_titlebar(player)
        refresh_actionbar(player)
        refresh_subfactory_bar(player, true)
    end

    ui_util.message.refresh(player)
    return main_dialog
end

-- Refreshes elements using ui_state.current_activity with less performance impact than refresh_main_dialog
function refresh_current_activity(player)
    local main_dialog = player.gui.screen["fp_frame_main_dialog"]
    local ui_state = get_ui_state(player)

    if main_dialog ~= nil and main_dialog.visible then
        refresh_actionbar(player)

        local subfactory = ui_state.context.subfactory
        if subfactory ~= nil and subfactory.valid then
            local table_info_elements = main_dialog["table_subfactory_pane"]
              ["flow_info"]["scroll-pane"]["table_info_elements"]
            refresh_mining_prod_table(player, subfactory, table_info_elements)
        end

        local line = ui_state.context.line
        if line ~= nil and subfactory.valid then
            local table_production = main_dialog["flow_production_pane"]
              ["scroll-pane_production_pane"]["table_production_pane"]
            refresh_recipe_button(player, line, table_production)
            refresh_machine_table(player, line, table_production)
        end

        ui_util.message.refresh(player)
    end
end


-- Creates the titlebar including name and exit-button
function add_titlebar_to(main_dialog)
    local titlebar = main_dialog.add{type="flow", name="flow_titlebar", direction="horizontal"}

    -- Title
    local label_title = titlebar.add{type="label", name="label_titlebar_name", caption=" Factory Planner"}
    label_title.style.font = "fp-font-bold-26p"

    -- Hint
    local label_hint = titlebar.add{type="label", name="label_titlebar_hint"}
    label_hint.style.font = "fp-font-semibold-18p"
    label_hint.style.top_margin = 6
    label_hint.style.left_margin = 14

    -- Spacer
    local flow_spacer = titlebar.add{type="flow", name="flow_titlebar_spacer", direction="horizontal"}
    flow_spacer.style.horizontally_stretchable = true

    -- Drag handle
    local handle = titlebar.add{type="empty-widget", name="empty-widget_titlebar_space", style="draggable_space"}
    handle.style.height = 34
    handle.style.width = 180
    handle.style.top_margin = 4
    handle.drag_target = main_dialog

    -- Buttonbar
    local flow_buttonbar = titlebar.add{type="flow", name="flow_titlebar_buttonbar", direction="horizontal"}
    flow_buttonbar.style.top_margin = 4

    flow_buttonbar.add{type="button", name="fp_button_titlebar_tutorial", caption={"fp.tutorial"},
      style="fp_button_titlebar", mouse_button_filter={"left"}}
    flow_buttonbar.add{type="button", name="fp_button_titlebar_preferences", caption={"fp.preferences"},
      style="fp_button_titlebar", mouse_button_filter={"left"}}

    local button_pause = flow_buttonbar.add{type="sprite-button", name="fp_button_titlebar_pause",
      sprite="utility/pause", tooltip={"fp.pause_on_interface"}, mouse_button_filter={"left"}}
    button_pause.style.left_margin = 4

    flow_buttonbar.add{type="sprite-button", name="fp_button_titlebar_exit",
      sprite="utility/close_fat", style="fp_button_titlebar_square", mouse_button_filter={"left"}}


    refresh_titlebar(game.get_player(main_dialog.player_index))
end


-- Refreshes the pause_on_interface-button
function refresh_titlebar(player)
    local main_dialog = player.gui.screen["fp_frame_main_dialog"]
    local button_pause = main_dialog["flow_titlebar"]["flow_titlebar_buttonbar"]["fp_button_titlebar_pause"]
    button_pause.enabled = (not game.is_multiplayer())
    button_pause.style = (get_preferences(player).pause_on_interface) and
      "fp_button_titlebar_square_selected" or "fp_button_titlebar_square"
end


-- Handles a click on the pause_on_interface button
function handle_pause_button_click(player, button)
    if not game.is_multiplayer() then
        local preferences = get_preferences(player)
        preferences.pause_on_interface = not preferences.pause_on_interface

        button.style = (preferences.pause_on_interface) and
          "fp_button_titlebar_square_selected" or "fp_button_titlebar_square"

        game.tick_paused = preferences.pause_on_interface
    end
end