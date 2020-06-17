require("ui.elements.titlebar")
require("ui.elements.actionbar")
require("ui.elements.subfactory_bar")
require("ui.elements.error_bar")
require("ui.elements.subfactory_pane")
require("ui.elements.production_titlebar")
require("ui.elements.production_table")

main_dialog = {}

-- ** LOCAL UTIL **
-- Readjusts the size of the main dialog according to the user settings
local function recalculate_main_dialog_dimensions(player)
    local player_table = get_table(player)

    local width = 880 + ((player_table.settings.items_per_row - 4) * 175)
    local height = 394 + (player_table.settings.recipes_at_once * 39)

    local dimensions = {width=width, height=height}
    player_table.ui_state.main_dialog_dimensions = dimensions
    return dimensions
end


-- ** TOP LEVEL **
-- Toggles the main dialog open and closed
function main_dialog.toggle(player)
    -- Won't toggle if a modal dialog is open
    if get_ui_state(player).modal_dialog_type == nil then
        local frame_main_dialog = player.gui.screen["fp_frame_main_dialog"]
        if frame_main_dialog ~= nil then frame_main_dialog.visible = not frame_main_dialog.visible end
        frame_main_dialog = main_dialog.refresh(player)

        player.opened = (frame_main_dialog.visible) and frame_main_dialog or nil
        main_dialog.set_pause_state(player, frame_main_dialog)
    end
end


-- Refreshes the entire main dialog, optionally including it's dimensions
-- Creates the dialog if it doesn't exist; Recreates it if needs to
function main_dialog.refresh(player, full_refresh)
    local frame_main_dialog = player.gui.screen["fp_frame_main_dialog"]

    if (frame_main_dialog == nil and not full_refresh) or (frame_main_dialog ~= nil and full_refresh) then
        if frame_main_dialog ~= nil then frame_main_dialog.clear()
        else
            frame_main_dialog = player.gui.screen.add{type="frame", name="fp_frame_main_dialog", direction="vertical"}
        end

        local dimensions = recalculate_main_dialog_dimensions(player)
        ui_util.properly_center_frame(player, frame_main_dialog, dimensions.width, dimensions.height)
        frame_main_dialog.style.minimal_width = dimensions.width
        frame_main_dialog.style.height = dimensions.height

        main_dialog.set_pause_state(player, frame_main_dialog)  -- Adjust the paused-state accordingly
        local ui_state = get_ui_state(player)
        if ui_state.modal_dialog_type == "beacon" and ui_state.flags.selection_mode then
            beacon_dialog.leave_selection_mode(player, 0)  -- Leave the beacon selection mode if it is active
        end

        titlebar.add_to(frame_main_dialog)
        actionbar.add_to(frame_main_dialog)
        subfactory_bar.add_to(frame_main_dialog)
        error_bar.add_to(frame_main_dialog)
        subfactory_pane.add_to(frame_main_dialog)
        production_titlebar.add_to(frame_main_dialog)

    elseif frame_main_dialog ~= nil and frame_main_dialog.visible then
        -- Re-center the main dialog because it get screwed up sometimes for reasons
        local dimensions = recalculate_main_dialog_dimensions(player)
        ui_util.properly_center_frame(player, frame_main_dialog, dimensions.width, dimensions.height)

        -- Refresh the elements on top of the hierarchy, which refresh everything below them
        titlebar.refresh(player)
        actionbar.refresh(player)
        subfactory_bar.refresh(player, true)
    end

    ui_util.message.refresh(player)
    return frame_main_dialog
end

-- Refreshes elements using ui_state.current_activity with less performance impact than main_dialog.refresh
function main_dialog.refresh_current_activity(player)
    local frame_main_dialog = player.gui.screen["fp_frame_main_dialog"]
    local ui_state = get_ui_state(player)

    if frame_main_dialog ~= nil and frame_main_dialog.visible then
        actionbar.refresh(player)

        local subfactory = ui_state.context.subfactory
        if subfactory ~= nil and subfactory.valid then
            local table_info_elements = frame_main_dialog["table_subfactory_pane"]
              ["flow_info"]["scroll-pane"]["table_info_elements"]
            info_pane.refresh_mining_prod_table(player, subfactory, table_info_elements)
        end

        local line = ui_state.context.line
        if line ~= nil and subfactory.valid then
            local table_production = frame_main_dialog["flow_production_pane"]
              ["scroll-pane_production_pane"]["table_production_pane"]
            production_table.refresh_recipe_button(player, line, table_production)
            production_table.refresh_machine_table(player, line, table_production)
        end

        ui_util.message.refresh(player)
    end
end


-- Returns true when the main dialog is open while no modal dialogs are
function main_dialog.is_in_focus(player)
    local frame_main_dialog = player.gui.screen["fp_frame_main_dialog"]
    return (frame_main_dialog ~= nil and frame_main_dialog.visible
      and get_ui_state(player).modal_dialog_type == nil)
end

-- Sets the game.paused-state appropriately
function main_dialog.set_pause_state(player, frame_main_dialog, force_false)
    if not game.is_multiplayer() and player.controller_type ~= defines.controllers.editor then
        if get_preferences(player).pause_on_interface and not force_false then
            game.tick_paused = frame_main_dialog.visible  -- only pause when the main dialog is open
        else
            game.tick_paused = false
        end
    end
end