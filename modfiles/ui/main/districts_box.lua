-- ** LOCAL UTIL **
local function save_district_name(player, tags, _)
    local main_elements = util.globals.main_elements(player)
    local district_elements = main_elements.districts_box[tags.district_id]

    local district = OBJECT_INDEX[tags.district_id]  --[[@as District]]
    district.name = district_elements.name_textfield.text
    district_elements.name_label.caption = district.name  -- saves the refresh

    district_elements.edit_flow.visible = false
    district_elements.name_flow.visible = true

    util.raise.refresh(player, "district_info")
end

local function change_district_location(player, tags, event)
    local district = OBJECT_INDEX[tags.district_id]  --[[@as District]]
    local location_proto_id = event.element.selected_index
    district.location_proto = prototyper.util.find("locations", location_proto_id, nil)  --[[@as FPLocationPrototype]]

    for factory in district:iterator() do
        factory.top_floor:reset_surface_compatibility()
        solver.update(player, factory)
    end
    util.raise.refresh(player, "all")
end


local function handle_item_button_click(player, tags, action)
    local item = OBJECT_INDEX[tags.item_id]

    if action == "copy" then  -- copy as SimpleItems makes most sense
        local copyable_item = {class="SimpleItem", proto=item.proto, amount=item.abs_diff}
        util.clipboard.copy(player, copyable_item)

    elseif action == "add_to_cursor" then
        util.cursor.handle_item_click(player, item.proto, item.abs_diff)

    elseif action == "factoriopedia" then
        local name = (item.proto.temperature) and item.proto.base_name or item.proto.name
        player.open_factoriopedia_gui(prototypes[item.proto.type][name])
    end
end


local function build_items_flow(player, parent, district)
    local items_flow = parent.add{type="flow", direction="horizontal"}
    items_flow.style.padding = {6, 12, 12, 12}

    local preferences = util.globals.preferences(player)
    local column_count = (preferences.products_per_row * 4) / 2

    local function build_item_flow(category)
        local item_flow = items_flow.add{type="flow", direction="vertical"}
        item_flow.add{type="label", caption={"fp.pu_" .. category, 2}, style="caption_label"}

        local item_frame = item_flow.add{type="frame", style="slot_button_deep_frame"}
        item_frame.style.width = column_count * MAGIC_NUMBERS.item_button_size
        item_frame.style.minimal_height = MAGIC_NUMBERS.item_button_size
        local table_items = item_frame.add{type="table", column_count=column_count, style="filter_slot_table"}

        return table_items
    end

    items_flow.add{type="empty-widget", style="flib_horizontal_pusher"}
    local prod_table = build_item_flow("product")
    items_flow.add{type="empty-widget", style="flib_horizontal_pusher"}
    items_flow.add{type="empty-widget", style="flib_horizontal_pusher"}
    local ingr_table = build_item_flow("ingredient")
    items_flow.add{type="empty-widget", style="flib_horizontal_pusher"}

    local action_tooltip = MODIFIER_ACTIONS["act_on_district_item"].tooltip
    local tooltips = util.globals.ui_state(player).tooltips

    local color_map = {
        production = {half="flib_slot_button_cyan", full="flib_slot_button_blue"},
        consumption = {half="flib_slot_button_yellow", full="flib_slot_button_red"}
    }

    for item in district.item_set:iterator() do
        local diff_string, amount_tooltip = item_views.process_item(player, item, item.abs_diff, nil)

        local total_amount = item[item.overall].amount
        local total_string, total_tooltip = item_views.process_item(player, item, total_amount, nil)

        local title_line = {"fp.tt_title", item.proto.localised_name}
        local diff_line = {"fp.item_amount_" .. item.overall, amount_tooltip}
        local total_line = {"fp.item_amount_total", total_tooltip}
        local tooltip = {"", title_line, diff_line, total_line, "\n", action_tooltip}

        local colors = color_map[item.overall]
        local style = (item.abs_diff ~= total_amount) and colors.half or colors.full

        local relevant_table = (item.overall == "production") and prod_table or ingr_table
        local button = relevant_table.add{type="sprite-button", number=diff_string, style=style,
            sprite=item.proto.sprite, tags={mod="fp", on_gui_click="act_on_district_item",
            item_id=item.id, on_gui_hover="set_tooltip", context="districts_box"},
            raise_hover_events=true, mouse_button_filter={"left-and-right"}}
        tooltips.districts_box[button.index] = tooltip
    end

    local max_count = math.max(#prod_table.children, #ingr_table.children)
    local height = math.ceil(max_count / column_count) * MAGIC_NUMBERS.item_button_size
    prod_table.style.height = height; ingr_table.style.height = height
end

local function build_district_frame(player, district, location_items)
    district:refresh()  -- refreshes its data if necessary

    local elements = util.globals.main_elements(player).districts_box
    elements[district.id] = {}

    local window_frame = elements.main_flow.add{type="frame", direction="vertical", style="inside_shallow_frame"}
    local subheader = window_frame.add{type="frame", direction="horizontal", style="subheader_frame"}
    subheader.style.top_padding = 6

    -- Interaction buttons
    local function create_move_button(flow, direction)
        local enabled = (direction == "next" and district.next ~= nil) or
            (direction == "previous" and district.previous ~= nil)
        local up_down = (direction == "next") and "down" or "up"
        local tooltip = {"", {"fp.move_object", {"fp.pl_district", 1}, {"fp." .. up_down}}}
        local move_button = flow.add{type="sprite-button", enabled=enabled, sprite="fp_arrow_" .. up_down,
            tags={mod="fp", on_gui_click="move_district", direction=direction, district_id=district.id},
            style="fp_sprite-button_move", tooltip=tooltip, mouse_button_filter={"left"}}
        move_button.style.size = {18, 14}
        move_button.style.padding = -1
    end

    local move_flow = subheader.add{type="flow", direction="vertical"}
    move_flow.style.vertical_spacing = 0
    move_flow.style.left_margin = 2
    create_move_button(move_flow, "previous")
    create_move_button(move_flow, "next")

    local selected = util.context.get(player, "District").id == district.id
    local selection_caption = (selected) and {"fp.u_selected"} or {"fp.u_select"}
    local select_button = subheader.add{type="button", caption=selection_caption, style="list_box_item",
        tags={mod="fp", on_gui_click="select_district", district_id=district.id},
        enabled=(not selected), mouse_button_filter={"left"}}
    select_button.style.font = "default-bold"
    select_button.style.width = 72
    select_button.style.padding = {0, 4}
    select_button.style.horizontal_align = "center"

    -- Name
    subheader.add{type="label", caption={"", {"fp.name"}, ": "}, style="subheader_caption_label"}

    local flow_name = subheader.add{type="flow", direction="horizontal"}
    flow_name.style.vertical_align = "center"
    elements[district.id]["name_flow"] = flow_name
    local label_name = flow_name.add{type="label", caption=district.name, style="bold_label"}
    elements[district.id]["name_label"] = label_name
    flow_name.add{type="sprite-button", style="mini_button_aligned_to_text_vertically_when_centered",
        tags={mod="fp", on_gui_click="edit_district_name", district_id=district.id}, sprite="utility/rename_icon",
        tooltip={"fp.edit_name"}, mouse_button_filter={"left"}}

    local flow_edit = subheader.add{type="flow", direction="horizontal", visible=false}
    flow_edit.style.vertical_align = "center"
    elements[district.id]["edit_flow"] = flow_edit
    local textfield_name = flow_edit.add{type="textfield", text=district.name, icon_selector=true,
        tags={mod="fp", on_gui_confirmed="confirm_district_name", district_id=district.id}}
    textfield_name.style.width = 160
    elements[district.id]["name_textfield"] = textfield_name
    flow_edit.add{type="sprite-button", style="mini_button_aligned_to_text_vertically_when_centered",
        tags={mod="fp", on_gui_click="save_district_name", district_id=district.id}, sprite="utility/rename_icon",
        tooltip={"fp.save_name"}, mouse_button_filter={"left"}}

    -- Location
    if MULTIPLE_PLANETS then
        local label_location = subheader.add{type="label", caption={"", {"fp.pu_location", 1}, ": "},
            tooltip={"fp.location_tt"}, style="subheader_caption_label"}
        label_location.style.left_margin = 8
        -- Using the location id for the index works because the location prototypes are in id order
        subheader.add{type="drop-down", items=location_items, selected_index=district.location_proto.id,
            tags={mod="fp", on_gui_selection_state_changed="change_district_location", district_id=district.id}}
    end

    -- Power & Pollution
    local label_power = subheader.add{type="label", caption=util.format.SI_value(district.power, "W", 3),
        style="bold_label", tooltip={"", {"fp.u_power"}, ": ", util.format.SI_value(district.power, "W", 5)}}
    label_power.style.left_margin = 24
    subheader.add{type="label", caption="|"}
    subheader.add{type="label", caption=util.format.SI_value(district.emissions, "E/m", 3), style="bold_label",
        tooltip=util.gui.format_emissions(district.emissions, district)}

    -- Item toggle
    subheader.add{type="empty-widget", style="flib_horizontal_pusher"}
    local sprite = (district.collapsed) and "fp_expand" or "fp_collapse"
    local items_toggle = subheader.add{type="sprite-button", sprite=sprite,
        tags={mod="fp", on_gui_click="toggle_district_items", district_id=district.id},
        style="tool_button", tooltip={"fp.toggle_district_items_tt"}, mouse_button_filter={"left"}}

    -- Delete button
    local delete_toggle = subheader.add{type="sprite-button", sprite="utility/trash", style="tool_button_red",
        tags={mod="fp", on_gui_click="delete_district_toggle", district_id=district.id},
        enabled=(district.parent:count() > 1), mouse_button_filter={"left"}}
    elements[district.id]["delete_toggle"] = delete_toggle
    local delete_confirm = subheader.add{type="sprite-button", sprite="utility/check_mark",
        tags={mod="fp", on_gui_click="delete_district_confirm", district_id=district.id},
        style="flib_tool_button_light_green", visible=false, mouse_button_filter={"left"}}
    delete_confirm.style.padding = 0
    elements[district.id]["delete_confirm"] = delete_confirm

    if not district.collapsed then
        build_items_flow(player, window_frame, district)
    end
end

local function refresh_districts_box(player)
    local player_table = util.globals.player_table(player)

    local main_elements = player_table.ui_state.main_elements
    if main_elements.main_frame == nil then return end

    local visible = player_table.ui_state.districts_view
    local main_flow = main_elements.districts_box.main_flow
    main_flow.parent.visible = visible
    if not visible then return end

    main_flow.clear()
    local location_items = {}
    for _, proto in pairs(storage.prototypes.locations) do
        table.insert(location_items, {"", "[img=" .. proto.sprite .. "] ", proto.localised_name})
    end

    util.globals.ui_state(player).tooltips.districts_box = {}
    for district in player_table.realm:iterator() do
        build_district_frame(player, district, location_items)
    end
end

local function build_districts_box(player)
    local main_elements = util.globals.main_elements(player)
    main_elements.districts_box = {}

    local parent_flow = main_elements.flows.right_vertical
    local scroll_pane = parent_flow.add{type="scroll-pane", style="flib_naked_scroll_pane_no_padding"}
    scroll_pane.style.top_margin = -2
    scroll_pane.style.extra_right_margin_when_activated = -12
    local flow_vertical = scroll_pane.add{type="flow", direction="vertical"}
    flow_vertical.style.vertical_spacing = MAGIC_NUMBERS.frame_spacing
    main_elements.districts_box["main_flow"] = flow_vertical

    refresh_districts_box(player)
end

-- ** EVENTS **
local listeners = {}

listeners.gui = {
    on_gui_click = {
        {
            name = "move_district",
            timeout = 10,
            handler = (function(player, tags, event)
                local district = OBJECT_INDEX[tags.district_id]  --[[@as District]]
                local spots_to_shift = (event.control) and 5 or ((not event.shift) and 1 or nil)
                district.parent:shift(district, tags.direction, spots_to_shift)

                util.raise.refresh(player, "districts_box")
            end)
        },
        {
            name = "select_district",
            handler = (function(player, tags, _)
                local selected_district = OBJECT_INDEX[tags.district_id]  --[[@as District]]
                util.context.set(player, selected_district)
                main_dialog.toggle_districts_view(player)
                util.raise.refresh(player, "all")
            end)
        },
        {
            name = "edit_district_name",
            handler = (function(player, tags, _)
                local main_elements = util.globals.main_elements(player)
                local district_elements = main_elements.districts_box[tags.district_id]
                district_elements.name_flow.visible = false
                district_elements.edit_flow.visible = true
            end)
        },
        {
            name = "save_district_name",
            handler = save_district_name
        },
        {
            name = "toggle_district_items",
            handler = (function(player, tags, _)
                local district = OBJECT_INDEX[tags.district_id]  --[[@as District]]
                district.collapsed = not district.collapsed

                util.raise.refresh(player, "districts_box")
            end)
        },
        {
            name = "delete_district_toggle",
            handler = (function(player, tags, _)
                local district = OBJECT_INDEX[tags.district_id]  --[[@as District]]

                local main_elements = util.globals.main_elements(player)
                local district_elements = main_elements.districts_box[tags.district_id]
                district_elements.delete_toggle.visible = false
                district_elements.delete_confirm.visible = true
            end)
        },
        {
            name = "delete_district_confirm",
            handler = (function(player, tags, _)
                local district = OBJECT_INDEX[tags.district_id]  --[[@as District]]

                local main_elements = util.globals.main_elements(player)
                local district_elements = main_elements.districts_box[tags.district_id]
                district_elements.delete_toggle.visible = true
                district_elements.delete_confirm.visible = false

                -- Removal will always find an alterantive because there always exists at least one District
                local adjacent_district = util.context.remove(player, district)  --[[@as District]]
                district.parent:remove(district)

                util.context.set(player, adjacent_district)
                util.raise.refresh(player, "all")
            end)
        },
        {
            name = "act_on_district_item",
            actions_table = {
                copy = {shortcut="shift-right"},
                add_to_cursor = {shortcut="alt-right"},
                factoriopedia = {shortcut="alt-left"}
            },
            handler = handle_item_button_click
        },
    },
    on_gui_confirmed = {
        {
            name = "confirm_district_name",
            handler = save_district_name
        }
    },
    on_gui_selection_state_changed = {
        {
            name = "change_district_location",
            handler = change_district_location
        }
    },
}

listeners.misc = {
    build_gui_element = (function(player, event)
        if event.trigger == "main_dialog" then
            build_districts_box(player)
        end
    end),
    refresh_gui_element = (function(player, event)
        local triggers = {districts_box=true, production=true, factory=true, all=true}
        if triggers[event.trigger] then refresh_districts_box(player) end
    end)
}

return { listeners }
