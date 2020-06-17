-- Creates the actionbar including the new-, edit- and delete-buttons
function add_actionbar_to(main_dialog)
    local actionbar = main_dialog.add{type="flow", name="flow_action_bar", direction="horizontal"}
    actionbar.style.bottom_margin = 4
    actionbar.style.left_margin = 6

    actionbar.add{type="button", name="fp_button_new_subfactory", caption={"fp.new_subfactory"},
      style="fp_button_action", mouse_button_filter={"left"}, tooltip={"fp.action_new_subfactory"}}
    actionbar.add{type="button", name="fp_button_edit_subfactory", caption={"fp.edit"},
      style="fp_button_action", mouse_button_filter={"left"}, tooltip={"fp.action_edit_subfactory"}}
    actionbar.add{type="button", name="fp_button_archive_subfactory", caption={"fp.archive"},
      style="fp_button_action", mouse_button_filter={"left"}}
    actionbar.add{type="button", name="fp_button_delete_subfactory", caption={"fp.delete"},
      style="fp_button_action", mouse_button_filter={"left"}, tooltip={"fp.action_delete_subfactory"}}

    local actionbar_spacer = actionbar.add{type="flow", name="flow_actionbar_spacer", direction="horizontal"}
    actionbar_spacer.style.horizontally_stretchable = true

    actionbar.add{type="button", name="fp_button_toggle_archive",
      caption={"fp.open_archive"}, style="fp_button_action", mouse_button_filter={"left"}}

    refresh_actionbar(game.get_player(main_dialog.player_index))
end


-- Disables edit and delete buttons if there exist no subfactories
function refresh_actionbar(player)
    local ui_state = get_ui_state(player)
    local archive_open = ui_state.flags.archive_open
    local actionbar = player.gui.screen["fp_frame_main_dialog"]["flow_action_bar"]
    local new_button = actionbar["fp_button_new_subfactory"]
    local delete_button = actionbar["fp_button_delete_subfactory"]
    local archive_button = actionbar["fp_button_archive_subfactory"]
    local toggle_archive_button = actionbar["fp_button_toggle_archive"]
    toggle_archive_button.style.width = 148  -- set here so it doesn't get lost somehow

    local subfactory_exists = (ui_state.context.subfactory ~= nil)
    actionbar["fp_button_edit_subfactory"].enabled = subfactory_exists
    delete_button.enabled = subfactory_exists

    archive_button.enabled = subfactory_exists
    archive_button.tooltip = (archive_open) and
      {"fp.action_unarchive_subfactory"} or {"fp.action_archive_subfactory"}

    local archived_subfactories_count = get_table(player).archive.Subfactory.count
    toggle_archive_button.enabled = (archive_open or archived_subfactories_count > 0)
    local archive_tooltip = {"fp.toggle_archive"}
    if not toggle_archive_button.enabled then
        archive_tooltip = {"", archive_tooltip, "\n", {"fp.archive_empty"}}
    else
        local subs = (archived_subfactories_count == 1) and {"fp.subfactory"} or {"fp.subfactories"}
        archive_tooltip = {"", archive_tooltip, "\n- ", {"fp.archive_filled"},
          " " .. archived_subfactories_count .. " ", subs, " -"}
    end
    toggle_archive_button.tooltip = archive_tooltip

    if ui_state.current_activity == "deleting_subfactory" then
        delete_button.caption = {"fp.delete_confirm"}
        delete_button.style.font =  "fp-font-bold-16p"
        delete_button.style.left_padding = 16
        ui_util.set_label_color(delete_button, "dark_red")
    else
        delete_button.caption = {"fp.delete"}
        delete_button.style.font =  "fp-font-semibold-16p"
        delete_button.style.left_padding = 10
        ui_util.set_label_color(delete_button, "default_button")
    end

    if archive_open then
        new_button.enabled = false
        archive_button.caption = {"fp.unarchive"}
        toggle_archive_button.caption = {"fp.close_archive"}
        toggle_archive_button.style = "fp_button_action_selected"
    else
        new_button.enabled = true
        archive_button.caption = {"fp.archive"}
        toggle_archive_button.caption = {"fp.open_archive"}
        toggle_archive_button.style = "fp_button_action"
    end
end


-- Resets the selected subfactory to a valid position after one has been removed
local function reset_subfactory_selection(player, factory, removed_gui_position)
    if removed_gui_position > factory.Subfactory.count then removed_gui_position = removed_gui_position - 1 end
    local subfactory = Factory.get_by_gui_position(factory, "Subfactory", removed_gui_position)
    ui_util.context.set_subfactory(player, subfactory)
end


-- Handles the subfactory deletion process
function handle_subfactory_deletion(player)
    local ui_state = get_ui_state(player)

    if ui_state.current_activity == "deleting_subfactory" then
        local factory = ui_state.context.factory
        local removed_gui_position = Factory.remove(factory, ui_state.context.subfactory)
        reset_subfactory_selection(player, factory, removed_gui_position)

        ui_state.current_activity = nil
        refresh_main_dialog(player)
    else
        ui_state.current_activity = "deleting_subfactory"
        refresh_current_activity(player)
    end
end

-- Handles (un)archiving the current subfactory
function handle_subfactory_archivation(player)
    local player_table = get_table(player)
    local ui_state = player_table.ui_state
    local subfactory = ui_state.context.subfactory
    local archive_open = ui_state.flags.archive_open

    local origin = archive_open and player_table.archive or player_table.factory
    local destination = archive_open and player_table.factory or player_table.archive

    local removed_gui_position = Factory.remove(origin, subfactory)
    reset_subfactory_selection(player, origin, removed_gui_position)
    Factory.add(destination, subfactory)

    ui_state.current_activity = nil
    refresh_main_dialog(player)
end

-- Enters or leaves the archive-viewing mode
function toggle_archive_view(player)
    local player_table = get_table(player)
    local ui_state = player_table.ui_state
    local archive_open = not ui_state.flags.archive_open  -- already negated right here
    ui_state.flags.archive_open = archive_open

    local factory = archive_open and player_table.archive or player_table.factory
    ui_util.context.set_factory(player, factory)

    ui_state.current_activity = nil
    refresh_main_dialog(player)
end