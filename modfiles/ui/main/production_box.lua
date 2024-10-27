local Line = require("backend.data.Line")
local matrix_engine = require("backend.calculation.matrix_engine")

-- ** LOCAL UTIL **
local function refresh_paste_button(player)
    local main_elements = util.globals.main_elements(player)
    if not main_elements.production_box then return end
    local factory = util.context.get(player, "Factory")  --[[@as Factory?]]

    local line_copied = util.clipboard.check_classes(player, {Floor=true, Line=true})
    main_elements.production_box.paste_button.visible = (factory ~= nil and line_copied) or false
end

local function refresh_solver_frame(player)
    local factory = util.context.get(player, "Factory")  --[[@as Factory]]
    local main_elements = util.globals.main_elements(player)
    local solver_flow = main_elements.solver_flow
    solver_flow.clear()

    local factory_data = solver.generate_factory_data(player, factory)
    local matrix_metadata = matrix_engine.get_matrix_solver_metadata(factory_data)
    if matrix_metadata.num_rows == 0 then return end  -- skip if there are no active lines
    local linear_dependence_data = matrix_engine.get_linear_dependence_data(factory_data, matrix_metadata)
    local num_needed_free_items = matrix_metadata.num_rows - matrix_metadata.num_cols + #matrix_metadata.free_items

    if next(linear_dependence_data.linearly_dependent_recipes) then
        main_elements.solver_frame.visible = true

        local caption = {"fp.error_message", {"fp.info_label", {"fp.linearly_dependent_recipes"}}}
        solver_flow.add{type="label", caption=caption, tooltip={"fp.linearly_dependent_recipes_tt"}, style="bold_label"}
        local flow_recipes = solver_flow.add{type="flow", direction="horizontal"}

        for _, recipe_proto in pairs(linear_dependence_data.linearly_dependent_recipes) do
            local sprite = flow_recipes.add{type="sprite", sprite=recipe_proto.sprite,
                tooltip=recipe_proto.localised_name, resize_to_sprite=true}
            sprite.style.size = 36
            sprite.style.stretch_image_to_widget_size = true
        end

    elseif num_needed_free_items ~= 0 then
        main_elements.solver_frame.visible = true

        local function build_item_flow(flow, status, items)
            for _, proto in pairs(items) do
                local tooltip = {"fp.turn_" .. status, proto.localised_name}
                local color = (status == "unrestricted") and "green" or "default"
                flow.add{type="sprite-button", sprite=proto.sprite, tooltip=tooltip,
                    tags={mod="fp", on_gui_click="switch_matrix_item", status=status, type=proto.type, name=proto.name},
                    style="flib_slot_button_" .. color .. "_small", mouse_button_filter={"left"}}
            end
        end

        local needs_choice = (#linear_dependence_data.allowed_free_items > 0)
        local item_count = 0

        if needs_choice then
            local caption = {"fp.error_message", {"fp.info_label", {"fp.choose_unrestricted_items"}}}
            local tooltip = {"fp.choose_unrestricted_items_tt", num_needed_free_items,
                {"fp.pl_item", num_needed_free_items}}
            solver_flow.add{type="label", caption=caption, tooltip=tooltip, style="bold_label"}
        else
            solver_flow.add{type="label", caption={"fp.info_label", {"fp.unrestricted_items_balanced"}},
                tooltip={"fp.unrestricted_items_balanced_tt"}, style="bold_label"}
        end

        local flow_unrestricted = solver_flow.add{type="flow", direction="horizontal"}
        build_item_flow(flow_unrestricted, "unrestricted", matrix_metadata.free_items)
        item_count = item_count + #matrix_metadata.free_items

        if needs_choice then
            local flow_constrained = solver_flow.add{type="flow", direction="horizontal"}
            build_item_flow(flow_constrained, "constrained", linear_dependence_data.allowed_free_items)
            item_count = item_count + #linear_dependence_data.allowed_free_items
        end

        -- This is some total bullshit because extra_bottom_padding_when_activated doesn't work
        local total_width = 180 + (4 * 12) + (item_count * 40)
        local interface_width = util.globals.ui_state(player).main_dialog_dimensions.width
        local box_width = interface_width - MAGIC_NUMBERS.list_width
        solver_flow.style.bottom_padding = (total_width > box_width) and 16 or 4
    end
end


local function change_floor(player, destination)
    if util.context.ascend_floors(player, destination) then
        -- Only refresh if the floor was indeed changed
        util.raise.refresh(player, "production")
    end
end

local function handle_solver_change(player, _, event)
    local factory = util.context.get(player, "Factory")  --[[@as Factory]]
    local new_solver = (event.element.switch_state == "left") and "traditional" or "matrix"

    if new_solver == "matrix" then
        factory.matrix_free_items = {}  -- activate the matrix solver
    else
        factory.matrix_free_items = nil  -- disable the matrix solver
        factory.linearly_dependant = false
    end

    local ui_state = util.globals.ui_state(player)
    if ui_state.districts_view then main_dialog.toggle_districts_view(player) end
    solver.update(player, factory)
    util.raise.refresh(player, "factory")
end

local function repair_factory(player, _, _)
    -- This function can only run is a factory is selected and invalid
    local factory = util.context.get(player, "Factory")  --[[@as Factory]]
    factory:repair(player)

    local ui_state = util.globals.ui_state(player)
    if ui_state.districts_view then main_dialog.toggle_districts_view(player) end
    solver.update(player, factory)
    util.raise.refresh(player, "all")  -- needs the full refresh to reset factory list buttons
end

local function paste_line(player, _, _)
    local floor = util.context.get(player, "Floor")  --[[@as Floor]]

    local dummy_line = Line.init({}, "produce")
    util.clipboard.dummy_paste(player, dummy_line, floor)
end

local function switch_matrix_item(player, tags, _)
    local factory = util.context.get(player, "Factory")  --[[@as Factory]]

    if tags.status == "unrestricted" then
        for index, item in pairs(factory.matrix_free_items) do
            if item.type == tags.type and item.name == tags.name then
                table.remove(factory.matrix_free_items, index)
                break
            end
        end
    else -- "constrained"
        local item_proto = prototyper.util.find("items", tags.name, tags.type)
        table.insert(factory.matrix_free_items, item_proto)
    end

    solver.update(player, factory)
    util.raise.refresh(player, "factory")
end


local function refresh_production_box(player)
    local ui_state = util.globals.ui_state(player)
    local factory = util.context.get(player, "Factory")  --[[@as Factory?]]
    local floor = util.context.get(player, "Floor")  --[[@as Floor?]]

    if ui_state.main_elements.main_frame == nil then return end
    local production_box_elements = ui_state.main_elements.production_box

    local visible = not ui_state.districts_view
    production_box_elements.vertical_frame.visible = visible
    if not visible then return end

    local factory_valid = factory ~= nil and factory.valid
    local any_lines_present = factory_valid and not factory.archived and floor:count() > 0
    local current_level = (factory_valid) and floor.level or 1

    production_box_elements.level_label.caption = (not factory_valid) and ""
        or {"fp.bold_label", {"", {"fp.level"}, " ", current_level}}

    production_box_elements.floor_up_button.visible = factory_valid
    production_box_elements.floor_up_button.enabled = (current_level > 1)

    production_box_elements.floor_top_button.visible = factory_valid
    production_box_elements.floor_top_button.enabled = (current_level > 1)

    production_box_elements.solver_flow.visible = factory_valid
    if factory_valid then
        local matrix_solver_active = (factory.matrix_free_items ~= nil)
        local switch_state = (matrix_solver_active) and "right" or "left"
        production_box_elements.solver_choice_switch.switch_state = switch_state
        production_box_elements.solver_choice_switch.enabled = (not factory.archived)
    end

    production_box_elements.utility_dialog_button.enabled = factory_valid

    production_box_elements.instruction_label.visible = false
    if factory == nil then
        production_box_elements.instruction_label.caption = {"fp.production_instruction_factory"}
        production_box_elements.instruction_label.visible = true
    elseif factory_valid and not factory.archived and not any_lines_present then
        if factory:count() == 0 then
            production_box_elements.instruction_label.caption = {"fp.production_instruction_product"}
            production_box_elements.instruction_label.visible = true
        else
            production_box_elements.instruction_label.caption = {"fp.production_instruction_recipe"}
            production_box_elements.instruction_label.visible = true
        end
    end

    local invalid_factory_selected = (factory and not factory.valid) or false
    production_box_elements.repair_flow.visible = invalid_factory_selected

    if invalid_factory_selected then
        local last_modset = util.porter.format_modset_diff(factory.last_valid_modset)
        production_box_elements.diff_label.tooltip = last_modset
    end

    refresh_paste_button(player)

    ui_state.main_elements.solver_frame.visible = false
    if any_lines_present and factory.matrix_free_items then
        refresh_solver_frame(player)
    end
end

local function build_production_box(player)
    local main_elements = util.globals.main_elements(player)
    main_elements.production_box = {}

    local parent_flow = main_elements.flows.right_vertical
    local frame_vertical = parent_flow.add{type="frame", direction="vertical", style="inside_deep_frame"}
    main_elements.production_box["vertical_frame"] = frame_vertical

    -- Subheader
    local subheader = frame_vertical.add{type="frame", direction="horizontal", style="subheader_frame"}
    subheader.style.top_padding = 4
    local flow_production = subheader.add{type="flow", direction="horizontal"}

    local button_utility_dialog = flow_production.add{type="sprite-button", tooltip={"fp.utility_dialog_tt"},
        tags={mod="fp", on_gui_click="open_utility_dialog"}, sprite="flib_settings_black", style="tool_button",
        mouse_button_filter={"left"}}
    button_utility_dialog.style.padding = 1
    main_elements.production_box["utility_dialog_button"] = button_utility_dialog

    local label_production = flow_production.add{type="label", caption={"fp.u_production"}, style="frame_title"}
    label_production.style.padding = {0, 8}

    local label_level = flow_production.add{type="label"}
    label_level.style.margin = {5, 6, 0, 4}
    main_elements.production_box["level_label"] = label_level

    local button_floor_up = flow_production.add{type="sprite-button", sprite="fp_arrow_line_up",
        tooltip={"fp.floor_up_tt"}, tags={mod="fp", on_gui_click="change_floor", destination="up"},
        style="fp_sprite-button_rounded_icon", mouse_button_filter={"left"}}
    button_floor_up.style.top_margin = 2
    main_elements.production_box["floor_up_button"] = button_floor_up

    local button_floor_top = flow_production.add{type="sprite-button", sprite="fp_arrow_line_bar_up",
        tooltip={"fp.floor_top_tt"}, tags={mod="fp", on_gui_click="change_floor", destination="top"},
        style="fp_sprite-button_rounded_icon", mouse_button_filter={"left"}}
    button_floor_top.style.padding = {3, 2, 1, 2}
    button_floor_top.style.top_margin = 2
    main_elements.production_box["floor_top_button"] = button_floor_top

    flow_production.add{type="empty-widget", style="flib_horizontal_pusher"}

    local flow_solver = flow_production.add{type="flow", direction="horizontal"}
    flow_solver.style.horizontal_spacing = 12
    flow_solver.style.margin = {4, 8, 0, 0}
    main_elements.production_box["solver_flow"] = flow_solver
    flow_solver.add{type="label", caption={"fp.info_label", {"fp.solver_choice"}}, style="bold_label",
        tooltip={"fp.solver_choice_tt"}}
    local switch_solver_choice = flow_solver.add{type="switch",
        right_label_caption={"fp.solver_choice_matrix"}, left_label_caption={"fp.solver_choice_traditional"},
        tags={mod="fp", on_gui_switch_state_changed="solver_choice_changed"}}
    main_elements.production_box["solver_choice_switch"] = switch_solver_choice


    -- Main scrollpane
    local scroll_pane_production = frame_vertical.add{type="scroll-pane", style="flib_naked_scroll_pane_no_padding"}
    scroll_pane_production.style.extra_right_padding_when_activated = 0
    scroll_pane_production.style.bottom_padding = 12
    scroll_pane_production.style.extra_bottom_padding_when_activated = -12
    main_elements.production_box["production_scroll_pane"] = scroll_pane_production

    -- Instruction label
    local label_instruction = frame_vertical.add{type="label", style="bold_label"}
    label_instruction.style.margin = 16
    main_elements.production_box["instruction_label"] = label_instruction

    -- Repair panel
    local flow_repair = frame_vertical.add{type="flow", direction="vertical"}
    flow_repair.style.margin = 12
    flow_repair.style.width = 380
    main_elements.production_box["repair_flow"] = flow_repair

    local label_repair = flow_repair.add{type="label", caption={"fp.warning_with_icon", {"fp.factory_needs_repair"}}}
    label_repair.style.single_line = false

    local flow_actions = flow_repair.add{type="flow", direction="horizontal"}
    flow_actions.style.top_margin = 8
    local label_diff = flow_actions.add{type="label", caption={"fp.modset_differences"}, style="bold_label"}
    main_elements.production_box["diff_label"] = label_diff
    flow_actions.add{type="empty-widget", style="flib_horizontal_pusher"}
    local button_repair = flow_actions.add{type="button", tags={mod="fp", on_gui_click="repair_factory"},
        caption={"fp.repair_factory"}, mouse_button_filter={"left"}}
    button_repair.style.minimal_width = 0
    button_repair.style.right_margin = 16
    button_repair.style.height = 22
    button_repair.style.padding = {0, 4}

    -- Paste button
    local button_paste = frame_vertical.add{type="button", caption={"fp.paste_line"}, tooltip={"fp.paste_line_tt"},
        style="rounded_button", tags={mod="fp", on_gui_click="paste_line"}, mouse_button_filter={"left"}}
    button_paste.style.margin = 12
    button_paste.style.minimal_width = 0
    main_elements.production_box["paste_button"] = button_paste

    frame_vertical.add{type="empty-widget", style="flib_vertical_pusher"}
    frame_vertical.add{type="empty-widget", style="flib_horizontal_pusher"}

    -- Bottom UI for messages & solver
    local scroll_pane_messages = frame_vertical.add{type="scroll-pane", vertical_scroll_policy="never",
        visible=false, style="flib_naked_scroll_pane_no_padding"}
    main_elements["messages_frame"] = scroll_pane_messages

    local line_messages = scroll_pane_messages.add{type="line", direction="horizontal"}
    line_messages.style.margin = -1  -- hack around some scrollpane styling issues

    local flow_messages = scroll_pane_messages.add{type="flow", direction="vertical"}
    flow_messages.style.padding = {0, 12, 6, 12}
    main_elements["messages_flow"] = flow_messages

    local scroll_pane_solver = frame_vertical.add{type="scroll-pane", vertical_scroll_policy="never",
        visible=false, style="flib_naked_scroll_pane_no_padding"}
    main_elements["solver_frame"] = scroll_pane_solver

    local line_solver = scroll_pane_solver.add{type="line", direction="horizontal"}
    line_solver.style.margin = -1  -- hack around some scrollpane styling issues

    local flow_solver_options = scroll_pane_solver.add{type="flow", direction="horizontal"}
    flow_solver_options.style.padding = {0, 12, 4, 12}
    flow_solver_options.style.vertical_align = "center"
    flow_solver_options.style.horizontal_spacing = 12
    main_elements["solver_flow"] = flow_solver_options

    refresh_production_box(player)
end


-- ** EVENTS **
local listeners = {}

listeners.gui = {
    on_gui_click = {
        {
            name = "change_floor",
            handler = (function(player, tags, _)
                change_floor(player, tags.destination)
            end)
        },
        {
            name = "open_utility_dialog",
            handler = (function(player, _, _)
                util.raise.open_dialog(player, {dialog="utility"})
            end)
        },
        {
            name = "repair_factory",
            timeout = 20,
            handler = repair_factory
        },
        {
            name = "paste_line",
            handler = paste_line
        },
        {
            name = "switch_matrix_item",
            handler = switch_matrix_item
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
    fp_up_floor = (function(player, _, _)
        if main_dialog.is_in_focus(player) then change_floor(player, "up") end
    end),
    fp_top_floor = (function(player, _, _)
        if main_dialog.is_in_focus(player) then change_floor(player, "top") end
    end),

    build_gui_element = (function(player, event)
        if event.trigger == "main_dialog" then
            build_production_box(player)
        end
    end),
    refresh_gui_element = (function(player, event)
        local triggers = {production_box=true, production_detail=true, production=true, factory=true, all=true}
        if triggers[event.trigger] then refresh_production_box(player)
        elseif event.trigger == "paste_button" then refresh_paste_button(player) end
    end)
}

return { listeners }
