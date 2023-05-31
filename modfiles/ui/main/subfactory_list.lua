-- ** LOCAL UTIL **
local function toggle_archive(player, _, _)
    local player_table = util.globals.player_table(player)
    local flags = player_table.ui_state.flags
    flags.archive_open = not flags.archive_open

    local factory = flags.archive_open and player_table.archive or player_table.factory
    util.context.set_factory(player, factory)
    util.raise.refresh(player, "all", nil)
end

-- Refresh the dialog, quitting archive view if it has become empty
local function refresh_after_subfactory_deletion(player, factory, removed_gui_position)
    if removed_gui_position > factory.Subfactory.count then removed_gui_position = removed_gui_position - 1 end
    local subfactory = Factory.get_by_gui_position(factory, "Subfactory", removed_gui_position)
    util.context.set_subfactory(player, subfactory)

    local archive_open = util.globals.flags(player).archive_open
    if archive_open and Factory.count(factory, "Subfactory") == 0 then
        -- Make sure the just-unarchived subfactory is the selected one in factory; It'll always be the last one
        local main_factory = util.globals.player_table(player).factory
        local last_position = Factory.count(main_factory, "Subfactory")
        -- It's okay to set selected_subfactory directly here, as toggle_archive calls the proper context util function
        main_factory.selected_subfactory = Factory.get_by_gui_position(main_factory, "Subfactory", last_position)

        toggle_archive(player)  -- does refreshing on its own
    else
        util.raise.refresh(player, "all", nil)
    end
end

-- Delete subfactory for good and refresh interface if necessary
local function delete_subfactory_for_good(metadata)
    local archive = metadata.subfactory.parent
    local removed_gui_position = Factory.remove(archive, metadata.subfactory)

    local player = game.get_player(metadata.player_index)  ---@cast player -nil
    if util.globals.main_elements(player).main_frame == nil then return end

    if util.globals.flags(player).archive_open then
        refresh_after_subfactory_deletion(player, archive, removed_gui_position)
    else  -- only need to refresh the archive button enabled state really
        util.raise.refresh(player, "subfactory_list", nil)
    end
end


local function archive_subfactory(player, _, _)
    local player_table = util.globals.player_table(player)
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
    refresh_after_subfactory_deletion(player, origin, removed_gui_position)
end

local function add_subfactory(player, _, event)
    local prefer_product_picker = util.globals.settings(player).prefer_product_picker
    local function xor(a, b) return not a ~= not b end  -- fancy, first time I ever needed this

    if xor(event.shift, prefer_product_picker) then  -- go right to the item picker with automatic subfactory naming
        util.raise.open_dialog(player, {dialog="picker", modal_data={item_id=nil, item_category="product",
            create_subfactory=true}})

    else  -- otherwise, have the user pick a subfactory name first
        util.raise.open_dialog(player, {dialog="subfactory", modal_data={subfactory_id=nil}})
    end
end

local function duplicate_subfactory(player, _, _)
    local player_table = util.globals.player_table(player)
    local context = player_table.ui_state.context
    local archive_open = player_table.ui_state.flags.archive_open
    local factory = player_table.factory

    local clone = Subfactory.clone(context.subfactory)
    local inserted_clone = nil
    if archive_open then
        inserted_clone = Factory.add(factory, clone)
        toggle_archive(player, _, _)
    else
        inserted_clone = Factory.insert_at(factory, context.subfactory.gui_position+1, clone)
    end

    util.context.set_subfactory(player, inserted_clone)
    solver.update(player, inserted_clone)
    util.raise.refresh(player, "all", nil)
end


local function handle_move_subfactory_click(player, tags, event)
    local context = util.globals.context(player)
    local subfactory = Factory.get(context.factory, "Subfactory", tags.subfactory_id)

    local spots_to_shift = (event.control) and 5 or ((not event.shift) and 1 or nil)
    local translated_direction = (tags.direction == "up") and "negative" or "positive"
    Factory.shift(context.factory, subfactory, 1, translated_direction, spots_to_shift)

    util.raise.refresh(player, "subfactory_list", nil)
end

local function handle_subfactory_click(player, tags, action)
    local ui_state = util.globals.ui_state(player)
    local previous_subfactory = ui_state.context.subfactory

    local selected_subfactory = Factory.get(ui_state.context.factory, "Subfactory", tags.subfactory_id)
    util.context.set_subfactory(player, selected_subfactory)

    if action == "select" then
        if ui_state.flags.recalculate_on_subfactory_change then
            -- This flag is set when a textfield is changed but not confirmed
            ui_state.flags.recalculate_on_subfactory_change = false
            solver.update(player, previous_subfactory)
        end
        util.raise.refresh(player, "all", nil)

    elseif action == "edit" then
        util.raise.refresh(player, "all", nil)  -- refresh to update the selected subfactory
        util.raise.open_dialog(player, {dialog="subfactory",
            modal_data={subfactory_id=selected_subfactory.id}})

    elseif action == "delete" then
        subfactory_list.delete_subfactory(player)
    end
end


local function refresh_subfactory_list(player)
    local player_table = util.globals.player_table(player)
    local flags, context = player_table.ui_state.flags, player_table.ui_state.context

    local main_elements = player_table.ui_state.main_elements
    if main_elements.main_frame == nil then return end

    local selected_subfactory = context.subfactory
    local subfactory_list_elements = main_elements.subfactory_list
    local listbox = subfactory_list_elements.subfactory_listbox
    listbox.clear()

    if selected_subfactory ~= nil then  -- only need to run this if any subfactory exists
        local attach_subfactory_products = player_table.preferences.attach_subfactory_products

        local subfactory_count = Factory.count(context.factory, "Subfactory")
        local tutorial_tt = (player_table.preferences.tutorial_mode)
            and data_util.generate_tutorial_tooltip("act_on_subfactory", nil, player) or nil

        for _, subfactory in pairs(Factory.get_in_order(context.factory, "Subfactory")) do
            local selected = (selected_subfactory.id == subfactory.id)
            local caption, info_tooltip = Subfactory.tostring(subfactory, attach_subfactory_products, false)
            local padded_caption = {"", "           ", caption}
            local tooltip = {"", info_tooltip, tutorial_tt}

            -- Pretty sure this needs the 'using-spaces-to-shift-the-label'-hack, padding doesn't work
            local subfactory_button = listbox.add{type="button", caption=padded_caption, tooltip=tooltip,
                tags={mod="fp", on_gui_click="act_on_subfactory", subfactory_id=subfactory.id},
                style="fp_button_fake_listbox_item", toggled=selected, mouse_button_filter={"left-and-right"}}

            local function create_move_button(flow, direction)
                local enabled = (direction == "up" and subfactory.gui_position ~= 1)
                    or (direction == "down" and subfactory.gui_position < subfactory_count)
                local endpoint = (direction == "up") and {"fp.top"} or {"fp.bottom"}
                local move_tooltip = (enabled) and {"fp.move_row_tt", {"fp.pl_subfactory", 1}, {"fp." .. direction}, endpoint} or ""

                flow.add{type="sprite-button", style="fp_button_move_row", sprite="fp_sprite_arrow_" .. direction,
                    tags={mod="fp", on_gui_click="move_subfactory", direction=direction, subfactory_id=subfactory.id},
                    tooltip=move_tooltip, enabled=enabled, mouse_button_filter={"left"}}
            end

            local move_flow = subfactory_button.add{type="flow", direction="horizontal"}
            move_flow.style.top_padding = 3
            move_flow.style.horizontal_spacing = 0
            create_move_button(move_flow, "up")
            create_move_button(move_flow, "down")
        end
    end

    -- Set all the button states and styles appropriately
    local subfactory_exists = (selected_subfactory ~= nil)
    local archive_open = (flags.archive_open)

    local archived_subfactory_count = Factory.count(player_table.archive, "Subfactory")
    subfactory_list_elements.toggle_archive_button.enabled = (archived_subfactory_count > 0)
    subfactory_list_elements.toggle_archive_button.style = (archive_open)
        and "flib_selected_tool_button" or "tool_button"

    if not archive_open then
        local subfactory_plural = {"fp.pl_subfactory", archived_subfactory_count}
        local archive_tooltip = {"fp.action_open_archive_tt", (archived_subfactory_count > 0)
            and {"fp.archive_filled", archived_subfactory_count, subfactory_plural} or {"fp.archive_empty"}}
        subfactory_list_elements.toggle_archive_button.tooltip = archive_tooltip
    else
        subfactory_list_elements.toggle_archive_button.tooltip = {"fp.action_close_archive_tt"}
    end

    subfactory_list_elements.archive_button.enabled = (subfactory_exists)
    subfactory_list_elements.archive_button.sprite = (archive_open)
        and "utility/export_slot" or "utility/import_slot"
    subfactory_list_elements.archive_button.tooltip = (archive_open)
        and {"fp.action_unarchive_subfactory"} or {"fp.action_archive_subfactory"}

    subfactory_list_elements.import_button.enabled = (not archive_open)
    subfactory_list_elements.export_button.enabled = (subfactory_exists)

    local prefer_product_picker = util.globals.settings(player).prefer_product_picker
    subfactory_list_elements.add_button.enabled = (not archive_open)
    subfactory_list_elements.add_button.tooltip = (prefer_product_picker)
        and {"fp.action_add_subfactory_by_product"} or {"fp.action_add_subfactory_by_name"}

    subfactory_list_elements.edit_button.enabled = (subfactory_exists)
    subfactory_list_elements.duplicate_button.enabled = (selected_subfactory ~= nil and selected_subfactory.valid)

    subfactory_list_elements.delete_button.enabled = (subfactory_exists)
    local delay_in_minutes = math.floor(MAGIC_NUMBERS.subfactory_deletion_delay / 3600)
    subfactory_list_elements.delete_button.tooltip = (archive_open)
        and {"fp.action_delete_subfactory"} or {"fp.action_trash_subfactory", delay_in_minutes}
end

local function build_subfactory_list(player)
    local main_elements = util.globals.main_elements(player)
    main_elements.subfactory_list = {}

    local parent_flow = main_elements.flows.left_vertical
    local frame_vertical = parent_flow.add{type="frame", direction="vertical", style="inside_deep_frame"}
    local row_count = util.globals.settings(player).subfactory_list_rows
    frame_vertical.style.height = MAGIC_NUMBERS.subheader_height + (row_count * MAGIC_NUMBERS.list_element_height)

    local subheader = frame_vertical.add{type="frame", direction="horizontal", style="subheader_frame"}

    local button_toggle_archive = subheader.add{type="sprite-button", tags={mod="fp", on_gui_click="toggle_archive"},
        sprite="fp_sprite_archive_dark", mouse_button_filter={"left"}}
    main_elements.subfactory_list["toggle_archive_button"] = button_toggle_archive

    local button_archive = subheader.add{type="sprite-button", tags={mod="fp", on_gui_click="archive_subfactory"},
        style="tool_button", mouse_button_filter={"left"}}
    main_elements.subfactory_list["archive_button"] = button_archive

    subheader.add{type="empty-widget", style="flib_horizontal_pusher"}

    local button_import = subheader.add{type="sprite-button", sprite="utility/import",
        tooltip={"fp.action_import_subfactory"}, style="tool_button", mouse_button_filter={"left"},
        tags={mod="fp", on_gui_click="subfactory_list_open_dialog", type="import"}}
    main_elements.subfactory_list["import_button"] = button_import

    local button_export = subheader.add{type="sprite-button", sprite="utility/export",
        tooltip={"fp.action_export_subfactory"}, style="tool_button", mouse_button_filter={"left"},
        tags={mod="fp", on_gui_click="subfactory_list_open_dialog", type="export"}}
    main_elements.subfactory_list["export_button"] = button_export

    subheader.add{type="empty-widget", style="flib_horizontal_pusher"}

    local button_add = subheader.add{type="sprite-button", tags={mod="fp", on_gui_click="add_subfactory"},
        sprite="utility/add", style="flib_tool_button_light_green", mouse_button_filter={"left"}}
    main_elements.subfactory_list["add_button"] = button_add

    local button_edit = subheader.add{type="sprite-button", tags={mod="fp", on_gui_click="edit_subfactory"},
        sprite="utility/rename_icon_normal", tooltip={"fp.action_edit_subfactory"}, style="tool_button",
        mouse_button_filter={"left"}}
    main_elements.subfactory_list["edit_button"] = button_edit

    local button_duplicate = subheader.add{type="sprite-button", tags={mod="fp", on_gui_click="duplicate_subfactory"},
        sprite="utility/clone", tooltip={"fp.action_duplicate_subfactory"}, style="tool_button",
        mouse_button_filter={"left"}}
    main_elements.subfactory_list["duplicate_button"] = button_duplicate

    local button_delete = subheader.add{type="sprite-button", tags={mod="fp", on_gui_click="delete_subfactory"},
        sprite="utility/trash", style="tool_button_red", mouse_button_filter={"left"}}
    main_elements.subfactory_list["delete_button"] = button_delete

    -- This is not really a list-box, but it imitates one and allows additional features
    local listbox_subfactories = frame_vertical.add{type="scroll-pane", style="fp_scroll-pane_fake_listbox"}
    listbox_subfactories.style.width = MAGIC_NUMBERS.list_width
    main_elements.subfactory_list["subfactory_listbox"] = listbox_subfactories

    refresh_subfactory_list(player)
end


-- ** TOP LEVEL **
subfactory_list = {}

-- Utility function to centralize subfactory creation behavior
function subfactory_list.add_subfactory(player, name)
    local subfactory = Subfactory.init(name)

    local settings = util.globals.settings(player)
    subfactory.timescale = settings.default_timescale
    if settings.prefer_matrix_solver then subfactory.matrix_free_items = {} end

    local context = util.globals.context(player)
    Factory.add(context.factory, subfactory)
    util.context.set_subfactory(player, subfactory)

    return subfactory
end

-- Utility function to centralize subfactory deletion behavior
function subfactory_list.delete_subfactory(player)
    local ui_state = util.globals.ui_state(player)
    local subfactory = ui_state.context.subfactory
    if subfactory == nil then return end  -- prevent crashes due to multiplayer latency

    if ui_state.flags.archive_open then
        if subfactory.tick_of_deletion then data_util.nth_tick.remove(subfactory.tick_of_deletion) end

        local factory = ui_state.context.factory
        local removed_gui_position = Factory.remove(factory, subfactory)
        refresh_after_subfactory_deletion(player, factory, removed_gui_position)
    else
        local desired_tick_of_deletion = game.tick + MAGIC_NUMBERS.subfactory_deletion_delay
        local actual_tick_of_deletion = data_util.nth_tick.add(desired_tick_of_deletion,
            "delete_subfactory_for_good", {player_index=player.index, subfactory=subfactory})
        subfactory.tick_of_deletion = actual_tick_of_deletion

        archive_subfactory(player)
    end
end


-- ** EVENTS **
local listeners = {}

listeners.gui = {
    on_gui_click = {
        {
            name = "toggle_archive",
            handler = toggle_archive
        },
        {
            name = "archive_subfactory",
            handler = archive_subfactory
        },
        {  -- import/export buttons
            name = "subfactory_list_open_dialog",
            handler = (function(player, tags, _)
                util.raise.open_dialog(player, {dialog=tags.type})
            end)
        },
        {
            name = "add_subfactory",
            handler = add_subfactory
        },
        {
            name = "edit_subfactory",
            handler = (function(player, _, _)
                local subfactory = util.globals.context(player).subfactory
                util.raise.open_dialog(player, {dialog="subfactory",
                    modal_data={subfactory_id=subfactory.id}})
            end)
        },
        {
            name = "duplicate_subfactory",
            handler = duplicate_subfactory
        },
        {
            name = "delete_subfactory",
            handler = subfactory_list.delete_subfactory
        },
        {
            name = "move_subfactory",
            handler = handle_move_subfactory_click
        },
        {
            name = "act_on_subfactory",
            modifier_actions = {
                select = {"left"},
                edit = {"right"},
                delete = {"control-right"}
            },
            handler = handle_subfactory_click
        }
    }
}

listeners.misc = {
    build_gui_element = (function(player, event)
        if event.trigger == "main_dialog" then
            build_subfactory_list(player)
        end
    end),
    refresh_gui_element = (function(player, event)
        local triggers = {subfactory_list=true, all=true}
        if triggers[event.trigger] then refresh_subfactory_list(player) end
    end)
}

listeners.global = {
    delete_subfactory_for_good = delete_subfactory_for_good
}

return { listeners }
