-- ** LOCAL UTIL **
local function refresh_districts_box(player)
    local player_table = util.globals.player_table(player)

    local main_elements = player_table.ui_state.main_elements
    if main_elements.main_frame == nil then return end

    local visible = player_table.ui_state.districts_view
    main_elements.districts_box.horizontal_flow.visible = visible
    if not visible then return end

end

local function build_districts_box(player)
    local main_elements = util.globals.main_elements(player)
    main_elements.districts_box = {}

    local parent_flow = main_elements.flows.right_vertical
    local flow_horizontal = parent_flow.add{type="flow", direction="horizontal"}
    main_elements.districts_box["horizontal_flow"] = flow_horizontal


    refresh_districts_box(player)
end

-- ** EVENTS **
local listeners = {}

listeners.gui = {
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
