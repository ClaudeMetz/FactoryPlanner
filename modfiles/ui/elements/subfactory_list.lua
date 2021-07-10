subfactory_list = {}

-- ** LOCAL UTIL **
local function toggle_archive(player, _, _)
    local player_table = data_util.get("table", player)
    local flags = player_table.ui_state.flags
    flags.archive_open = not flags.archive_open

    local factory = flags.archive_open and player_table.archive or player_table.factory
    ui_util.context.set_factory(player, factory)
    main_dialog.refresh(player, "all")
end

function GENERIC_HANDLERS.handle_subfactory_submission(player, options, action)
    local ui_state = data_util.get("ui_state", player)
    local subfactory = ui_state.modal_data.object

    if action == "submit" then
        local name = options.subfactory_name
        local icon = options.subfactory_icon
        -- Somehow, choosing the 'signal-unkown' icon spec has no icon name
        icon = (icon and icon.name) and icon or nil

        if subfactory ~= nil then
            subfactory.name, subfactory.icon = name, icon
        else
            subfactory_list.add_subfactory(player, name, icon)
        end
        main_dialog.refresh(player, "all")

    elseif action == "delete" then
        local factory = ui_state.context.factory
        local removed_gui_position = Factory.remove(factory, subfactory)
        subfactory_list.refresh_after_deletion(player, factory, removed_gui_position)
    end
end

function GENERIC_HANDLERS.handle_subfactory_data_change(modal_data, _)
    local modal_elements = modal_data.modal_elements

    -- Remove whitespace from the subfactory name. No cheating!
    local name_text = modal_elements["subfactory_name"].text:gsub("^%s*(.-)%s*$", "%1")
    local icon_spec = modal_elements["subfactory_icon"].elem_value

    local issue_message = nil
    if name_text == "" and (icon_spec == nil or icon_spec.name == nil) then
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
        icon = (not sprite_missing) and subfactory.icon or nil
    end

    local modal_data = {
        title = {"fp.two_word_title", {"fp." .. action}, {"fp.pl_subfactory", 1}},
        text = {"fp.options_subfactory_text"},
        submission_handler_name = "handle_subfactory_submission",
        allow_deletion = (action == "edit"),
        object = subfactory,
        fields = {
            {
                type = "textfield",
                name = "subfactory_name",
                change_handler_name = "handle_subfactory_data_change",
                caption = {"fp.options_subfactory_name"},
                text = (subfactory) and subfactory.name or "",
                width = 200,
                focus = true
            },
            {
                type = "choose_elem_button",
                name = "subfactory_icon",
                change_handler_name = "handle_subfactory_data_change",
                caption = {"fp.options_subfactory_icon"},
                elem_type = "signal",
                elem_value = icon
            }
        }
    }
    return modal_data
end


local function archive_subfactory(player, _, _)
    local player_table = data_util.get("table", player)
    local ui_state = player_table.ui_state
    local subfactory = ui_state.context.subfactory
    local archive_open = ui_state.flags.archive_open

    local origin = archive_open and player_table.archive or player_table.factory
    local destination = archive_open and player_table.factory or player_table.archive

    -- Reset deletion if a deleted subfactory is un-archived
    if archive_open and subfactory.tick_of_deletion then
        data_util.nth_tick.remove(subfactory.tick_of_deletion)
        subfactory.tick_of_deletion = nil
    end

    local removed_gui_position = Factory.remove(origin, subfactory)
    Factory.add(destination, subfactory)  -- needs to be added after the removal else shit breaks
    subfactory_list.refresh_after_deletion(player, origin, removed_gui_position)
end

local function add_subfactory(player, _, metadata)
    if metadata.alt then
        -- If alt is pressed, go right to the item picker, which will determine the subfactory icon
        modal_dialog.enter(player, {type="picker", modal_data={object=nil, item_category="product",
          create_subfactory=true}})

    else  -- otherwise, go through the normal proceedure
        local modal_data = generate_subfactory_dialog_modal_data("new", nil)
        modal_dialog.enter(player, {type="options", modal_data=modal_data})
    end
end

local function edit_subfactory(player, _, _)
    local subfactory = data_util.get("context", player).subfactory
    local modal_data = generate_subfactory_dialog_modal_data("edit", subfactory)
    modal_dialog.enter(player, {type="options", modal_data=modal_data})
end

local function delete_subfactory(player, _, _)
    local ui_state = data_util.get("ui_state", player)
    local subfactory = ui_state.context.subfactory
    if subfactory == nil then return end  -- prevent crashes due to multiplayer latency

    if ui_state.flags.archive_open then
        if subfactory.tick_of_deletion then data_util.nth_tick.remove(subfactory.tick_of_deletion) end

        local factory = ui_state.context.factory
        local removed_gui_position = Factory.remove(factory, subfactory)
        subfactory_list.refresh_after_deletion(player, factory, removed_gui_position)
    else
        local desired_tick_of_deletion = game.tick + SUBFACTORY_DELETION_DELAY
        local actual_tick_of_deletion = data_util.nth_tick.add(desired_tick_of_deletion,
          "delete_subfactory_for_good", {player_index=player.index, subfactory=subfactory})
        subfactory.tick_of_deletion = actual_tick_of_deletion

        archive_subfactory(player)
    end
end


local function handle_subfactory_click(player, tags, metadata)
    local ui_state = data_util.get("ui_state", player)
    local context = ui_state.context
    local subfactory = Factory.get(context.factory, "Subfactory", tags.subfactory_id)

    if metadata.direction ~= nil then  -- shift subfactory in the given direction
        local shifting_function = (metadata.alt) and Factory.shift_to_end or Factory.shift
        if shifting_function(context.factory, subfactory, metadata.direction) then
            main_dialog.refresh(player, "subfactory_list")
        else
            local direction_string = (metadata.direction == "negative") and {"fp.up"} or {"fp.down"}
            local message = {"fp.error_list_item_cant_be_shifted", {"fp.pl_subfactory", 1}, direction_string}
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
            main_dialog.refresh(player, "all")

        elseif metadata.click == "right" then
            if metadata.action == "edit" then
                main_dialog.refresh(player, "all")  -- refresh to update the selected subfactory
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

    local button_toggle_archive = subheader.add{type="sprite-button", tags={mod="fp", on_gui_click="toggle_archive"},
      sprite="fp_sprite_archive_dark", mouse_button_filter={"left"}}
    main_elements.subfactory_list["toggle_archive_button"] = button_toggle_archive

    subheader.add{type="line", direction="vertical"}

    local button_import = subheader.add{type="sprite-button", sprite="utility/import",
      tooltip={"fp.action_import_subfactory"}, style="tool_button", mouse_button_filter={"left"},
      tags={mod="fp", on_gui_click="subfactory_list_open_dialog", type="import"}}
    main_elements.subfactory_list["import_button"] = button_import

    local button_export = subheader.add{type="sprite-button", sprite="utility/export",
      tooltip={"fp.action_export_subfactory"}, style="tool_button", mouse_button_filter={"left"},
      tags={mod="fp", on_gui_click="subfactory_list_open_dialog", type="export"}}
    main_elements.subfactory_list["export_button"] = button_export

    subheader.add{type="empty-widget", style="flib_horizontal_pusher"}

    local button_archive = subheader.add{type="sprite-button", tags={mod="fp", on_gui_click="archive_subfactory"},
      style="tool_button", mouse_button_filter={"left"}}
    main_elements.subfactory_list["archive_button"] = button_archive

    local button_duplicate = subheader.add{type="sprite-button", tags={mod="fp", on_gui_click="duplicate_subfactory"},
      sprite="utility/clone", tooltip={"fp.action_duplicate_subfactory"}, style="tool_button",
      mouse_button_filter={"left"}}
    main_elements.subfactory_list["duplicate_button"] = button_duplicate

    subheader.add{type="line", direction="vertical"}

    local button_add = subheader.add{type="sprite-button", tags={mod="fp", on_gui_click="add_subfactory"},
      sprite="utility/add", tooltip={"fp.action_add_subfactory"}, style="flib_tool_button_light_green",
      mouse_button_filter={"left"}}
    main_elements.subfactory_list["add_button"] = button_add

    local button_edit = subheader.add{type="sprite-button", tags={mod="fp", on_gui_click="edit_subfactory"},
      sprite="utility/rename_icon_normal", tooltip={"fp.action_edit_subfactory"}, style="tool_button",
      mouse_button_filter={"left"}}
    main_elements.subfactory_list["edit_button"] = button_edit

    local button_delete = subheader.add{type="sprite-button", tags={mod="fp", on_gui_click="delete_subfactory"},
      sprite="utility/trash", style="tool_button_red", mouse_button_filter={"left"}}
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
            local caption, info_tooltip = Subfactory.tostring(subfactory, false)
            local tooltip = {"", info_tooltip, tutorial_tooltip}

            listbox.add{type="button", tags={mod="fp", on_gui_click="act_on_subfactory", subfactory_id=subfactory.id},
              caption=caption, tooltip=tooltip, style=style, mouse_button_filter={"left-and-right"}}
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

    subfactory_list_elements.import_button.enabled = (not archive_open)
    subfactory_list_elements.export_button.enabled = (subfactory_exists)

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
    local delay_in_minutes = math.floor(SUBFACTORY_DELETION_DELAY / 3600)
    subfactory_list_elements.delete_button.tooltip = (archive_open) and
      {"fp.action_delete_subfactory"} or {"fp.action_trash_subfactory", delay_in_minutes}
end

-- Refresh the dialog, quitting archive view if it has become empty
function subfactory_list.refresh_after_deletion(player, factory, removed_gui_position)
    if removed_gui_position > factory.Subfactory.count then removed_gui_position = removed_gui_position - 1 end
    local subfactory = Factory.get_by_gui_position(factory, "Subfactory", removed_gui_position)
    ui_util.context.set_subfactory(player, subfactory)

    local archive_open = data_util.get("flags", player).archive_open
    if archive_open and Factory.count(factory, "Subfactory") == 0 then
        -- Make sure the just-unarchived subfactory is the selected one in factory; It'll always be the last one
        local main_factory = data_util.get("table", player).factory
        local last_position = Factory.count(main_factory, "Subfactory")
        -- It's okay to set selected_subfactory directly here, as toggle_archive calls the proper context util function
        main_factory.selected_subfactory = Factory.get_by_gui_position(main_factory, "Subfactory", last_position)

        toggle_archive(player)  -- does refreshing on its own
    else
        main_dialog.refresh(player, "all")
    end
end

-- Utility function to centralize subfactory creation behavior
function subfactory_list.add_subfactory(player, name, icon)
    local subfactory = Subfactory.init(name, icon)

    local settings = data_util.get("settings", player)
    subfactory.timescale = settings.default_timescale
    if settings.prefer_matrix_solver then subfactory.matrix_free_items = {} end

    local context = data_util.get("context", player)
    Factory.add(context.factory, subfactory)
    ui_util.context.set_subfactory(player, subfactory)
end


-- Delete subfactory for good and refresh interface if necessary
function NTH_TICK_HANDLERS.delete_subfactory_for_good(metadata)
    local archive = metadata.subfactory.parent
    local removed_gui_position = Factory.remove(archive, metadata.subfactory)

    local player = game.get_player(metadata.player_index)
    if data_util.get("main_elements", player).main_frame == nil then return end

    if data_util.get("flags", player).archive_open then
        subfactory_list.refresh_after_deletion(player, archive, removed_gui_position)
    else  -- doing this conditional is a bit dumb, but it works (I think)
        main_dialog.refresh(player, "all")
    end
end


-- ** EVENTS **
subfactory_list.gui_events = {
    on_gui_click = {
        {
            name = "toggle_archive",
            handler = toggle_archive
        },
        {
            name = "subfactory_list_open_dialog",
            handler = (function(player, tags, _)
                modal_dialog.enter(player, {type=tags.type})
            end)
        },
        {
            name = "archive_subfactory",
            handler = archive_subfactory
        },
        {
            name = "duplicate_subfactory",
            handler = (function(player, _, _)
                local ui_state = data_util.get("ui_state", player)
                local subfactory = ui_state.context.subfactory

                -- This relies on the porting-functionality. It basically exports and
                -- immediately imports the subfactory, effectively duplicating it
                local export_string = data_util.porter.get_export_string({subfactory})
                data_util.add_subfactories_by_string(player, export_string, true)
            end)
        },
        {
            name = "add_subfactory",
            handler = add_subfactory
        },
        {
            name = "edit_subfactory",
            handler = edit_subfactory
        },
        {
            name = "delete_subfactory",
            timeout = 20,
            handler = delete_subfactory
        },
        {
            name = "act_on_subfactory",
            handler = handle_subfactory_click
        }
    }
}
