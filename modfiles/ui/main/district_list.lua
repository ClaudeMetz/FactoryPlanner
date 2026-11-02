local MAX_DISTRICT_ROWS = 5
local DISTRICT_ROW_HEIGHT = 28

-- ** LOCAL UTIL **
---@param district District
---@return LocalisedString
local function district_tooltip(district)
    local location = district.location_proto  ---@as FPLocationPrototype
    return {"fp.district_location", district.name, location.localised_name, location.tooltip}
end

---@param listbox LuaGuiElement
---@param district District
---@param selected boolean
---@param held_factory Factory?
local function build_district_row(listbox, district, selected, held_factory)
    local active_count = district:count({archived=false})
    local button_width = MAGIC_NUMBERS.list_width - 24
    local left_padding, right_padding = 4, 12
    local row = listbox.add{type="flow", direction="horizontal"}
    row.style.horizontal_spacing = 0

    if held_factory and not held_factory.archived then
        local move_button = row.add{type="sprite-button", style="fp_sprite-button_move",
            sprite="fp_arrow_right", mouse_button_filter={"left"}, enabled=held_factory.parent ~= district,
            tooltip={"fp.move_factory_to_district", held_factory.name, district.name},
            tags={mod="fp", on_gui_click="place_factory_in_district", district_id=district.id}}
        move_button.style.size = {20, DISTRICT_ROW_HEIGHT}
        move_button.style.padding = 2
        button_width = button_width - 20
    end

    ---@class SelectDistrictTags
    ---@field district_id ObjectID
    local tags = {mod="fp", on_gui_click="select_district", district_id=district.id}
    local button = row.add{type="button", style="list_box_item",
        toggled=selected, mouse_button_filter={"left"},
        tooltip=district_tooltip(district), tags=tags}
    button.style.width = button_width
    button.style.height = DISTRICT_ROW_HEIGHT
    button.style.padding = {0, right_padding, 0, left_padding}

    local flow = button.add{type="flow", direction="horizontal", ignored_by_interaction=true}
    -- Buttons do not resize child flows, so match their available content width
    flow.style.width = button_width - left_padding - right_padding
    flow.style.vertical_align = "center"
    flow.style.horizontal_spacing = 8
    local label_name = flow.add{type="label", caption=district:tostring(), ignored_by_interaction=true}
    label_name.style.font = "default-listbox"
    label_name.style.font_color = selected and {0, 0, 0} or {1, 1, 1}
    label_name.style.horizontally_squashable = true
    flow.add{type="empty-widget", style="fflib_horizontal_pusher", ignored_by_interaction=true}
    local label_count = flow.add{type="label", caption=active_count,
        style="fp_label_district_count", ignored_by_interaction=true}
    if selected then label_count.style.font_color = {0.35, 0.35, 0.35} end
end

---@param player LuaPlayer
local function refresh_district_list(player)
    local ui_state = lib.globals.ui_state(player)
    if ui_state.main_elements.main_frame == nil then return end

    local selected_district = lib.context.get(player, "District")  ---@as District
    local frame = ui_state.main_elements.district_list.frame
    local realm = lib.globals.player_table(player).realm
    local district_count = realm:count()
    local single_district = (district_count == 1)
    frame.clear()
    frame.style.top_padding = (single_district) and 6 or 8
    frame.style.bottom_padding = (single_district) and 6 or 12

    local flow_horizontal = frame.add{type="flow", direction="horizontal"}
    flow_horizontal.style.height = 24
    flow_horizontal.style.bottom_margin = (single_district) and 0 or 8
    flow_horizontal.style.horizontally_stretchable = true
    flow_horizontal.style.vertical_align = "center"

    local label_districts = flow_horizontal.add{type="label",
        caption=(single_district) and selected_district:tostring() or {"fp.pu_district", 2},
        tooltip=(single_district) and district_tooltip(selected_district) or nil}
    label_districts.style.font = "fp_district_heading"
    label_districts.style.left_padding = 2
    label_districts.style.maximal_width = 180

    flow_horizontal.add{type="empty-widget", style="fflib_horizontal_pusher"}
    local button_districts = flow_horizontal.add{type="button",
        caption=(single_district) and {"fp.pu_district", 2} or {"fp.district_overview"},
        tooltip={"fp.view_districts"}, tags={mod="fp", on_gui_click="toggle_districts_view"},
        style="tool_button", auto_toggle=true, toggled=ui_state.districts_view, mouse_button_filter={"left"}}
    button_districts.style.font = "default-semibold"
    button_districts.style.padding = {0, 6}
    button_districts.style.minimal_width = 0
    button_districts.style.height = 24

    if single_district then return end

    local scroll_pane = frame.add{type="scroll-pane", style="list_box_in_shallow_frame_under_subheader_scroll_pane"}
    scroll_pane.style.maximal_height = MAX_DISTRICT_ROWS * DISTRICT_ROW_HEIGHT
    scroll_pane.style.horizontally_stretchable = true
    scroll_pane.style.extra_right_margin_when_activated = (district_count > MAX_DISTRICT_ROWS)
        and -frame.style.right_padding or 0
    scroll_pane.horizontal_scroll_policy = "never"
    local listbox = scroll_pane.add{type="flow", direction="vertical"}
    listbox.style.vertical_spacing = 0

    local held_factory = lib.gui.held_object(player, "factory_list")  ---@as Factory?
    for district in realm:iterator() do
        build_district_row(listbox, district, district == selected_district, held_factory)
    end
end

---@param player LuaPlayer
local function build_district_list(player)
    local main_elements = lib.globals.main_elements(player)
    local parent_flow = main_elements.flows.left_vertical
    local frame = parent_flow.add{type="frame", direction="vertical", style="inside_shallow_frame"}
    frame.style.width = MAGIC_NUMBERS.list_width
    frame.style.padding = {8, 12, 12, 12}
    main_elements.district_list = {frame=frame}

    refresh_district_list(player)
end


-- ** EVENTS **
local listeners = {}  ---@type ListenerDefinitions

listeners.gui = {
    on_gui_click = {
        {
            name = "select_district",
            handler = function(player, tags, _)
                ---@cast tags SelectDistrictTags
                local selected_district = OBJECT_INDEX[tags.district_id]  ---@as District
                lib.context.set(player, selected_district)
                lib.gui.run_refresh(player, "all")
            end
        },
        {
            name = "place_factory_in_district",
            handler = function(player, tags, _)
                ---@cast tags SelectDistrictTags
                local factory = lib.gui.held_object(player, "factory_list")  ---@as Factory?
                local district = OBJECT_INDEX[tags.district_id]  ---@as District
                if not factory or factory.archived or factory.parent == district then return end

                local adjacent_factory = lib.context.remove(player, factory)
                if lib.context.get(player, "Factory") == factory then
                    lib.context.set(player, adjacent_factory or factory.parent, true)
                end
                factory.parent:remove(factory)
                district:insert(factory)
                lib.globals.ui_state(player).held_object_id = nil

                solver.update(player, factory, true)
                lib.gui.run_refresh(player, "all")
            end
        },
        {
            name = "toggle_districts_view",
            handler = function(player, _, _)
                main_dialog.toggle_districts_view(player, false)
                lib.gui.run_refresh(player, "factory")
            end
        }
    }
}  ---@as GUIListenerDefinition

listeners.player = {
    build_gui_element = function(player, event)
        ---@cast event BuildGUIElementEventData
        if event.trigger == "main_dialog" then
            build_district_list(player)
        end
    end,
    refresh_gui_element = function(player, event)
        ---@cast event RefreshGUIElementEventData
        local triggers = {district_list=true, factory_list=true, all=true}
        if triggers[event.trigger] then refresh_district_list(player) end
    end
}

listeners.game = {
    on_research_finished = function(event)
        ---@cast event EventData.on_research_finished
        if game.tick == 0 then return end  -- no shenanigans during setup
        for _, effect in pairs(event.research.prototype.effects) do
            if effect.type == "mining-drill-productivity-bonus"
                    or effect.type == "change-recipe-productivity" then
                local offset = 1
                for _, player in pairs(game.players) do
                    local realm = lib.globals.player_table(player).realm
                    realm:schedule_solver_updates(game.tick + offset, player)
                    offset = offset + 2
                end
                break
            end
        end
    end
}

return { listeners }
