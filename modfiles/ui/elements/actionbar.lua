-- Creates the actionbar including the new-, edit- and delete-buttons
function add_actionbar_to(main_dialog)
    local actionbar = main_dialog.add{type="flow", name="flow_action_bar", direction="horizontal"}
    actionbar.style.left_margin = 6

    actionbar.add{type="button", name="fp_button_new_subfactory", caption={"button-text.new_subfactory"}, 
      style="fp_button_action", mouse_button_filter={"left"}}
    actionbar.add{type="button", name="fp_button_edit_subfactory", caption={"button-text.edit"}, 
      style="fp_button_action", mouse_button_filter={"left"}}
    actionbar.add{type="button", name="fp_button_delete_subfactory", caption={"button-text.delete"}, 
      style="fp_button_action", mouse_button_filter={"left"}}
    actionbar.style.bottom_margin = 4

    refresh_actionbar(game.get_player(main_dialog.player_index))
end


-- Disables edit and delete buttons if there exist no subfactories
function refresh_actionbar(player)
    local ui_state = get_ui_state(player)
    local actionbar = player.gui.screen["fp_frame_main_dialog"]["flow_action_bar"]
    local delete_button = actionbar["fp_button_delete_subfactory"]

    local subfactory_exists = (ui_state.context.subfactory ~= nil)
    actionbar["fp_button_edit_subfactory"].enabled = subfactory_exists
    delete_button.enabled = subfactory_exists

    if ui_state.current_activity == "deleting_subfactory" then
        delete_button.caption = {"button-text.delete_confirm"}
        delete_button.style.font =  "fp-font-bold-16p"
        delete_button.style.left_padding = 16
        ui_util.set_label_color(delete_button, "dark_red")
    else
        delete_button.caption = {"button-text.delete"}
        delete_button.style.font =  "fp-font-semibold-16p"
        delete_button.style.left_padding = 10
        ui_util.set_label_color(delete_button, "default_button")
    end
end


-- Handles the subfactory deletion process
function handle_subfactory_deletion(player)
    local ui_state = get_ui_state(player)

    if ui_state.current_activity == "deleting_subfactory" then
        local factory = ui_state.context.factory
        local removed_gui_position = ui_state.context.subfactory.gui_position
        Factory.remove(factory, ui_state.context.subfactory)

        if removed_gui_position > factory.Subfactory.count then removed_gui_position = removed_gui_position - 1 end
        local subfactory = Factory.get_by_gui_position(factory, "Subfactory", removed_gui_position)
        data_util.context.set_subfactory(player, subfactory)

        ui_state.current_activity = nil
    else
        ui_state.current_activity = "deleting_subfactory"
    end

    refresh_main_dialog(player)
end