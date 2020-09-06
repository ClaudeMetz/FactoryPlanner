actionbar = {}

-- ** LOCAL UTIL **
local function handle_subfactory_submission(player, options, action)
    local ui_state = get_ui_state(player)
    local factory = ui_state.context.factory
    local subfactory = ui_state.modal_data.object

    if action == "submit" then
        local name = options.subfactory_name
        local icon = options.subfactory_icon

        if subfactory ~= nil then
            subfactory.name = name
            -- Don't save over the unknown signal to preserve what's saved behind it
            if not icon or icon.name ~= "signal-unknown" then subfactory.icon = icon end
        else
            local new_subfactory = Subfactory.init(name, icon, get_settings(player).default_timescale)
            Factory.add(factory, new_subfactory)
            ui_util.context.set_subfactory(player, new_subfactory)
        end

    elseif action == "delete" then
        local removed_gui_position = Factory.remove(factory, subfactory)
        ui_util.reset_subfactory_selection(player, factory, removed_gui_position)
    end

    main_dialog.refresh(player)
end

-- Sets the dialog_submit-button appropriately after any data was changed
local function handle_subfactory_data_change(modal_data, _)
    local ui_elements = modal_data.ui_elements

    -- Remove whitespace from the subfactory name. No cheating!
    local name_text = ui_elements["fp_textfield_options_subfactory_name"].text:gsub("^%s*(.-)%s*$", "%1")
    local icon_spec = ui_elements["fp_choose_elem_button_options_subfactory_icon"].elem_value

    local issue_message = nil
    if name_text == "" and icon_spec == nil then
        issue_message = {"fp.options_subfactory_issue_choose_either"}
    elseif string.len(name_text) > 64 then
        issue_message = {"fp.options_subfactory_issue_max_characters"}
    end

    modal_dialog.set_submit_button_state(ui_elements, (issue_message == nil), issue_message)
end


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

local function generate_subfactory_dialog_modal_data(action, subfactory)
    local icon = nil
    if subfactory and subfactory.icon then
        local sprite_missing = ui_util.verify_subfactory_icon(subfactory)
        icon = (sprite_missing) and {type="virtual", name="signal-unknown"} or subfactory.icon
    end

    local modal_data = {
        title = {"fp.two_word_title", {"fp." .. action}, {"fp.pl_subfactory", 1}},
        text = {"fp.options_subfactory_text"},
        minimal_width = 325,
        submission_handler = handle_subfactory_submission,
        object = subfactory,
        fields = {
            {
                type = "textfield",
                name = "subfactory_name",
                change_handler = handle_subfactory_data_change,
                caption = {"fp.options_subfactory_name"},
                text = (subfactory) and subfactory.name or "",
                focus = true
            },
            {
                type = "choose_elem_button",
                name = "subfactory_icon",
                change_handler = handle_subfactory_data_change,
                caption = {"fp.options_subfactory_icon"},
                elem_type = "signal",
                elem_value = icon
            }
        }
    }
    return modal_data
end


function actionbar.new_subfactory(player)
    local modal_data = generate_subfactory_dialog_modal_data("new", nil)
    modal_dialog.enter(player, {type="options", submit=true, modal_data=modal_data})
end

function actionbar.edit_subfactory(player)
    local subfactory = data_util.get("context", player).subfactory
    local modal_data = generate_subfactory_dialog_modal_data("edit", subfactory)
    modal_dialog.enter(player, {type="options", submit=true, delete=true, modal_data=modal_data})
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

    main_dialog.refresh(player)
end

function actionbar.duplicate_subfactory(player)
    local ui_state = get_ui_state(player)
    local subfactory = ui_state.context.subfactory

    -- This relies on the porting-functionality. It basically exports and
    -- immediately imports the subfactory, effectively duplicating it
    local export_string = data_util.porter.get_export_string(player, {subfactory})
    data_util.add_subfactories_by_string(player, export_string, true)
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

    main_dialog.refresh(player)
end