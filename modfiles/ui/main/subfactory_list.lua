local Factory = require("backend.data.Factory")

-- Delete subfactory for good and refresh interface if necessary
local function delete_subfactory_for_good(metadata)
    local player = game.get_player(metadata.player_index)  ---@cast player -nil
    util.context.remove(player, metadata.subfactory)

    local selected_subfactory = util.context.get(player, "Factory")  --[[@as Factory?]]
    if selected_subfactory and selected_subfactory.id == metadata.subfactory.id then
        util.context.set_adjacent(player, selected_subfactory)
    end
    metadata.subfactory.parent:remove(metadata.subfactory)

    if not main_dialog.is_in_focus(player) then return end

    -- Refresh all if the archive is currently open
    if selected_subfactory and selected_subfactory.archived == true then
        util.raise.refresh(player, "all", nil)
    else  -- only need to refresh the archive button enabled state really
        util.raise.refresh(player, "subfactory_list", nil)
    end
end


local function change_subfactory_archived(player, archived)
    local subfactory = util.context.get(player, "Factory")  --[[@as Factory]]
    subfactory.archived = archived

    util.context.remove(player, subfactory)  -- clear 'main' cache
    util.context.set_adjacent(player, subfactory, (not archived))
    subfactory.parent:shift(subfactory, "next", nil)  -- shift to end

    -- Reset deletion if a deleted subfactory is un-archived
    if archived == false and subfactory.tick_of_deletion then
        util.nth_tick.cancel(subfactory.tick_of_deletion)
        subfactory.tick_of_deletion = nil
    end

    util.raise.refresh(player, "all", nil)
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
    local subfactory = util.context.get(player, "Factory")  --[[@as Factory]]
    local clone = subfactory:clone()
    clone.archived = false  -- always clone as unarchived
    subfactory.parent:insert(clone)

    solver.update(player, clone)
    util.context.set(player, clone)

    util.raise.refresh(player, "all", nil)
end


local function handle_move_subfactory_click(player, tags, event)
    local subfactory = OBJECT_INDEX[tags.subfactory_id]  --[[@as Factory]]
    local spots_to_shift = (event.control) and 5 or ((not event.shift) and 1 or nil)
    subfactory.parent:shift(subfactory, tags.direction, spots_to_shift)

    util.raise.refresh(player, "subfactory_list", nil)
end

local function handle_subfactory_click(player, tags, action)
    local selected_subfactory = OBJECT_INDEX[tags.subfactory_id]  --[[@as Factory]]

    if action == "select" then
        local flags = util.globals.flags(player)
        if flags.recalculate_on_subfactory_change then
            -- This flag is set when a textfield is changed but not confirmed
            flags.recalculate_on_subfactory_change = false
            local previous_subfactory = util.context.get(player, "Factory")
            solver.update(player, previous_subfactory)
        end
        util.context.set(player, selected_subfactory)
        util.raise.refresh(player, "all", nil)

    elseif action == "edit" then
        util.raise.refresh(player, "all", nil)  -- refresh to update the selected subfactory
        util.raise.open_dialog(player, {dialog="subfactory", modal_data={subfactory_id=selected_subfactory.id}})

    elseif action == "delete" then
        subfactory_list.delete_subfactory(player)
    end
end


local function refresh_subfactory_list(player)
    local player_table = util.globals.player_table(player)

    local main_elements = player_table.ui_state.main_elements
    if main_elements.main_frame == nil then return end

    local selected_subfactory = util.context.get(player, "Factory")  --[[@as Factory?]]
    local archived = (selected_subfactory) and selected_subfactory.archived or false

    local subfactory_list_elements = main_elements.subfactory_list
    local listbox = subfactory_list_elements.subfactory_listbox
    listbox.clear()

    if selected_subfactory ~= nil then  -- only need to run this if any subfactory exists
        local attach_subfactory_products = player_table.preferences.attach_subfactory_products
        local filter = {archived = archived}
        local tutorial_tt = (player_table.preferences.tutorial_mode)
            and util.actions.tutorial_tooltip("act_on_subfactory", nil, player) or nil

        for subfactory in selected_subfactory.parent:iterator(filter) do
            local selected = (selected_subfactory.id == subfactory.id)
            local caption, info_tooltip = subfactory:tostring(attach_subfactory_products, false)
            local padded_caption = {"", "           ", caption}
            local tooltip = {"", info_tooltip, tutorial_tt}

            -- Pretty sure this needs the 'using-spaces-to-shift-the-label'-hack, padding doesn't work
            local subfactory_button = listbox.add{type="button", caption=padded_caption, tooltip=tooltip,
                tags={mod="fp", on_gui_click="act_on_subfactory", subfactory_id=subfactory.id},
                style="fp_button_fake_listbox_item", toggled=selected, mouse_button_filter={"left-and-right"}}

            local function create_move_button(flow, direction)
                local enabled = (subfactory.parent:find(filter, subfactory[direction], direction) ~= nil)
                local endpoint = (direction == "next") and {"fp.bottom"} or {"fp.top"}
                local up_down = (direction == "next") and "down" or "up"
                local move_tooltip = (enabled) and {"fp.move_row_tt", {"fp.pl_subfactory", 1},
                    {"fp." .. up_down}, endpoint} or ""

                flow.add{type="sprite-button", style="fp_button_move_row", sprite="fp_sprite_arrow_" .. up_down,
                    tags={mod="fp", on_gui_click="move_subfactory", direction=direction, subfactory_id=subfactory.id},
                    tooltip=move_tooltip, enabled=enabled, mouse_button_filter={"left"}}
            end

            local move_flow = subfactory_button.add{type="flow", direction="horizontal"}
            move_flow.style.top_padding = 3
            move_flow.style.horizontal_spacing = 0
            create_move_button(move_flow, "previous")
            create_move_button(move_flow, "next")
        end
    end

    -- Set all the button states and styles appropriately
    local subfactory_exists = (selected_subfactory ~= nil)
    local district = util.context.get(player, "District")  --[[@as District]]
    local archived_subfactory_count = district:count{archived=true}

    subfactory_list_elements.toggle_archive_button.enabled = (archived_subfactory_count > 0)
    subfactory_list_elements.toggle_archive_button.style = (archived)
        and "flib_selected_tool_button" or "tool_button"

    if not archived then
        local subfactory_plural = {"fp.pl_subfactory", archived_subfactory_count}
        local archive_tooltip = {"fp.action_open_archive_tt", (archived_subfactory_count > 0)
            and {"fp.archive_filled", archived_subfactory_count, subfactory_plural} or {"fp.archive_empty"}}
        subfactory_list_elements.toggle_archive_button.tooltip = archive_tooltip
    else
        subfactory_list_elements.toggle_archive_button.tooltip = {"fp.action_close_archive_tt"}
    end

    subfactory_list_elements.archive_button.enabled = (subfactory_exists)
    subfactory_list_elements.archive_button.sprite = (archived)
        and "utility/export_slot" or "utility/import_slot"
    subfactory_list_elements.archive_button.tooltip = (archived)
        and {"fp.action_unarchive_subfactory"} or {"fp.action_archive_subfactory"}

    subfactory_list_elements.import_button.enabled = (not archived)
    subfactory_list_elements.export_button.enabled = (subfactory_exists)

    local prefer_product_picker = util.globals.settings(player).prefer_product_picker
    subfactory_list_elements.add_button.enabled = (not archived)
    subfactory_list_elements.add_button.tooltip = (prefer_product_picker)
        and {"fp.action_add_subfactory_by_product"} or {"fp.action_add_subfactory_by_name"}

    subfactory_list_elements.edit_button.enabled = (subfactory_exists)
    subfactory_list_elements.duplicate_button.enabled = (selected_subfactory ~= nil and selected_subfactory.valid)

    subfactory_list_elements.delete_button.enabled = (subfactory_exists)
    local delay_in_minutes = math.floor(MAGIC_NUMBERS.subfactory_deletion_delay / 3600)
    subfactory_list_elements.delete_button.tooltip = (archived)
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
subfactory_list = {}  -- TODO try to move elsewhere or smth to get rid of global variable

-- Utility function to centralize subfactory creation behavior
function subfactory_list.add_subfactory(player, name)
    local settings = util.globals.settings(player)
    local subfactory = Factory.init(name, settings.default_timescale)
    if settings.prefer_matrix_solver then subfactory.matrix_free_items = {} end

    local district = util.context.get(player, "District")  --[[@as District]]
    district:insert(subfactory)
    util.context.set(player, subfactory)

    return subfactory
end

-- Utility function to centralize subfactory deletion behavior
function subfactory_list.delete_subfactory(player)
    local subfactory = util.context.get(player, "Factory")  --[[@as Factory]]

    if subfactory.archived then
        if subfactory.tick_of_deletion then util.nth_tick.cancel(subfactory.tick_of_deletion) end

        util.context.remove(player, subfactory)
        util.context.set_adjacent(player, subfactory)
        subfactory.parent:remove(subfactory)

        util.raise.refresh(player, "all", nil)
    else
        local desired_tick_of_deletion = game.tick + MAGIC_NUMBERS.subfactory_deletion_delay
        local actual_tick_of_deletion = util.nth_tick.register(desired_tick_of_deletion,
            "delete_subfactory_for_good", {player_index=player.index, subfactory=subfactory})
        subfactory.tick_of_deletion = actual_tick_of_deletion

        change_subfactory_archived(player, true)
    end
end


local listeners = {}

listeners.gui = {
    on_gui_click = {
        {  -- can't be pressed without archived factories
            name = "toggle_archive",
            handler = (function(player, _, _)
                local archive = true
                local factory = util.context.get(player, "Factory")  --[[@as Factory?]]
                if factory ~= nil then archive = (not factory.archived) end
                util.context.set_default(player, archive)
                util.raise.refresh(player, "all", nil)
            end)
        },
        {
            name = "archive_subfactory",
            handler = (function(player, _, _)
                local factory = util.context.get(player, "Factory")  --[[@as Factory]]
                change_subfactory_archived(player, (not factory.archived))
            end)
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
                local subfactory = util.context.get(player, "Factory")  --[[@as Factory]]
                util.raise.open_dialog(player, {dialog="subfactory", modal_data={subfactory_id=subfactory.id}})
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
