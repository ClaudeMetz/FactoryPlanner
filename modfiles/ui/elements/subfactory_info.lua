subfactory_info = {}

-- ** LOCAL UTIL **
local function repair_subfactory(player)
    -- This function can only run is a subfactory is selected and invalid
    local subfactory = data_util.get("context", player).subfactory

    Subfactory.repair(subfactory, player)
    data_util.cleanup_subfactory(player, subfactory, true)
end

-- ** TOP LEVEL **
subfactory_info.gui_events = {
    on_gui_click = {
        {
            name = "fp_button_subfactory_repair",
            timeout = 20,
            handler = (function(player, _, _)
                repair_subfactory(player)
            end)
        }
    }
}

function subfactory_info.build(player)
    local main_elements = data_util.get("main_elements", player)
    main_elements.subfactory_info = {}

    local parent_flow = main_elements.flows.left_vertical
    local frame_vertical = parent_flow.add{type="frame", direction="vertical",
      style="inside_shallow_frame_with_padding"}
    frame_vertical.style.height = 160
    frame_vertical.style.horizontally_stretchable = true

    -- No subfactory flow - This is very stupid
    local flow_no_subfactory = frame_vertical.add{type="flow", direction="vertical"}
    main_elements.subfactory_info["no_subfactory_flow"] = flow_no_subfactory
    flow_no_subfactory.add{type="empty-widget", style="flib_vertical_pusher"}
    local internal_flow = flow_no_subfactory.add{type="flow", direction="horizontal"}
    internal_flow.add{type="empty-widget", style="flib_horizontal_pusher"}
    internal_flow.add{type="label", caption={"fp.no_subfactory"}}
    internal_flow.add{type="empty-widget", style="flib_horizontal_pusher"}
    flow_no_subfactory.add{type="empty-widget", style="flib_vertical_pusher"}

    -- Repair flow
    local flow_repair = frame_vertical.add{type="flow", direction="vertical"}
    main_elements.subfactory_info["repair_flow"] = flow_repair

    local label = flow_repair.add{type="label", caption={"fp.warning_with_icon", {"fp.subfactory_needs_repair"}}}
    label.style.single_line = false
    local button_repair = flow_repair.add{type="button", name="fp_button_subfactory_repair",
      caption={"fp.repair_subfactory"}, style="rounded_button", mouse_button_filter={"left"}}
    button_repair.style.height = 26
    button_repair.style.top_margin = 4

    -- Subfactory info
    local flow_info = frame_vertical.add{type="flow", direction="vertical"}
    main_elements.subfactory_info["info_flow"] = flow_info


    subfactory_info.refresh(player)
end

function subfactory_info.refresh(player)
    local ui_state = data_util.get("ui_state", player)
    local subfactory_info_elements = ui_state.main_elements.subfactory_info
    local subfactory = ui_state.context.subfactory

    subfactory_info_elements.no_subfactory_flow.visible = (not subfactory)
    subfactory_info_elements.repair_flow.visible = (subfactory and not subfactory.valid)
    local valid_subfactory_selected = (subfactory and subfactory.valid)
    subfactory_info_elements.info_flow.visible = valid_subfactory_selected

    if valid_subfactory_selected then  -- we need to refresh some stuff in this case
    end
end