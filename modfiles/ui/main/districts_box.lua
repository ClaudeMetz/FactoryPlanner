local District = require("backend.data.District")

-- ** LOCAL UTIL **
local function save_district_name(player, tags, _)
    local main_elements = util.globals.main_elements(player)
    local district_elements = main_elements.districts_box[tags.district_id]

    local district = OBJECT_INDEX[tags.district_id]  --[[@as District]]
    district.name = district_elements.name_textfield.text
    district_elements.name_label.caption = district.name  -- saves the refresh

    district_elements.edit_flow.visible = false
    district_elements.name_flow.visible = true

    util.raise.refresh(player, "district_info", nil)
end

local function build_district_frame(elements, district, selected_id, location_items)
    elements[district.id] = {}

    local window_frame = elements.vertical_flow.add{type="frame", direction="vertical", style="inside_shallow_frame"}
    local subheader = window_frame.add{type="frame", direction="horizontal", style="subheader_frame"}

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

    local select_button = subheader.add{type="button", caption={"fp.select"}, style="list_box_item",
        tags={mod="fp", on_gui_click="select_district", district_id=district.id},
        enabled=(district.id ~= selected_id), mouse_button_filter={"left"}}
    select_button.style.font = "default-bold"
    select_button.style.padding = {0, 4}

    -- Name
    subheader.add{type="label", caption={"", {"fp.pu_district", 1}, ": "}, style="subheader_caption_label"}

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
    elements[district.id]["name_textfield"] = textfield_name
    flow_edit.add{type="sprite-button", style="mini_button_aligned_to_text_vertically_when_centered",
        tags={mod="fp", on_gui_click="save_district_name", district_id=district.id}, sprite="utility/rename_icon",
        tooltip={"fp.save_name"}, mouse_button_filter={"left"}}

    -- Location
    local label_location = subheader.add{type="label", caption={"", {"fp.pu_location", 1}, ": "},
        style="subheader_caption_label"}
    label_location.style.left_margin = 8
    -- Using the location id for the index works because the location prototypes are in id order
    subheader.add{type="drop-down", items=location_items, selected_index=district.location_proto.id,
        tags={mod="fp", on_gui_selection_state_changed="change_district_location", district_id=district.id}}

    -- Delete button
    subheader.add{type="empty-widget", style="flib_horizontal_pusher"}
    subheader.add{type="sprite-button", tags={mod="fp", on_gui_click="delete_district", district_id=district.id},
        sprite="utility/trash", style="tool_button_red", enabled=(district.parent:count() > 1),
        mouse_button_filter={"left"}}

    local scroll_pane = window_frame.add{type="scroll-pane", style="flib_naked_scroll_pane"}

end

local function refresh_districts_box(player)
    local player_table = util.globals.player_table(player)

    local main_elements = player_table.ui_state.main_elements
    if main_elements.main_frame == nil then return end

    local visible = player_table.ui_state.districts_view
    local main_flow = main_elements.districts_box.vertical_flow
    main_flow.visible = visible
    if not visible then return end

    main_flow.clear()
    local selected_district_id = util.context.get(player, "District").id
    local location_items = {}
    for _, proto in pairs(global.prototypes.locations) do
        table.insert(location_items, {"", "[img=" .. proto.sprite .. "] ", proto.localised_name})
    end

    for district in player_table.realm:iterator() do
        build_district_frame(main_elements.districts_box, district, selected_district_id, location_items)
    end

    main_flow.add{type="button", caption={"fp.add_district"}, style="fp_button_green",
        tags={mod="fp", on_gui_click="add_district"}, mouse_button_filter={"left"}}
end

local function build_districts_box(player)
    local main_elements = util.globals.main_elements(player)
    main_elements.districts_box = {}

    local parent_flow = main_elements.flows.right_vertical
    local flow_vertical = parent_flow.add{type="flow", direction="vertical"}
    flow_vertical.style.vertical_spacing = MAGIC_NUMBERS.frame_spacing
    main_elements.districts_box["vertical_flow"] = flow_vertical

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

                util.raise.refresh(player, "districts_box", nil)
            end)
        },
        {
            name = "select_district",
            handler = (function(player, tags, _)
                local selected_district = OBJECT_INDEX[tags.district_id]  --[[@as District]]
                util.context.set(player, selected_district)
                util.raise.refresh(player, "all", nil)
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
            name = "delete_district",
            handler = (function(player, tags, _)
                local district = OBJECT_INDEX[tags.district_id]  --[[@as District]]

                -- Removal will always find an alterantive because there always exists at least one District
                local adjacent_district = util.context.remove(player, district)  --[[@as District]]
                district.parent:remove(district)

                util.context.set(player, adjacent_district)
                util.raise.refresh(player, "all", nil)
            end)
        },
        {
            name = "add_district",
            handler = (function(player, _, _)
                local realm = util.globals.player_table(player).realm
                realm:insert(District.init())
                util.raise.refresh(player, "districts_box", nil)
            end)
        }
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
            handler = (function(player, tags, event)
                local district = OBJECT_INDEX[tags.district_id]  --[[@as District]]
                local location_proto_id = event.element.selected_index
                district.location_proto = global.prototypes.locations[location_proto_id]

                util.raise.refresh(player, "district_info", nil)
            end)
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
