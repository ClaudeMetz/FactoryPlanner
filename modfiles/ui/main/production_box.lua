local Floor = require("backend.data.Floor")
local Line = require("backend.data.Line")
local TLProduct = require("backend.data.TLProduct")

-- ** LOCAL UTIL **
---@param player LuaPlayer
local function refresh_paste_button(player)
    local main_elements = lib.globals.main_elements(player)
    if not main_elements.production_box then return end
    local factory = lib.context.get(player, "Factory")  ---@as Factory?

    local line_copied = lib.clipboard.check_classes(player, {Floor=true, Line=true})
    main_elements.production_box.paste_button.visible = (factory ~= nil and line_copied) or false
end

---@param player LuaPlayer
---@param destination "up" | "top"
local function change_floor(player, destination)
    if lib.context.ascend_floors(player, destination) then
        lib.gui.run_refresh(player, "production")
    end
end

---@param player LuaPlayer
local function toggle_fold_out_subfloors(player)
    local preferences = lib.globals.preferences(player)
    preferences.fold_out_subfloors = not preferences.fold_out_subfloors
    lib.gui.run_refresh(player, "production_table")
end

---@param player LuaPlayer
local function handle_convert_subfloor(player)
    local floor = lib.context.get(player, "Floor")  ---@as Floor
    local products = #floor.products > 0 and floor.products or floor.first--[[@cast -nil]].products
    local first_product = products[1]  ---@as SimpleItem always one at least
    local factory = factory_list.add_factory(player, nil, first_product.proto)

    for _, floor_product in pairs(products) do  ---@cast floor_product SimpleItem
        local product = TLProduct.init(floor_product.proto)
        product.required_amount = floor_product.amount
        factory:insert(product)
    end

    local floor_copy = floor:pack(false)
    floor_copy.level = 1
    factory.top_floor.parent = nil  -- detach the floor the factory was created with
    factory.top_floor = Floor.unpack(floor_copy)
    factory.top_floor.parent = factory

    factory:validate(player)
    lib.context.set(player, factory.top_floor)

    solver.update(player)
    lib.gui.run_refresh(player, "all")
end

---@param player LuaPlayer
---@param tags ChangeSolverTags
local function handle_solver_change(player, tags, _)
    local factory = lib.context.get(player, "Factory")  ---@as Factory
    if factory.solver == tags.solver then return end

    factory.solver = tags.solver
    factory:clear_solver_cache()

    main_dialog.toggle_districts_view(player, true)
    solver.update(player)
    lib.gui.run_refresh(player, "production")
end

---@param player LuaPlayer
local function repair_factory(player, _, _)
    -- This function can only run is a factory is selected and invalid
    lib.context.get(player, "Factory")--[[@as Factory]]:repair(player)

    main_dialog.toggle_districts_view(player, true)
    solver.update(player)
    lib.gui.run_refresh(player, "all")  -- needs the full refresh to reset factory list buttons
end

---@param player LuaPlayer
local function paste_line(player, _, _)
    local floor = lib.context.get(player, "Floor")  ---@as Floor
    local dummy_line = Line.init()
    lib.clipboard.dummy_paste(player, dummy_line, floor)
end

---@param player LuaPlayer
local function refresh_production_box(player)
    local ui_state = lib.globals.ui_state(player)
    local preferences = lib.globals.preferences(player)
    local factory = lib.context.get(player, "Factory")  ---@as Factory?
    local floor = lib.context.get(player, "Floor")  ---@as Floor

    if ui_state.main_elements.main_frame == nil then return end
    local production_box_elements = ui_state.main_elements.production_box

    local visible = not ui_state.districts_view
    production_box_elements.vertical_frame.visible = visible
    if not visible then return end

    local factory_valid = factory ~= nil and factory.valid
    local any_lines_present = factory_valid and not factory--[[@cast -nil]].archived and floor:count() > 0
    local current_level = (factory_valid) and floor.level or 1

    production_box_elements.level_label.caption = (not factory_valid) and ""
        or {"fp.bold_label", {"", {"fp.level"}, " ", current_level}}

    production_box_elements.floor_up_button.visible = factory_valid
    production_box_elements.floor_up_button.enabled = (current_level > 1)

    production_box_elements.floor_top_button.visible = factory_valid
    production_box_elements.floor_top_button.enabled = (current_level > 1)

    production_box_elements.fold_out_subfloors_button.visible = factory_valid
    production_box_elements.fold_out_subfloors_button.toggled = preferences.fold_out_subfloors

    production_box_elements.convert_subfloor_button.visible = factory_valid
    production_box_elements.convert_subfloor_button.enabled = (current_level > 1)

    production_box_elements.solver_flow.visible = factory_valid
    if factory_valid then  ---@cast factory -nil
        for _, button in pairs(production_box_elements.solver_table.children) do
            button.toggled = (button.tags--[[@as ChangeSolverTags]].solver == factory.solver)
            button.enabled = (not factory.archived)
        end
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
        local last_modset = lib.porter.format_modset_diff(factory--[[@cast -nil]].last_valid_modset)
        production_box_elements.diff_label.tooltip = last_modset
    end

    refresh_paste_button(player)
end

---@class ChangeFloorTags
---@field destination "up" | "top"

---@param player LuaPlayer
local function build_production_box(player)
    local main_elements = lib.globals.main_elements(player)
    main_elements.production_box = {}

    local parent_flow = main_elements.flows.right_vertical
    local frame_vertical = parent_flow.add{type="frame", direction="vertical", style="inside_deep_frame"}
    main_elements.production_box["vertical_frame"] = frame_vertical

    -- Subheader
    local subheader = frame_vertical.add{type="frame", direction="horizontal", style="subheader_frame"}
    subheader.style.top_padding = 4
    local flow_production = subheader.add{type="flow", direction="horizontal"}

    local button_utility_dialog = flow_production.add{type="sprite-button", tooltip={"fp.utility_dialog_tt"},
        tags={mod="fp", on_gui_click="open_utility_dialog"}, sprite="fflib_settings_black", style="tool_button",
        mouse_button_filter={"left"}}
    button_utility_dialog.style.padding = 1
    main_elements.production_box["utility_dialog_button"] = button_utility_dialog

    local label_production = flow_production.add{type="label", caption={"fp.u_production"}, style="frame_title"}
    label_production.style.padding = {0, 8}

    local label_level = flow_production.add{type="label"}
    label_level.style.margin = {5, 6, 0, 4}
    main_elements.production_box["level_label"] = label_level

    local up_tags = {mod="fp", on_gui_click="change_floor", destination="up"}  ---@type ChangeFloorTags
    local button_floor_up = flow_production.add{type="sprite-button", tags=up_tags, sprite="fp_arrow_line_up",
        tooltip={"fp.floor_up_tt"}, style="fp_sprite-button_rounded_icon", mouse_button_filter={"left"}}
    button_floor_up.style.top_margin = 2
    main_elements.production_box["floor_up_button"] = button_floor_up

    local top_tags = {mod="fp", on_gui_click="change_floor", destination="top"}  ---@type ChangeFloorTags
    local button_floor_top = flow_production.add{type="sprite-button", tags=top_tags, sprite="fp_arrow_line_bar_up",
        tooltip={"fp.floor_top_tt"}, style="fp_sprite-button_rounded_icon", mouse_button_filter={"left"}}
    button_floor_top.style.padding = {3, 2, 1, 2}
    button_floor_top.style.top_margin = 2
    main_elements.production_box["floor_top_button"] = button_floor_top

    local button_fold_out_subfloors = flow_production.add{type="sprite-button", sprite="fp_fold_out_subfloors",
        tooltip={"fp.fold_out_subfloors_tt"}, tags={mod="fp", on_gui_click="toggle_fold_out_subfloors"},
        style="fp_sprite-button_rounded_icon", mouse_button_filter={"left"}, auto_toggle=true}
    button_fold_out_subfloors.style.margin = {2, 0, 0, 16}
    main_elements.production_box["fold_out_subfloors_button"] = button_fold_out_subfloors

    local button_convert_subfloor = flow_production.add{type="sprite-button", sprite="utility/export_slot",
        tooltip={"fp.convert_subfloor_tt"}, tags={mod="fp", on_gui_click="convert_subfloor"},
        style="fp_sprite-button_rounded_icon", mouse_button_filter={"left"}}
    button_convert_subfloor.style.top_margin = 2
    main_elements.production_box["convert_subfloor_button"] = button_convert_subfloor

    local button_paste = flow_production.add{type="sprite-button", sprite="utility/import_slot",
        tooltip={"fp.paste_line_tt"}, tags={mod="fp", on_gui_click="paste_line"},
        style="fp_sprite-button_rounded_icon", mouse_button_filter={"left"}}
    button_paste.style.top_margin = 2
    main_elements.production_box["paste_button"] = button_paste

    flow_production.add{type="empty-widget", style="fflib_horizontal_pusher"}

    local flow_solver = flow_production.add{type="flow", direction="horizontal"}
    flow_solver.style.horizontal_spacing = 12
    flow_solver.style.top_margin = 2
    flow_solver.style.vertical_align = "center"
    main_elements.production_box["solver_flow"] = flow_solver
    flow_solver.add{type="label", caption={"fp.info_label", {"fp.solver_choice"}}, style="bold_label",
        tooltip={"fp.solver_choice_tt"}}

    local table_solvers = flow_solver.add{type="table", column_count=#solver.choices}
    table_solvers.style.horizontal_spacing = 0
    main_elements.production_box["solver_table"] = table_solvers

    for _, name in pairs(solver.choices) do
        ---@class ChangeSolverTags
        ---@field solver SolverName
        local tags = {mod="fp", on_gui_click="change_solver", solver=name}
        table_solvers.add{type="button", tags=tags, caption={"fp.solver_" .. name},
            tooltip={"fp.solver_" .. name .. "_tt"}, style="fp_button_push", mouse_button_filter={"left"}}
    end


    -- Main scrollpane
    local scroll_pane_production = frame_vertical.add{type="scroll-pane", style="fflib_naked_scroll_pane_no_padding"}
    scroll_pane_production.style.bottom_padding = 12
    scroll_pane_production.style.extra_bottom_padding_when_activated = -12
    scroll_pane_production.style.extra_right_padding_when_activated = -12
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
    flow_actions.add{type="empty-widget", style="fflib_horizontal_pusher"}
    local button_repair = flow_actions.add{type="button", tags={mod="fp", on_gui_click="repair_factory"},
        caption={"fp.repair_factory"}, mouse_button_filter={"left"}}
    button_repair.style.minimal_width = 0
    button_repair.style.right_margin = 16
    button_repair.style.height = 22
    button_repair.style.padding = {0, 4}

    frame_vertical.add{type="empty-widget", style="fflib_vertical_pusher"}
    frame_vertical.add{type="empty-widget", style="fflib_horizontal_pusher"}

    refresh_production_box(player)
end


-- ** EVENTS **
local listeners = {}  ---@type ListenerDefinitions

listeners.gui = {
    on_gui_click = {
        {
            name = "change_floor",
            handler = function(player, tags, _)
                ---@cast tags ChangeFloorTags
                change_floor(player, tags.destination)
            end
        },
        {
            name = "toggle_fold_out_subfloors",
            handler = toggle_fold_out_subfloors
        },
        {
            name = "convert_subfloor",
            handler = handle_convert_subfloor
        },
        {
            name = "open_utility_dialog",
            handler = function(player, _, _)
                lib.gui.open_dialog(player, {dialog="utility"})
            end
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
            name = "change_solver",
            handler = handle_solver_change
        }
    }
}  ---@as GUIListenerDefinition

listeners.player = {
    fp_up_floor = function(player, _)
        if main_dialog.is_in_focus(player) then change_floor(player, "up") end
    end,
    fp_top_floor = function(player, _)
        if main_dialog.is_in_focus(player) then change_floor(player, "top") end
    end,
    fp_toggle_fold_out_subfloors = function(player, _)
        if main_dialog.is_in_focus(player) then toggle_fold_out_subfloors(player) end
    end,

    build_gui_element = function(player, event)
        ---@cast event BuildGUIElementEventData
        if event.trigger == "main_dialog" then
            build_production_box(player)
        end
    end,
    refresh_gui_element = function(player, event)
        ---@cast event RefreshGUIElementEventData
        local triggers = {production_box=true, production=true, factory=true, all=true}
        if triggers[event.trigger] then refresh_production_box(player)
        elseif event.trigger == "paste_button" then refresh_paste_button(player) end
    end
}

return { listeners }
