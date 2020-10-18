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
        -- Make sure the just-unarchived subfactory is the selected one in factory; It'll always be the last one
        local main_factory = data_util.get("table", player).factory
        local last_position = Factory.count(main_factory, "Subfactory")
        -- It's okay to set selected_subfactory directly here, as toggle_archive calls the proper context util function
        main_factory.selected_subfactory = Factory.get_by_gui_position(main_factory, "Subfactory", last_position)

        toggle_archive(player)  -- does refreshing on its own
    else
        main_dialog.refresh(player, nil)
    end
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
            local new_subfactory = Subfactory.init(name, icon, data_util.get("settings", player).default_timescale)
            Factory.add(factory, new_subfactory)
            ui_util.context.set_subfactory(player, new_subfactory)
        end
        main_dialog.refresh(player, nil)

    elseif action == "delete" then
        local removed_gui_position = Factory.remove(factory, subfactory)
        reset_subfactory_selection(player, factory, removed_gui_position)
        refresh_with_archive_open(player, factory)
    end
end

local function handle_subfactory_data_change(modal_data, _)
    local modal_elements = modal_data.modal_elements

    -- Remove whitespace from the subfactory name. No cheating!
    local name_text = modal_elements["fp_textfield_options_subfactory_name"].text:gsub("^%s*(.-)%s*$", "%1")
    local icon_spec = modal_elements["fp_choose_elem_button_options_subfactory_icon"].elem_value

    local issue_message = nil
    if name_text == "" and icon_spec == nil then
        issue_message = {"fp.options_subfactory_issue_choose_either"}
    elseif string.len(name_text) > 256 then
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
        submission_handler = handle_subfactory_submission,
        object = subfactory,
        fields = {
            {
                type = "textfield",
                name = "subfactory_name",
                change_handler = handle_subfactory_data_change,
                caption = {"fp.options_subfactory_name"},
                text = (subfactory) and subfactory.name or "",
                width = 200,
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

local function edit_subfactory(player)
    local subfactory = data_util.get("context", player).subfactory
    local modal_data = generate_subfactory_dialog_modal_data("edit", subfactory)
    modal_dialog.enter(player, {type="options", submit=true, delete=true, modal_data=modal_data})
end

local function delete_subfactory(player)
    local context = data_util.get("context", player)
    local removed_gui_position = Factory.remove(context.factory, context.subfactory)
    reset_subfactory_selection(player, context.factory, removed_gui_position)
    refresh_with_archive_open(player, context.factory)
end


local function handle_subfactory_click(player, button, metadata)
    local subfactory_id = string.gsub(button.name, "fp_button_subfactory_", "")
    local ui_state = data_util.get("ui_state", player)
    local context = ui_state.context
    local subfactory = Factory.get(context.factory, "Subfactory", tonumber(subfactory_id))

    if metadata.direction ~= nil then  -- shift subfactory in the given direction
        local shifting_function = (metadata.alt) and Factory.shift_to_end or Factory.shift
        if shifting_function(context.factory, subfactory, metadata.direction) then
            main_dialog.refresh(player, {"subfactory_list"})
        else
            local direction_string = (metadata.direction == "negative") and {"fp.up"} or {"fp.down"}
            local message = {"fp.error_list_item_cant_be_shifted", {"fp.subfactory"}, direction_string}
            title_bar.enqueue_message(player, message, "error", 1, true)
        end
    else
        local old_subfactory = context.subfactory
        ui_util.context.set_subfactory(player, subfactory)

        if metadata.click == "left" then
            if old_subfactory.id == subfactory.id then
                -- Reset Floor when clicking on selected subfactory
                production_box.change_floor(player, "top")
            elseif ui_state.flags.recalculate_on_subfactory_change then
                -- This flag is set when a textfield is changed but not confirmed
                ui_state.flags.recalculate_on_subfactory_change = false
                calculation.update(player, old_subfactory)
            end
            main_dialog.refresh(player, nil)

        elseif metadata.click == "right" then
            if metadata.action == "edit" then
                main_dialog.refresh(player, nil)  -- refresh to update the selected subfactory
                edit_subfactory(player)
            elseif metadata.action == "delete" then
                delete_subfactory(player)
            end
        end
    end
end


-- ** TOP LEVEL **
function subfactory_list.build(player)
    local main_elements = data_util.get("main_elements", player)
    main_elements.subfactory_list = {}

    local parent_flow = main_elements.flows.left_vertical
    local frame_vertical = parent_flow.add{type="frame", direction="vertical", style="inside_deep_frame"}
    local row_count = data_util.get("settings", player).subfactory_list_rows
    frame_vertical.style.height = SUBFACTORY_SUBHEADER_HEIGHT + (row_count * SUBFACTORY_LIST_ELEMENT_HEIGHT)

    local subheader = frame_vertical.add{type="frame", direction="horizontal", style="subheader_frame"}

    local button_toggle_archive = subheader.add{type="button", name="fp_button_subfactories_toggle_archive",
      caption={"fp.action_toggle_archive"}, mouse_button_filter={"left"}}
    button_toggle_archive.style.disabled_font_color = {}
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
      sprite="utility/add", tooltip={"fp.action_add_subfactory"}, style="flib_tool_button_light_green",
      mouse_button_filter={"left"}}
    main_elements.subfactory_list["add_button"] = button_add

    local button_edit = subheader.add{type="sprite-button", name="fp_sprite-button_subfactory_edit",
      sprite="utility/rename_icon_normal", tooltip={"fp.action_edit_subfactory"}, style="tool_button",
      mouse_button_filter={"left"}}
    main_elements.subfactory_list["edit_button"] = button_edit

    local button_delete = subheader.add{type="sprite-button", name="fp_sprite-button_subfactory_delete",
      sprite="utility/trash", tooltip={"fp.action_delete_subfactory"}, style="tool_button_red",
      mouse_button_filter={"left"}}
    main_elements.subfactory_list["delete_button"] = button_delete

    -- This is not really a list-box, but it imitates one and allows additional features
    local listbox_subfactories = frame_vertical.add{type="scroll-pane", style="fp_scroll-pane_fake_listbox"}
    listbox_subfactories.style.width = SUBFACTORY_LIST_WIDTH
    main_elements.subfactory_list["subfactory_listbox"] = listbox_subfactories

    subfactory_list.refresh(player)
end

function subfactory_list.refresh(player)
    local player_table = data_util.get("table", player)
    local ui_state = player_table.ui_state
    local subfactory_list_elements = ui_state.main_elements.subfactory_list

    local selected_subfactory = ui_state.context.subfactory
    local listbox = subfactory_list_elements.subfactory_listbox
    listbox.clear()

    local tutorial_tooltip = ui_util.generate_tutorial_tooltip(player, "subfactory", false, true, false)
    if selected_subfactory ~= nil then  -- only need to run this if any subfactory exists
        for _, subfactory in pairs(Factory.get_in_order(ui_state.context.factory, "Subfactory")) do
            local selected = (selected_subfactory.id == subfactory.id)
            local style = (selected) and "fp_button_fake_listbox_item_active" or "fp_button_fake_listbox_item"
            local caption = Subfactory.tostring(subfactory, true)
            local tooltip = {"", caption, tutorial_tooltip}

            listbox.add{type="button", name="fp_button_subfactory_" .. subfactory.id, caption=caption,
              tooltip=tooltip, style=style, mouse_button_filter={"left-and-right"}}
        end
    end

    -- Set all the button states and styles appropriately
    local subfactory_exists = (selected_subfactory ~= nil)
    local archive_open = (ui_state.flags.archive_open)

    local archived_subfactory_count = Factory.count(player_table.archive, "Subfactory")
    subfactory_list_elements.toggle_archive_button.enabled = (archived_subfactory_count > 0)
    subfactory_list_elements.toggle_archive_button.style = (archive_open) and
      "flib_selected_tool_button" or "tool_button"

    if not archive_open then
        local subfactory_plural = {"fp.pl_subfactory", archived_subfactory_count}
        local archive_tooltip = {"fp.action_open_archive_tt", (archived_subfactory_count > 0)
          and {"fp.archive_filled", archived_subfactory_count, subfactory_plural} or {"fp.archive_empty"}}
        subfactory_list_elements.toggle_archive_button.tooltip = archive_tooltip
    else
        subfactory_list_elements.toggle_archive_button.tooltip = {"fp.action_close_archive_tt"}
    end

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


-- ** EVENTS **
subfactory_list.gui_events = {
    on_gui_click = {
        {
            name = "fp_button_subfactories_toggle_archive",
            handler = toggle_archive
        },
        {
            name = "fp_sprite-button_subfactories_export",
            handler = (function(player, _, _)
                modal_dialog.enter(player, {type="export"})
            end)
        },
        {
            name = "fp_sprite-button_subfactories_import",
            handler = (function(player, _, _)
                modal_dialog.enter(player, {type="import", submit=true})
            end)
        },
        {
            name = "fp_sprite-button_subfactory_archive",
            handler = archive_subfactory
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
            handler = edit_subfactory
        },
        {
            name = "fp_sprite-button_subfactory_delete",
            timeout = 20,
            handler = delete_subfactory
        },
        {
            pattern = "^fp_button_subfactory_%d+$",
            handler = handle_subfactory_click
        }
    }
}