-- ** LOCAL UTIL **
local function repair_factory(player, _, _)
    -- This function can only run is a factory is selected and invalid
    local factory = util.context.get(player, "Factory")  --[[@as Factory]]
    factory:repair(player)

    local ui_state = util.globals.ui_state(player)
    if ui_state.districts_view then main_dialog.toggle_districts_view(player) end
    solver.update(player, factory)
    util.raise.refresh(player, "all")  -- needs the full refresh to reset factory list buttons
end

local function change_timescale(player, new_timescale)
    local factory = util.context.get(player, "Factory")  --[[@as Factory]]

    -- Blank out first, then update so District items are updated correctly
    solver.update(player, factory, true)
    factory.timescale = new_timescale
    solver.update(player, factory)

    local ui_state = util.globals.ui_state(player)
    if ui_state.districts_view then main_dialog.toggle_districts_view(player) end

    view_state.rebuild_state(player)
    util.raise.refresh(player, "factory")
end

local function handle_solver_change(player, _, event)
    local factory = util.context.get(player, "Factory")  --[[@as Factory]]
    local new_solver = (event.element.switch_state == "left") and "traditional" or "matrix"

    if new_solver == "matrix" then
        factory.matrix_free_items = {}  -- activate the matrix solver
    else
        factory.matrix_free_items = nil  -- disable the matrix solver
        factory.linearly_dependant = false

        local any_lines_removed = factory.top_floor:remove_consuming_lines()
        if any_lines_removed then  -- inform the user if any byproduct recipes are being removed
            util.messages.raise(player, "hint", {"fp.hint_byproducts_removed"}, 1)
        end
    end

    local ui_state = util.globals.ui_state(player)
    if ui_state.districts_view then main_dialog.toggle_districts_view(player) end
    solver.update(player, factory)
    util.raise.refresh(player, "factory")
end


local function refresh_factory_info(player)
    local main_elements = util.globals.main_elements(player)
    if main_elements.main_frame == nil then return end

    local factory_info_elements = main_elements.factory_info
    local factory = util.context.get(player, "Factory")  --[[@as Factory?]]

    local invalid_factory_selected = (factory and not factory.valid) or false
    factory_info_elements.repair_button.visible = invalid_factory_selected
    factory_info_elements.repair_label.visible = invalid_factory_selected

    local valid_factory_selected = (factory and factory.valid) or false
    factory_info_elements.power_emissions_flow.visible = valid_factory_selected
    factory_info_elements.info_flow.visible = valid_factory_selected

    if factory == nil then return end

    if invalid_factory_selected then
        factory_info_elements.repair_label.tooltip = util.porter.format_modset_diff(factory.last_valid_modset)

    elseif valid_factory_selected then  -- we need to refresh some stuff in this case
        -- Power + Emissions
        local top_floor = factory.top_floor
        local label_power = factory_info_elements.power_label
        label_power.caption = {"fp.bold_label", util.format.SI_value(top_floor.power, "W", 3)}
        label_power.tooltip = util.format.SI_value(top_floor.power, "W", 5)

        local label_emissions = factory_info_elements.emissions_label
        label_emissions.tooltip = util.gui.format_emissions(top_floor.emissions)

        -- Timescale
        for _, button in pairs(factory_info_elements.timescales_table.children) do
            button.toggled = (factory.timescale == button.tags.timescale)
        end

        -- Solver Choice
        local matrix_solver_active = (factory.matrix_free_items ~= nil)
        local switch_state = (matrix_solver_active) and "right" or "left"
        factory_info_elements.solver_choice_switch.switch_state = switch_state
        factory_info_elements.solver_choice_switch.enabled = (not factory.archived)
    end
end

local function build_factory_info(player)
    local main_elements = util.globals.main_elements(player)
    main_elements.factory_info = {}

    local parent_flow = main_elements.flows.left_vertical
    local frame_vertical = parent_flow.add{type="frame", direction="vertical",
        style="inside_shallow_frame_with_padding"}
    frame_vertical.style.size = {MAGIC_NUMBERS.list_width, MAGIC_NUMBERS.factory_info_height}

    local flow_title = frame_vertical.add{type="flow", direction="horizontal"}
    flow_title.style.margin = {-4, 0, 8, 0}
    flow_title.add{type="label", caption={"fp.factory_info"}, style="caption_label"}

    -- Repair button
    local button_repair = flow_title.add{type="button", tags={mod="fp", on_gui_click="repair_factory"},
        caption={"fp.repair_factory"}, style="rounded_button", mouse_button_filter={"left"}}
    button_repair.style.height = 20
    button_repair.style.top_padding = -2
    button_repair.style.margin = {2, 0, -2, 12}
    main_elements.factory_info["repair_button"] = button_repair

    -- Power + Emissions
    flow_title.add{type="empty-widget", style="flib_horizontal_pusher"}
    local flow_power_emissions = flow_title.add{type="flow", direction="horizontal"}
    main_elements.factory_info["power_emissions_flow"] = flow_power_emissions
    local label_power_value = flow_power_emissions.add{type="label"}
    main_elements.factory_info["power_label"] = label_power_value
    flow_power_emissions.add{type="label", caption="|"}
    local label_emissions_value = flow_power_emissions.add{type="label",
        caption={"fp.info_label", {"fp.emissions_title"}}}
    main_elements.factory_info["emissions_label"] = label_emissions_value


    -- Repair label
    local label_repair = frame_vertical.add{type="label", caption={"fp.warning_with_icon", {"fp.factory_needs_repair"}}}
    label_repair.style.single_line = false
    label_repair.style.top_margin = -4
    main_elements.factory_info["repair_label"] = label_repair


    -- Factory info
    local flow_info = frame_vertical.add{type="flow", direction="vertical"}
    flow_info.style.vertical_spacing = 8
    main_elements.factory_info["info_flow"] = flow_info

    -- Timescale
    local flow_timescale = flow_info.add{type="flow", direction="horizontal"}
    flow_timescale.style.horizontal_spacing = 10
    flow_timescale.style.vertical_align = "center"

    flow_timescale.add{type="label", caption={"fp.info_label", {"fp.timescale"}}, tooltip={"fp.timescale_tt"}}
    flow_timescale.add{type="empty-widget", style="flib_horizontal_pusher"}

    local table_timescales = flow_timescale.add{type="table", column_count=table_size(TIMESCALE_MAP)}
    table_timescales.style.horizontal_spacing = 0
    main_elements.factory_info["timescales_table"] = table_timescales

    for scale, name in pairs(TIMESCALE_MAP) do
        local button = table_timescales.add{type="button", caption={"", "1", {"fp.unit_" .. name}},
            tags={mod="fp", on_gui_click="change_timescale", timescale=scale}, mouse_button_filter={"left"}}
        button.style.size = {42, 26}
        button.style.padding = 0
    end

    -- Solver Choice
    local flow_solver_choice = flow_info.add{type="flow", direction="horizontal"}
    flow_solver_choice.style.horizontal_spacing = 10
    flow_solver_choice.style.vertical_align = "center"

    flow_solver_choice.add{type="label", caption={"fp.info_label", {"fp.solver_choice"}},
        tooltip={"fp.solver_choice_tt"}}
    flow_solver_choice.add{type="empty-widget", style="flib_horizontal_pusher"}

    local switch_solver_choice = flow_solver_choice.add{type="switch",
        right_label_caption={"fp.solver_choice_matrix"}, left_label_caption={"fp.solver_choice_traditional"},
        tags={mod="fp", on_gui_switch_state_changed="solver_choice_changed"}}
    main_elements.factory_info["solver_choice_switch"] = switch_solver_choice

    refresh_factory_info(player)
end


-- ** EVENTS **
local listeners = {}

listeners.gui = {
    on_gui_click = {
        {
            name = "repair_factory",
            timeout = 20,
            handler = repair_factory
        },
        {
            name = "change_timescale",
            handler = (function(player, tags, _)
                change_timescale(player, tags.timescale)
            end)
        }
    },
    on_gui_switch_state_changed = {
        {
            name = "solver_choice_changed",
            handler = handle_solver_change
        }
    }
}

listeners.misc = {
    build_gui_element = (function(player, event)
        if event.trigger == "main_dialog" then
            build_factory_info(player)
        end
    end),
    refresh_gui_element = (function(player, event)
        local triggers = {factory_info=true, factory=true, all=true}
        if triggers[event.trigger] then refresh_factory_info(player) end
    end)
}

return { listeners }
