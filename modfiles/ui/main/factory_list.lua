local Factory = require("backend.data.Factory")

-- Delete factory for good and refresh interface if necessary
local function delete_factory_for_good(metadata)
    local player = game.get_player(metadata.player_index)  ---@cast player -nil
    local factory = OBJECT_INDEX[metadata.factory_id]  --[[@as Factory]]
    local adjacent_factory = util.context.remove(player, factory)

    local selected_factory = util.context.get(player, "Factory")  --[[@as Factory?]]
    if selected_factory and selected_factory.id == factory.id then
        util.context.set(player, adjacent_factory or factory.parent)
    end
    factory.parent:remove(factory)

    if not main_dialog.is_in_focus(player) then return end
    -- Refresh all if the archive is currently open
    if selected_factory and selected_factory.archived == true then
        util.raise.refresh(player, "all")
    else  -- only need to refresh the archive button enabled state really
        util.raise.refresh(player, "factory_list")
    end
end


local function change_factory_archived(player, to_archive)
    local factory = util.context.get(player, "Factory")  --[[@as Factory]]

    if to_archive or factory.parent:count({archived=true}) > 1 then
        local adjacent_factory = util.context.remove(player, factory)
        util.context.set(player, adjacent_factory or factory.parent, true)
    end  -- if it's pulling the last factory from the archive, keep the context on it

    factory.archived = to_archive
    factory.parent:shift(factory, "next", nil)  -- shift to end
    factory.parent.needs_refresh = true

    -- Reset deletion if a deleted factory is un-archived
    if not to_archive and factory.tick_of_deletion then
        util.nth_tick.cancel(factory.tick_of_deletion)
        factory.tick_of_deletion = nil
    end

    util.raise.refresh(player, "all")
end

local function add_factory(player, _, event)
    local skip_factory_naming = util.globals.preferences(player).skip_factory_naming

    if util.xor(event.shift, skip_factory_naming) then  -- go right to the item picker with automatic factory naming
        util.raise.open_dialog(player, {dialog="picker", modal_data={item_id=nil, item_category="product",
            create_factory=true}})
    else  -- otherwise, have the user pick a factory name first
        util.raise.open_dialog(player, {dialog="factory", modal_data={factory_id=nil}})
    end
end

local function duplicate_factory(player, _, event)
    local factory = util.context.get(player, "Factory")  --[[@as Factory]]
    local clone = factory:clone()
    clone.archived = false  -- always clone as unarchived
    local pivot = (event.shift and not factory.archived) and factory or nil
    factory.parent:insert(clone, pivot, "next")

    solver.update(player, clone)
    main_dialog.toggle_districts_view(player, true)
    util.context.set(player, clone)
    util.raise.refresh(player, "all")
end


local function handle_move_factory_click(player, tags, event)
    local factory = OBJECT_INDEX[tags.factory_id]  --[[@as Factory]]
    local spots_to_shift = (event.control) and 5 or ((not event.shift) and 1 or nil)
    factory.parent:shift(factory, tags.direction, spots_to_shift)

    util.raise.refresh(player, "factory_list")
end

local function handle_factory_click(player, tags, action)
    local selected_factory = OBJECT_INDEX[tags.factory_id]  --[[@as Factory]]

    if action == "select" then
        local ui_state = util.globals.ui_state(player)
        if ui_state.recalculate_on_factory_change then
            -- This flag is set when a textfield is changed but not confirmed
            ui_state.recalculate_on_factory_change = false
            local previous_factory = util.context.get(player, "Factory")
            solver.update(player, previous_factory)
        end

        main_dialog.toggle_districts_view(player, true)
        util.context.set(player, selected_factory)
        util.raise.refresh(player, "all")  -- refresh to update the selected factory

    elseif action == "edit" then
        util.context.set(player, selected_factory)
        util.raise.refresh(player, "all")  -- refresh to update the selected factory

        util.raise.open_dialog(player, {dialog="factory", modal_data={factory_id=selected_factory.id}})

    elseif action == "delete" then
        util.context.set(player, selected_factory)
        factory_list.delete_factory(player)
    end
end


local function refresh_factory_list(player)
    local player_table = util.globals.player_table(player)
    local tooltips = player_table.ui_state.tooltips
    tooltips.factory_list = {}

    local main_elements = player_table.ui_state.main_elements
    if main_elements.main_frame == nil then return end

    local selected_factory = util.context.get(player, "Factory")  --[[@as Factory?]]
    local archived = (selected_factory) and selected_factory.archived or false

    local factory_list_elements = main_elements.factory_list
    local listbox = factory_list_elements.factory_listbox
    listbox.clear()

    if selected_factory ~= nil then  -- only need to run this if any factory exists
        local attach_factory_products = player_table.preferences.attach_factory_products
        local filter = {archived = archived}

        local function create_move_button(flow, direction, factory)
            local enabled = (factory.parent:find(filter, factory[direction], direction) ~= nil)
            local endpoint = (direction == "next") and {"fp.bottom"} or {"fp.top"}
            local up_down = (direction == "next") and "down" or "up"
            local move_tooltip = (enabled) and {"", {"fp.move_object", {"fp.pl_factory", 1}, {"fp." .. up_down}},
                {"fp.move_object_instructions", endpoint}} or ""

            local move_button = flow.add{type="sprite-button", enabled=enabled, sprite="fp_arrow_" .. up_down,
                tags={mod="fp", on_gui_click="move_factory", direction=direction, factory_id=factory.id,
                on_gui_hover="set_tooltip", context="factory_list"}, mouse_button_filter={"left"},
                raise_hover_events=true, style="fp_sprite-button_move"}
            move_button.style.size = {20, 12}
            move_button.style.padding = -2
            tooltips.factory_list[move_button.index] = move_tooltip
        end

        for factory in selected_factory.parent:iterator(filter) do
            local selected = (selected_factory.id == factory.id)
            local caption, info_tooltip = factory:tostring(attach_factory_products, false)
            local tooltip = {"", info_tooltip, "\n", MODIFIER_ACTIONS["act_on_factory"].tooltip}

            local button_flow = listbox.add{type="flow", direction="horizontal"}
            button_flow.style.horizontal_spacing = 0

            local move_flow = button_flow.add{type="flow", direction="vertical"}
            move_flow.style.vertical_spacing = 0
            move_flow.style.padding = {2, 0}
            create_move_button(move_flow, "previous", factory)
            create_move_button(move_flow, "next", factory)

            local factory_button = button_flow.add{type="button", caption=caption, toggled=selected,
                tags={mod="fp", on_gui_click="act_on_factory", factory_id=factory.id, on_gui_hover="set_tooltip",
                context="factory_list"}, style="list_box_item", mouse_button_filter={"left-and-right"},
                raise_hover_events=true}
            factory_button.style.padding = {0, 12, 0, 4}
            factory_button.style.width = MAGIC_NUMBERS.list_width - 20
            tooltips.factory_list[factory_button.index] = tooltip
        end
    end

    -- Set all the button states and styles appropriately
    local factory_exists = (selected_factory ~= nil)
    local district = util.context.get(player, "District")  --[[@as District]]
    local archived_factory_count = district:count({archived=true})

    factory_list_elements.toggle_archive_button.enabled = (archived_factory_count > 0)
    factory_list_elements.toggle_archive_button.style = (archived)
        and "flib_selected_tool_button" or "tool_button"

    if not archived then
        local factory_plural = {"fp.pl_factory", archived_factory_count}
        local archive_tooltip = {"fp.action_open_archive_tt", (archived_factory_count > 0)
            and {"fp.archive_filled", archived_factory_count, factory_plural} or {"fp.archive_empty"}}
        factory_list_elements.toggle_archive_button.tooltip = archive_tooltip
    else
        factory_list_elements.toggle_archive_button.tooltip = {"fp.action_close_archive_tt"}
    end

    factory_list_elements.archive_button.enabled = (factory_exists)
    factory_list_elements.archive_button.sprite = (archived)
        and "utility/export_slot" or "utility/import_slot"
    factory_list_elements.archive_button.tooltip = (archived)
        and {"fp.action_unarchive_factory"} or {"fp.action_archive_factory"}

    factory_list_elements.import_button.enabled = (not archived)
    factory_list_elements.export_button.enabled = (factory_exists)

    local skip_factory_naming = util.globals.preferences(player).skip_factory_naming
    factory_list_elements.add_button.enabled = (not archived)
    factory_list_elements.add_button.tooltip = (skip_factory_naming)
        and {"fp.action_add_factory_by_product"} or {"fp.action_add_factory_by_name"}

    factory_list_elements.edit_button.enabled = (factory_exists)
    factory_list_elements.duplicate_button.enabled = (selected_factory ~= nil and selected_factory.valid)

    factory_list_elements.delete_button.enabled = (factory_exists)
    local delay_in_minutes = math.floor(MAGIC_NUMBERS.factory_deletion_delay / 3600)
    factory_list_elements.delete_button.tooltip = (archived)
        and {"fp.action_delete_factory"} or {"fp.action_trash_factory", delay_in_minutes}
end

local function build_factory_list(player)
    local main_elements = util.globals.main_elements(player)
    main_elements.factory_list = {}

    local parent_flow = main_elements.flows.left_vertical
    local frame_vertical = parent_flow.add{type="frame", direction="vertical", style="inside_deep_frame"}
    local row_count = util.globals.preferences(player).factory_list_rows
    frame_vertical.style.height = MAGIC_NUMBERS.subheader_height + (row_count * MAGIC_NUMBERS.list_element_height)

    local subheader = frame_vertical.add{type="frame", direction="horizontal", style="subheader_frame"}

    local button_toggle_archive = subheader.add{type="sprite-button", tags={mod="fp", on_gui_click="toggle_archive"},
        sprite="fp_archive", mouse_button_filter={"left"}}
    main_elements.factory_list["toggle_archive_button"] = button_toggle_archive

    local button_archive = subheader.add{type="sprite-button", tags={mod="fp", on_gui_click="archive_factory"},
        style="tool_button", mouse_button_filter={"left"}}
    main_elements.factory_list["archive_button"] = button_archive

    subheader.add{type="empty-widget", style="flib_horizontal_pusher"}

    local button_import = subheader.add{type="sprite-button", sprite="utility/import",
        tooltip={"fp.action_import_factory"}, style="tool_button", mouse_button_filter={"left"},
        tags={mod="fp", on_gui_click="factory_list_open_dialog", type="import"}}
    main_elements.factory_list["import_button"] = button_import

    local button_export = subheader.add{type="sprite-button", sprite="utility/export",
        tooltip={"fp.action_export_factory"}, style="tool_button", mouse_button_filter={"left"},
        tags={mod="fp", on_gui_click="factory_list_open_dialog", type="export"}}
    main_elements.factory_list["export_button"] = button_export

    subheader.add{type="empty-widget", style="flib_horizontal_pusher"}

    local button_add = subheader.add{type="sprite-button", tags={mod="fp", on_gui_click="add_factory"},
        sprite="utility/add", style="flib_tool_button_light_green", mouse_button_filter={"left"}}
    button_add.style.padding = 1
    main_elements.factory_list["add_button"] = button_add

    local button_edit = subheader.add{type="sprite-button", tags={mod="fp", on_gui_click="edit_factory"},
        sprite="utility/rename_icon", tooltip={"fp.action_edit_factory"}, style="tool_button",
        mouse_button_filter={"left"}}
    main_elements.factory_list["edit_button"] = button_edit

    local button_duplicate = subheader.add{type="sprite-button", tags={mod="fp", on_gui_click="duplicate_factory"},
        sprite="utility/clone", tooltip={"fp.action_duplicate_factory"}, style="tool_button",
        mouse_button_filter={"left"}}
    main_elements.factory_list["duplicate_button"] = button_duplicate

    local button_delete = subheader.add{type="sprite-button", tags={mod="fp", on_gui_click="delete_factory"},
        sprite="utility/trash", style="tool_button_red", mouse_button_filter={"left"}}
    main_elements.factory_list["delete_button"] = button_delete

    -- This is not really a list-box, but it imitates one and allows additional features
    local listbox_factories = frame_vertical.add{type="scroll-pane", style="list_box_under_subheader_scroll_pane"}
    listbox_factories.style.vertically_stretchable = true
    listbox_factories.style.extra_right_padding_when_activated = -12
    local flow_factories = listbox_factories.add{type="flow", direction="vertical"}
    flow_factories.style.vertical_spacing = 0
    main_elements.factory_list["factory_listbox"] = flow_factories

    refresh_factory_list(player)
end


-- ** TOP LEVEL **
factory_list = {}  -- try to move elsewhere or smth to get rid of global variable

-- Utility function to centralize factory creation behavior
function factory_list.add_factory(player, name)
    local preferences = util.globals.preferences(player)
    local factory = Factory.init(name)
    if preferences.prefer_matrix_solver then factory.matrix_free_items = {} end

    local district = util.context.get(player, "District")  --[[@as District]]
    district:insert(factory)

    util.context.set(player, factory)

    return factory
end

-- Utility function to centralize factory deletion behavior
function factory_list.delete_factory(player)
    local factory = util.context.get(player, "Factory")  --[[@as Factory]]
    if not factory then return end  -- latency protection

    if factory.archived then
        local adjacent_factory = util.context.remove(player, factory)
        local district = factory.parent
        factory.parent:remove(factory)

        util.context.set(player, adjacent_factory or district)
        util.raise.refresh(player, "all")
    else
        local desired_tick_of_deletion = game.tick + MAGIC_NUMBERS.factory_deletion_delay
        local actual_tick_of_deletion = util.nth_tick.register(desired_tick_of_deletion,
            "delete_factory_for_good", {player_index=player.index, factory_id=factory.id})
        factory.tick_of_deletion = actual_tick_of_deletion

        change_factory_archived(player, true)
    end
end


local listeners = {}

listeners.gui = {
    on_gui_click = {
        {
            name = "toggle_archive",
            handler = (function(player, _, _)
                local factory = util.context.get(player, "Factory")  --[[@as Factory]]
                local archive_open = (factory) and factory.archived or false
                local district = (factory) and factory.parent or util.context.get(player, "District")
                local new_factory = district:find({archived=not archive_open})  --[[@as Factory]]

                main_dialog.toggle_districts_view(player, true)
                util.context.set(player, new_factory or district, true)
                util.raise.refresh(player, "all")
            end)
        },
        {
            name = "archive_factory",
            timeout = 10,
            handler = (function(player, _, _)
                local factory = util.context.get(player, "Factory")  --[[@as Factory]]
                change_factory_archived(player, (not factory.archived))
            end)
        },
        {  -- import/export buttons
            name = "factory_list_open_dialog",
            handler = (function(player, tags, _)
                util.raise.open_dialog(player, {dialog=tags.type})
            end)
        },
        {
            name = "add_factory",
            handler = add_factory
        },
        {
            name = "edit_factory",
            handler = (function(player, _, _)
                local factory = util.context.get(player, "Factory")  --[[@as Factory]]
                util.raise.open_dialog(player, {dialog="factory", modal_data={factory_id=factory.id}})
            end)
        },
        {
            name = "duplicate_factory",
            handler = duplicate_factory
        },
        {
            name = "delete_factory",
            timeout = 10,
            handler = factory_list.delete_factory
        },
        {
            name = "move_factory",
            timeout = 10,
            handler = handle_move_factory_click
        },
        {
            name = "act_on_factory",
            actions_table = {
                select = {shortcut="left", limitations={}},
                edit = {shortcut="control-left"},
                delete = {shortcut="control-right"}
            },
            handler = handle_factory_click
        }
    }
}

listeners.misc = {
    build_gui_element = (function(player, event)
        if event.trigger == "main_dialog" then
            build_factory_list(player)
        end
    end),
    refresh_gui_element = (function(player, event)
        local triggers = {factory_list=true, all=true}
        if triggers[event.trigger] then refresh_factory_list(player) end
    end)
}

listeners.global = {
    delete_factory_for_good = delete_factory_for_good
}

return { listeners }
