-- ** LOCAL UTIL **
local function refresh_district_info(player)
    local ui_state = lib.globals.ui_state(player)
    if ui_state.main_elements.main_frame == nil then return end

    local district = lib.context.get(player, "District")  --[[@as District]]
    local district_info_elements = ui_state.main_elements.district_info

    district_info_elements.name_label.caption = district.name

    if MULTIPLE_PLANETS then
        district_info_elements.location_sprite.sprite = district.location_proto.sprite
        district_info_elements.location_sprite.tooltip = district.location_proto.tooltip
    end

    district_info_elements.districts_button.toggled = ui_state.districts_view
end

local function build_district_info(player)
    local main_elements = lib.globals.main_elements(player)
    main_elements.district_info = {}

    local parent_flow = main_elements.flows.left_vertical
    local frame = parent_flow.add{type="frame", style="inside_shallow_frame"}
    frame.style.size = {MAGIC_NUMBERS.list_width, MAGIC_NUMBERS.district_info_height}
    local flow_horizontal = frame.add{type="flow", direction="horizontal"}
    flow_horizontal.style.padding = {4, 4}
    flow_horizontal.style.vertical_align = "center"

    flow_horizontal.add{type="label", caption={"", {"fp.pu_district", 1}, ": "}, style="subheader_caption_label"}
    local label_name = flow_horizontal.add{type="label", style="bold_label"}
    label_name.style.maximal_width = (MULTIPLE_PLANETS) and 120 or 190
    main_elements.district_info["name_label"] = label_name

    if MULTIPLE_PLANETS then
        flow_horizontal.add{type="label", caption={"", {"fp.on"}, ": "}, style="subheader_caption_label"}
        local button_sprite = flow_horizontal.add{type="sprite"}
        button_sprite.style.size = 24
        button_sprite.style.stretch_image_to_widget_size = true
        main_elements.district_info["location_sprite"] = button_sprite
    end

    flow_horizontal.add{type="empty-widget", style="fflib_horizontal_pusher"}
    local button_districts = flow_horizontal.add{type="sprite-button", sprite="fp_panel",
        tooltip={"fp.view_districts"}, tags={mod="fp", on_gui_click="toggle_districts_view"},
        style="tool_button", auto_toggle=true, mouse_button_filter={"left"}}
    button_districts.style.padding = -4
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
                lib.gui.run_refresh(player, "factory")
            end)
        }
    }
}

listeners.player = {
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

listeners.game = {
    on_research_finished = (function(event)
        if game.tick == 0 then return end  -- no shenanigans during setup
        for _, effect in pairs(event.research.prototype.effects) do
            if effect.type == "mining-drill-productivity-bonus"
                    or effect.type == "change-recipe-productivity" then
                local offset = 0
                for _, player in pairs(game.players) do
                    local realm = lib.globals.player_table(player).realm
                    realm:schedule_solver_updates(game.tick + offset, player)
                    offset = offset + 2
                end
                break
            end
        end
    end)
}

return { listeners }
