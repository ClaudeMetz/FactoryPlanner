subfactory_list = {}

-- ** LOCAL UTIL **
local function toggle_archive(player)
    local player_table = data_util.get("table", player)
    local ui_state = player_table.ui_state
    local archive_open = not ui_state.flags.archive_open  -- already negated right here
    ui_state.flags.archive_open = archive_open

    local factory = archive_open and player_table.archive or player_table.factory
    ui_util.context.set_factory(player, factory)
    main_dialog.refresh(player, nil)
end

-- Resets the selected subfactory to a valid position after one has been removed
local function reset_subfactory_selection(player, factory, removed_gui_position)
    if removed_gui_position > factory.Subfactory.count then removed_gui_position = removed_gui_position - 1 end
    local subfactory = Factory.get_by_gui_position(factory, "Subfactory", removed_gui_position)
    ui_util.context.set_subfactory(player, subfactory)
end

-- Refresh the dialog, quitting archive view if it has become empty
local function refresh_with_archive_open(player, factory)
    local archive_open = data_util.get("flags", player).archive_open
    if archive_open and Factory.count(factory, "Subfactory") == 0 then
        toggle_archive(player)  -- does refreshing on its own
    else
        main_dialog.refresh(player, nil)
    end
end

local function archive_subfactory(player)
    local player_table = data_util.get("table", player)
    local ui_state = player_table.ui_state
    local subfactory = ui_state.context.subfactory
    local archive_open = ui_state.flags.archive_open

    local origin = archive_open and player_table.archive or player_table.factory
    local destination = archive_open and player_table.factory or player_table.archive

    local removed_gui_position = Factory.remove(origin, subfactory)
    reset_subfactory_selection(player, origin, removed_gui_position)
    Factory.add(destination, subfactory)

    refresh_with_archive_open(player, origin)
end

local function delete_subfactory(player)
    local context = data_util.get("context", player)
    local removed_gui_position = Factory.remove(context.factory, context.subfactory)
    reset_subfactory_selection(player, context.factory, removed_gui_position)

    refresh_with_archive_open(player, context.factory)
end


local function handle_subfactory_submission(player, options, action)
    local ui_state = data_util.get("ui_state", player)
    local factory = ui_state.context.factory
    local subfactory = ui_state.modal_data.object

    if action == "submit" then
        local name = options.subfactory_name
        local icon = options.subfactory_icon

        if subfactory ~= nil then
            subfactory.name = name
            -- Don't save over the unknown signal to preserve what's saved behind it
            if icon and icon.name ~= "signal-unknown" then subfactory.icon = icon end
        else
            local new_subfactory = Subfactory.init(name, icon, get_settings(player).default_timescale)
            Factory.add(factory, new_subfactory)
            ui_util.context.set_subfactory(player, new_subfactory)
        end

    elseif action == "delete" then
        local removed_gui_position = Factory.remove(factory, subfactory)
        reset_subfactory_selection(player, factory, removed_gui_position)
    end

    if action ~= "cancel" then main_dialog.refresh(player, nil) end
end

local function handle_subfactory_data_change(modal_data, _)
    local modal_elements = modal_data.modal_elements

    -- Remove whitespace from the subfactory name. No cheating!
    local name_text = modal_elements["fp_textfield_options_subfactory_name"].text:gsub("^%s*(.-)%s*$", "%1")
    local icon_spec = modal_elements["fp_choose_elem_button_options_subfactory_icon"].elem_value

    local issue_message = nil
    if name_text == "" and icon_spec == nil then
        issue_message = {"fp.options_subfactory_issue_choose_either"}
    elseif string.len(name_text) > 64 then
        issue_message = {"fp.options_subfactory_issue_max_characters"}
    end

    modal_dialog.set_submit_button_state(modal_elements, (issue_message == nil), issue_message)
end

local function generate_subfactory_dialog_modal_data(action, subfactory)
    local icon = nil
    if subfactory and subfactory.icon then
        local sprite_missing = Subfactory.verify_icon(subfactory)
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


-- ** TOP LEVEL **
subfactory_list.gui_events = {
    on_gui_click = {
        {
            name = "fp_button_subfactories_toggle_archive",
            handler = (function(player, _, _)
                toggle_archive(player)
            end)
        },
        {
            name = "fp_sprite-button_subfactories_export",
            timeout = 20,
            handler = (function(player, _, _)
                modal_dialog.enter(player, {type="export"})
            end)
        },
        {
            name = "fp_sprite-button_subfactories_import",
            timeout = 20,
            handler = (function(player, _, _)
                modal_dialog.enter(player, {type="import", submit=true})
            end)
        },
        {
            name = "fp_sprite-button_subfactory_archive",
            handler = (function(player, _, _)
                archive_subfactory(player)
            end)
        },
        {
            name = "fp_sprite-button_subfactory_duplicate",
            handler = (function(player, _, _)
                local ui_state = data_util.get("ui_state", player)
                local subfactory = ui_state.context.subfactory

                -- This relies on the porting-functionality. It basically exports and
                -- immediately imports the subfactory, effectively duplicating it
                local export_string = data_util.porter.get_export_string(player, {subfactory})
                data_util.add_subfactories_by_string(player, export_string, true)
            end)
        },
        {
            name = "fp_sprite-button_subfactory_add",
            timeout = 20,
            handler = (function(player, _, _)
                local modal_data = generate_subfactory_dialog_modal_data("new", nil)
                modal_dialog.enter(player, {type="options", submit=true, modal_data=modal_data})
            end)
        },
        {
            name = "fp_sprite-button_subfactory_edit",
            timeout = 20,
            handler = (function(player, _, _)
                local subfactory = data_util.get("context", player).subfactory
                local modal_data = generate_subfactory_dialog_modal_data("edit", subfactory)
                modal_dialog.enter(player, {type="options", submit=true, delete=true, modal_data=modal_data})
            end)
        },
        {
            name = "fp_sprite-button_subfactory_delete",
            timeout = 20,
            handler = (function(player, _, _)
                delete_subfactory(player)
            end)
        }
    },
    on_gui_selection_state_changed = {
        {
            name = "fp_list-box_subfactories",
            handler = (function(player, element)
                local factory = data_util.get("context", player).factory
                local subfactory = Factory.get_by_gui_position(factory, "Subfactory", element.selected_index)
                ui_util.context.set_subfactory(player, subfactory)
                main_dialog.refresh(player, "subfactory")
            end)
        }
    }
}

function subfactory_list.build(player)
    local main_elements = data_util.get("main_elements", player)
    main_elements.subfactory_list = {}

    local parent_flow = main_elements.flows.left_vertical
    local frame_vertical = parent_flow.add{type="frame", direction="vertical", style="inside_deep_frame"}
    frame_vertical.style.height = data_util.get("settings", player).subfactory_list_rows * 28

    local subheader = frame_vertical.add{type="frame", direction="horizontal", style="subheader_frame"}

    local button_toggle_archive = subheader.add{type="button", name="fp_button_subfactories_toggle_archive",
      caption={"fp.action_toggle_archive"}, mouse_button_filter={"left"}}
    button_toggle_archive.style.disabled_font_color = {} -- black
    main_elements.subfactory_list["toggle_archive_button"] = button_toggle_archive

    subheader.add{type="line", direction="vertical"}

    local button_export = subheader.add{type="sprite-button", name="fp_sprite-button_subfactories_export",
      sprite="utility/export", tooltip={"fp.action_export_subfactory"}, style="tool_button",
      mouse_button_filter={"left"}}
    main_elements.subfactory_list["export_button"] = button_export

    local button_import = subheader.add{type="sprite-button", name="fp_sprite-button_subfactories_import",
      sprite="utility/import", tooltip={"fp.action_import_subfactory"}, style="tool_button",
      mouse_button_filter={"left"}}
    main_elements.subfactory_list["import_button"] = button_import

    subheader.add{type="empty-widget", style="flib_horizontal_pusher"}

    local button_archive = subheader.add{type="sprite-button", name="fp_sprite-button_subfactory_archive",
      style="tool_button", mouse_button_filter={"left"}}
    main_elements.subfactory_list["archive_button"] = button_archive

    local button_duplicate = subheader.add{type="sprite-button", name="fp_sprite-button_subfactory_duplicate",
      sprite="utility/clone", tooltip={"fp.action_duplicate_subfactory"}, style="tool_button",
      mouse_button_filter={"left"}}
    main_elements.subfactory_list["duplicate_button"] = button_duplicate

    subheader.add{type="line", direction="vertical"}

    local button_add = subheader.add{type="sprite-button", name="fp_sprite-button_subfactory_add",
      sprite="utility/add", tooltip={"fp.action_add_subfactory"}, style="fp_sprite-button_tool_green",
      mouse_button_filter={"left"}}
    button_add.style.top_margin = 0
    main_elements.subfactory_list["add_button"] = button_add

    local button_edit = subheader.add{type="sprite-button", name="fp_sprite-button_subfactory_edit",
      sprite="utility/rename_icon_normal", tooltip={"fp.action_edit_subfactory"}, style="tool_button",
      mouse_button_filter={"left"}}
    main_elements.subfactory_list["edit_button"] = button_edit

    local button_delete = subheader.add{type="sprite-button", name="fp_sprite-button_subfactory_delete",
      sprite="utility/trash", tooltip={"fp.action_delete_subfactory"}, style="tool_button_red",
      mouse_button_filter={"left"}}
    main_elements.subfactory_list["delete_button"] = button_delete


    local listbox_subfactories = frame_vertical.add{type="list-box", name="fp_list-box_subfactories",
      style="list_box_under_subheader"}
    listbox_subfactories.style.vertically_stretchable = true
    main_elements.subfactory_list["subfactory_listbox"] = listbox_subfactories

    subfactory_list.refresh(player)
end

function subfactory_list.refresh(player)
    local player_table = data_util.get("table", player)
    local ui_state = player_table.ui_state
    local subfactory_list_elements = ui_state.main_elements.subfactory_list

    local selected_subfactory = ui_state.context.subfactory
    local listbox_items, selected_index = {}, 0

    if selected_subfactory ~= nil then
        selected_index = selected_subfactory.gui_position
        for _, subfactory in pairs(Factory.get_in_order(ui_state.context.factory, "Subfactory")) do
            table.insert(listbox_items, Subfactory.tostring(subfactory))
        end
    end
    local listbox = subfactory_list_elements.subfactory_listbox
    listbox.items = listbox_items
    listbox.selected_index = selected_index

    -- Set all the button states and styles appropriately
    local subfactory_exists = (selected_subfactory ~= nil)
    local archive_open = (ui_state.flags.archive_open)

    local archived_subfactory_count = Factory.count(player_table.archive, "Subfactory")
    local subfactory_plural = {"fp.pl_subfactory", archived_subfactory_count}
    local archive_tooltip = {"fp.action_toggle_archive_tt", (archived_subfactory_count > 0)
      and {"fp.archive_filled", archived_subfactory_count, subfactory_plural} or {"fp.archive_empty"}}
    subfactory_list_elements.toggle_archive_button.tooltip = archive_tooltip
    subfactory_list_elements.toggle_archive_button.enabled = (archived_subfactory_count > 0)

    subfactory_list_elements.toggle_archive_button.style = (archive_open) and
      "flib_selected_tool_button" or "tool_button"

    subfactory_list_elements.export_button.enabled = (subfactory_exists)
    subfactory_list_elements.import_button.enabled = (not archive_open)

    subfactory_list_elements.archive_button.enabled = (subfactory_exists)
    subfactory_list_elements.archive_button.sprite = (archive_open) and
      "utility/export_slot" or "utility/import_slot"
    subfactory_list_elements.archive_button.tooltip = (archive_open) and
      {"fp.action_unarchive_subfactory"} or {"fp.action_archive_subfactory"}
    subfactory_list_elements.duplicate_button.enabled =
      (subfactory_exists and selected_subfactory.valid and not archive_open)

    subfactory_list_elements.add_button.enabled = (not archive_open)
    subfactory_list_elements.edit_button.enabled = (subfactory_exists)
    subfactory_list_elements.delete_button.enabled = (subfactory_exists)
end