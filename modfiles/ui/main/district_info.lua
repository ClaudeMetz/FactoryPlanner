-- ** LOCAL UTIL **
local function refresh_district_info(player)
    local ui_state = util.globals.ui_state(player)
    if ui_state.main_elements.main_frame == nil then return end

    local district = util.context.get(player, "District")  --[[@as District]]
    local district_info_elements = ui_state.main_elements.district_info

    district_info_elements.name_label.caption = district.name

    if SPACE_TRAVEL then
        district_info_elements.location_sprite.sprite = district.location_proto.sprite
        district_info_elements.location_sprite.tooltip = district.location_proto.tooltip
    end

    district_info_elements.districts_button.toggled = ui_state.districts_view
end

local function build_district_info(player)
    local main_elements = util.globals.main_elements(player)
    main_elements.district_info = {}

    local parent_flow = main_elements.flows.left_vertical
    local frame = parent_flow.add{type="frame", style="inside_shallow_frame"}
    frame.style.size = {MAGIC_NUMBERS.list_width, MAGIC_NUMBERS.district_info_height}
    local flow_horizontal = frame.add{type="flow", direction="horizontal"}
    flow_horizontal.style.padding = {4, 4}
    flow_horizontal.style.vertical_align = "center"

    flow_horizontal.add{type="label", caption={"", {"fp.pu_district", 1}, ": "}, style="subheader_caption_label"}
    local label_name = flow_horizontal.add{type="label", style="bold_label"}
    label_name.style.maximal_width = 100
    main_elements.district_info["name_label"] = label_name

    if SPACE_TRAVEL then
        flow_horizontal.add{type="label", caption={"", {"fp.on"}, ": "}, style="subheader_caption_label"}
        local button_sprite = flow_horizontal.add{type="sprite"}
        button_sprite.style.size = 24
        button_sprite.style.stretch_image_to_widget_size = true
        main_elements.district_info["location_sprite"] = button_sprite
    end

    flow_horizontal.add{type="empty-widget", style="flib_horizontal_pusher"}
    local button_districts = flow_horizontal.add{type="sprite-button", sprite="utility/dropdown",
        tooltip={"fp.view_districts"}, tags={mod="fp", on_gui_click="toggle_districts_view"},
        style="tool_button", auto_toggle=true, mouse_button_filter={"left"}}
    button_districts.style.padding = 1
    main_elements.district_info["districts_button"] = button_districts

    refresh_district_info(player)
end


-- ** EVENTS **
local listeners = {}

listeners.gui = {
    on_gui_click = {
        {
            name = "toggle_districts_view",
            handler = (function(player, _, _)
                main_dialog.toggle_districts_view(player)
                util.raise.refresh(player, "production")
            end)
        }
    }
}

listeners.misc = {
    build_gui_element = (function(player, event)
        if event.trigger == "main_dialog" then
            build_district_info(player)
        end
    end),
    refresh_gui_element = (function(player, event)
        local triggers = {district_info=true, all=true}
        if triggers[event.trigger] then refresh_district_info(player) end
    end)
}

return { listeners }
