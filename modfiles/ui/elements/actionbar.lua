actionbar = {}

-- ** TOP LEVEL **
-- Creates the actionbar including the new-, edit-, (un)archive- and duplicate-buttons
function actionbar.add_to(main_dialog)
    local flow_actionbar = main_dialog.add{type="flow", name="flow_action_bar", direction="horizontal"}
    flow_actionbar.style.bottom_margin = 4
    flow_actionbar.style.left_margin = 6
    flow_actionbar.style.height = 32

    local action_buttons = {
        {name = "new", extend_caption=true},
        {name = "separation_line"},
        {name = "edit"},
        {name = "archive"},
        {name = "duplicate"},
        {name = "separation_line"},
        {name = "import"},
        {name = "export"}
    }

    for _, ab in ipairs(action_buttons) do
        if ab.name == "separation_line" then
            flow_actionbar.add{type="line", direction="vertical"}
        else
            local caption = {"fp." .. ab.name}
            if ab.extend_caption then caption = {"", caption, " ", {"fp.csubfactory"}} end

            flow_actionbar.add{type="button", name="fp_button_actionbar_" .. ab.name,
              caption=caption, style="fp_button_action", mouse_button_filter={"left"},
              tooltip={"fp.action_" .. ab.name .. "_subfactory"}}
        end
    end

    local actionbar_spacer = flow_actionbar.add{type="flow", name="flow_actionbar_spacer", direction="horizontal"}
    actionbar_spacer.style.horizontally_stretchable = true

    flow_actionbar.add{type="button", name="fp_button_toggle_archive", caption={"fp.open_archive"},
      style="fp_button_action", mouse_button_filter={"left"}}

    actionbar.refresh(game.get_player(main_dialog.player_index))
end

function actionbar.refresh(player)
    local ui_state = get_ui_state(player)
    local subfactory = ui_state.context.subfactory
    local archive_open = ui_state.flags.archive_open

    local flow_actionbar = player.gui.screen["fp_frame_main_dialog"]["flow_action_bar"]
    local new_button = flow_actionbar["fp_button_actionbar_new"]
    local archive_button = flow_actionbar["fp_button_actionbar_archive"]
    local toggle_archive_button = flow_actionbar["fp_button_toggle_archive"]

    local subfactory_exists, subfactory_valid = (subfactory ~= nil), (subfactory and subfactory.valid)
    flow_actionbar["fp_button_actionbar_edit"].enabled = subfactory_exists
    archive_button.enabled = subfactory_exists
    flow_actionbar["fp_button_actionbar_duplicate"].enabled = subfactory_exists and subfactory_valid
    flow_actionbar["fp_button_actionbar_export"].enabled = subfactory_exists

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
    toggle_archive_button.style.width = 148  -- set here so it doesn't get lost somehow

    if archive_open then
        new_button.enabled = false
        archive_button.caption = {"fp.unarchive"}
        archive_button.tooltip = {"fp.action_unarchive_subfactory"}
        toggle_archive_button.caption = {"fp.close_archive"}
        toggle_archive_button.style = "fp_button_action_selected"
    else
        new_button.enabled = true
        archive_button.caption = {"fp.archive"}
        archive_button.tooltip = {"fp.action_archive_subfactory"}
        toggle_archive_button.caption = {"fp.open_archive"}
        toggle_archive_button.style = "fp_button_action"
    end
end


function actionbar.new_subfactory(player)
    modal_dialog.enter(player, {type="subfactory", submit=true})
end

function actionbar.edit_subfactory(player)
    modal_dialog.enter(player, {type="subfactory", submit=true, delete=true,
      modal_data={subfactory = get_context(player).subfactory}})
end

function actionbar.archive_subfactory(player)
    local player_table = get_table(player)
    local ui_state = player_table.ui_state
    local subfactory = ui_state.context.subfactory
    local archive_open = ui_state.flags.archive_open

    local origin = archive_open and player_table.archive or player_table.factory
    local destination = archive_open and player_table.factory or player_table.archive

    local removed_gui_position = Factory.remove(origin, subfactory)
    ui_util.reset_subfactory_selection(player, origin, removed_gui_position)
    Factory.add(destination, subfactory)

    ui_state.current_activity = nil
    main_dialog.refresh(player)
end

function actionbar.duplicate_subfactory(player, alt)
    local ui_state = get_ui_state(player)
    local subfactory = ui_state.context.subfactory
    local export_string = prototyper.porter.get_export_string(player, {subfactory})

    -- alt-clicking in devmode prints the export-string to the log for later use
    if alt and devmode then
        llog(export_string)
    else
        ui_state.current_activity = nil

        -- This relies on the porting-functionality. It basically exports and
        -- immediately imports the subfactory, effectively duplicating it
        ui_util.add_subfactories_by_string(player, export_string, true)
    end
end

function actionbar.import_subfactory(player)
    modal_dialog.enter(player, {type="import", submit=true})
end

function actionbar.export_subfactory(player)
    modal_dialog.enter(player, {type="export"})
end


-- Enters or leaves the archive-viewing mode
function actionbar.toggle_archive_view(player)
    local player_table = get_table(player)
    local ui_state = player_table.ui_state
    local archive_open = not ui_state.flags.archive_open  -- already negated right here
    ui_state.flags.archive_open = archive_open

    local factory = archive_open and player_table.archive or player_table.factory
    ui_util.context.set_factory(player, factory)

    ui_state.current_activity = nil
    main_dialog.refresh(player)
end