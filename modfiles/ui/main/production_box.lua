local Line = require("backend.data.Line")
local matrix_engine = require("backend.calculation.matrix_engine")

-- ** LOCAL UTIL **
local function refresh_production(player, _, _)
    local factory = util.context.get(player, "Factory")
    if factory and factory.valid then
        solver.update(player, factory)
        util.raise.refresh(player, "factory", nil)
    end
end

local function refresh_paste_button(player)
    local main_elements = util.globals.main_elements(player)
    if not main_elements.production_box then return end
    local factory = util.context.get(player, "Factory")  --[[@as Factory?]]

    local line_copied = util.clipboard.check_classes(player, {Floor=true, Line=true})
    main_elements.production_box.paste_button.visible = (factory ~= nil and line_copied)
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


local function paste_line(player, _, _)
    local floor = util.context.get(player, "Floor")  --[[@as Floor]]

    local dummy_line = Line.init({}, "produce")
    util.clipboard.dummy_paste(player, dummy_line, floor)
end

-- Changes the floor to either be the top one or the one above the current one
local function change_floor(player, destination)
    if util.context.descend_floors(player, destination) then
        -- Only refresh if the floor was indeed changed
        util.raise.refresh(player, "production", nil)
    end
end

local function switch_matrix_item(player, tags, event)
    local factory = util.context.get(player, "Factory")  --[[@as Factory]]

    if tags.status == "unrestricted" then
        for index, item in pairs(factory.matrix_free_items) do
            if item.type == tags.type and item.name == tags.name then
                table.remove(factory.matrix_free_items, index)
                break
            end
        end
    else -- "constrained"
        local item_proto = PROTOTYPE_MAPS.items[tags.type].members[tags.name]
        table.insert(factory.matrix_free_items, item_proto)
    end

    solver.update(player, factory)
    util.raise.refresh(player, "factory", nil)
end


local function refresh_production_box(player)
    local ui_state = util.globals.ui_state(player)
    local factory = util.context.get(player, "Factory")  --[[@as Factory?]]
    local floor = util.context.get(player, "Floor")  --[[@as Floor?]]

    if ui_state.main_elements.main_frame == nil then return end
    local production_box_elements = ui_state.main_elements.production_box

    local factory_valid = factory ~= nil and factory.valid
    local current_level = (factory_valid) and floor.level or 1
    local any_lines_present = factory_valid and not factory.archived and floor:count() > 0

    production_box_elements.refresh_button.enabled = any_lines_present
    production_box_elements.level_label.caption = (not factory_valid) and ""
        or {"fp.bold_label", {"", {"fp.level"}, " ", current_level}}

    production_box_elements.floor_up_button.visible = factory_valid
    production_box_elements.floor_up_button.enabled = (current_level > 1)

    production_box_elements.floor_top_button.visible = factory_valid
    production_box_elements.floor_top_button.enabled = (current_level > 1)

    production_box_elements.separator_line.visible = factory_valid
    production_box_elements.utility_dialog_button.visible = factory_valid

    util.raise.refresh(player, "view_state", production_box_elements.view_state_table)
    production_box_elements.view_state_table.visible = factory_valid

    production_box_elements.instruction_label.visible = false
    if factory == nil then
        production_box_elements.instruction_label.caption = {"fp.production_instruction_factory"}
        production_box_elements.instruction_label.visible = true
    elseif factory_valid and not any_lines_present then
        if factory:count() == 0 then
            production_box_elements.instruction_label.caption = {"fp.production_instruction_product"}
            production_box_elements.instruction_label.visible = true
        else
            production_box_elements.instruction_label.caption = {"fp.production_instruction_recipe"}
            production_box_elements.instruction_label.visible = true
        end
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

    local subheader = frame_vertical.add{type="frame", direction="horizontal", style="subheader_frame"}
    subheader.style.maximal_height = 100  -- large value to nullify maximal_height
    subheader.style.padding = {8, 8, 6, 8}

    local button_refresh = subheader.add{type="sprite-button", tags={mod="fp", on_gui_click="refresh_production"},
        sprite="utility/refresh", style="tool_button", tooltip={"fp.refresh_production"}, mouse_button_filter={"left"}}
    main_elements.production_box["refresh_button"] = button_refresh

    local label_title = subheader.add{type="label", caption={"fp.production"}, style="frame_title"}
    label_title.style.padding = {0, 8}

    local label_level = subheader.add{type="label"}
    label_level.style.right_margin = 8
    main_elements.production_box["level_label"] = label_level

    local button_floor_up = subheader.add{type="sprite-button", sprite="fp_arrow_line_up",
        tooltip={"fp.floor_up_tt"}, tags={mod="fp", on_gui_click="change_floor", destination="up"},
        style="fp_sprite-button_rounded_mini", mouse_button_filter={"left"}}
    main_elements.production_box["floor_up_button"] = button_floor_up

    local button_floor_top = subheader.add{type="sprite-button", sprite="fp_arrow_line_bar_up",
        tooltip={"fp.floor_top_tt"}, tags={mod="fp", on_gui_click="change_floor", destination="top"},
        style="fp_sprite-button_rounded_mini", mouse_button_filter={"left"}}
    main_elements.production_box["floor_top_button"] = button_floor_top

    local separator = subheader.add{type="line", direction="vertical"}
    separator.style.margin = {0, 8}
    main_elements.production_box["separator_line"] = separator

    local button_utility_dialog = subheader.add{type="button", caption={"fp.utilities"},
        tooltip={"fp.utility_dialog_tt"}, tags={mod="fp", on_gui_click="open_utility_dialog"},
        style="fp_button_rounded_mini", mouse_button_filter={"left"}}
    main_elements.production_box["utility_dialog_button"] = button_utility_dialog

    subheader.add{type="empty-widget", style="flib_horizontal_pusher"}

    util.raise.build(player, "view_state", subheader)
    main_elements.production_box["view_state_table"] = subheader["table_view_state"]

    local label_instruction = frame_vertical.add{type="label", style="bold_label"}
    label_instruction.style.margin = 20
    main_elements.production_box["instruction_label"] = label_instruction

    local flow_production_table = frame_vertical.add{type="flow", direction="horizontal"}
    main_elements.production_box["production_table_flow"] = flow_production_table

    local button_paste = frame_vertical.add{type="button", caption={"fp.paste_line"}, tooltip={"fp.paste_line_tt"},
        style="fp_button_rounded_mini", tags={mod="fp", on_gui_click="paste_line"}, mouse_button_filter={"left"}}
    button_paste.style.margin = {6, 12}
    main_elements.production_box["paste_button"] = button_paste

    frame_vertical.add{type="empty-widget", style="flib_vertical_pusher"}

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

    local flow_solver = scroll_pane_solver.add{type="flow", direction="horizontal"}
    flow_solver.style.padding = {0, 12, 4, 12}
    flow_solver.style.vertical_align = "center"
    flow_solver.style.horizontal_spacing = 12
    main_elements["solver_flow"] = flow_solver

    refresh_production_box(player)
end


-- ** EVENTS **
local listeners = {}

listeners.gui = {
    on_gui_click = {
        {
            name = "refresh_production",
            timeout = 20,
            handler = (function(player, _, _)
                if DEV_ACTIVE then  -- implicit mod reload for easier development
                    util.gui.reset_player(player)  -- destroys all FP GUIs
                    util.gui.toggle_mod_gui(player)  -- fixes the mod gui button after its been destroyed
                    game.reload_mods()  -- toggle needs to be delayed by a tick since the reload is not instant
                    game.print("Mods reloaded")
                    util.nth_tick.register((game.tick + 1), "interface_toggle", {player_index=player.index})
                else
                    refresh_production(player, nil, nil)
                end
            end)
        },
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
            name = "paste_line",
            handler = paste_line
        },
        {
            name = "switch_matrix_item",
            handler = switch_matrix_item
        }
    }
}

listeners.misc = {
    fp_refresh_production = (function(player, _, _)
        if main_dialog.is_in_focus(player) then refresh_production(player, nil, nil) end
    end),
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
