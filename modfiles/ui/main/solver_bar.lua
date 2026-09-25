-- ** LOCAL UTIL **
---@param player LuaPlayer
---@param tags SwitchMatrixItemTags
local function switch_matrix_item(player, tags, _)
    local floor = lib.context.get(player, "Floor")  ---@as Floor

    if tags.status == "unrestricted" then
        for index, item in pairs(floor.gaussian_free_items) do
            if item.type == tags.type and item.name == tags.name then
                table.remove(floor.gaussian_free_items, index)
                break
            end
        end
    else -- "constrained"
        local item_proto = prototyper.util.find("items", tags.name, tags.type)
        table.insert(floor.gaussian_free_items, item_proto)
    end

    solver.update(player)
    lib.gui.run_refresh(player, "production")
end


---@param player LuaPlayer
local function refresh_solver_bar(player)
    local ui_state = lib.globals.ui_state(player)
    if ui_state.main_elements.main_frame == nil then return end
    local solver_frame = ui_state.main_elements.solver_bar.frame
    local solver_flow = ui_state.main_elements.solver_bar.flow
    solver_flow.clear()
    solver_frame.visible = false

    local factory = lib.context.get(player, "Factory")  ---@as Factory?
    if ui_state.districts_view or factory == nil or not factory.valid then return end
    local floor = lib.context.get(player, "Floor")  ---@as Floor

    local label_error = solver_flow.add{type="label", style="fp_label_solver"}  ---@type LuaGuiElement
    if floor.solver_error and floor.solver_error ~= "free_items_unbalanced" then
        label_error.caption = {"fp.error_message", {"fp.info_label", {"fp.solver_error_" .. floor.solver_error}}}
        label_error.tooltip = {"fp.solver_error_" .. floor.solver_error .. "_tt"}
        solver_frame.visible = true
    end

    if factory.archived or floor.solver ~= "gaussian" or floor:count() == 0 then return end

    local free_items = floor.gaussian_free_items  ---@as FPItemPrototype[]
    local num_needed_free_items = floor.linear_dependence_data and floor.linear_dependence_data.num_needed_free_items or 0

    ---@param flow LuaGuiElement
    ---@param status "unrestricted" | "constrained"
    ---@param color "default" | "green"
    ---@param items FPItemPrototype[]
    local function build_unrestricted_item_buttons(flow, status, color, items)
        for _, proto in pairs(items) do
            ---@class SwitchMatrixItemTags
            ---@field status "unrestricted" | "constrained"
            ---@field type string
            ---@field name string
            flow.add{type="sprite-button", sprite=proto.sprite, tooltip={"fp.turn_" .. status, proto.localised_name},
                tags={mod="fp", on_gui_click="switch_matrix_item", status=status, type=proto.type, name=proto.name},
                style="fflib_slot_button_" .. color, mouse_button_filter={"left"}}
        end
    end

    if floor.linear_dependence_data and next(floor.linear_dependence_data.linearly_dependent_free_items) then
        local num_needed_restricted_items = #floor.linear_dependence_data.linearly_dependent_free_items
        local num_items_to_remove = num_needed_restricted_items - num_needed_free_items

        label_error.caption = {"fp.error_message", {"fp.info_label", {"fp.remove_unrestricted_items"}}}
        label_error.tooltip = {"fp.remove_unrestricted_items_tt", num_items_to_remove, {"fp.pl_item", num_items_to_remove}}
        solver_frame.visible = true

        local flow_unrestricted = solver_flow.add{type="flow", direction="horizontal"}
        build_unrestricted_item_buttons(flow_unrestricted, "unrestricted", "default", floor.linear_dependence_data.linearly_dependent_free_items)
    elseif num_needed_free_items ~= 0 then
        local needs_choice = floor.linear_dependence_data and #floor.linear_dependence_data.allowed_free_items > 0 or false

        if needs_choice then
            label_error.caption = {"fp.error_message", {"fp.info_label", {"fp.choose_unrestricted_items"}}}
            label_error.tooltip = {"fp.choose_unrestricted_items_tt", num_needed_free_items,
                {"fp.pl_item", num_needed_free_items}}
        elseif not floor.solver_error then
            label_error.caption = {"fp.info_label", {"fp.unrestricted_items_balanced"}}
            label_error.tooltip = {"fp.unrestricted_items_balanced_tt"}
        end
        solver_frame.visible = true

        local flow_unrestricted = solver_flow.add{type="flow", direction="horizontal"}
        build_unrestricted_item_buttons(flow_unrestricted, "unrestricted", "green", free_items)

        if needs_choice then  ---@cast floor.linear_dependence_data -nil
            local flow_constrained = solver_flow.add{type="flow", direction="horizontal"}
            build_unrestricted_item_buttons(flow_constrained, "constrained", "default", floor.linear_dependence_data.allowed_free_items)
        end
    end
end

---@param player LuaPlayer
local function build_solver_bar(player)
    local main_elements = lib.globals.main_elements(player)
    main_elements.solver_bar = {}

    local parent_frame = main_elements.production_box.vertical_frame
    local frame = parent_frame.add{type="frame", direction="horizontal", style="fp_frame_subfooter", visible=false}
    frame.style.padding = 0
    main_elements.solver_bar["frame"] = frame

    local scroll_pane = frame.add{type="scroll-pane", style="naked_scroll_pane",
        horizontal_scroll_policy="auto", vertical_scroll_policy="never"}
    scroll_pane.style.padding = {2, 12}
    -- Establish the width before layout so a temporary overflow doesn't leave scrollbar height behind
    scroll_pane.style.width = main_elements.flows.right_vertical.style.minimal_width

    local flow = scroll_pane.add{type="flow", direction="horizontal"}
    flow.style.vertical_align = "center"
    flow.style.horizontal_spacing = 12
    main_elements.solver_bar["flow"] = flow

    refresh_solver_bar(player)
end


-- ** EVENTS **
local listeners = {}  ---@type ListenerDefinitions

listeners.gui = {
    on_gui_click = {
        {
            name = "switch_matrix_item",
            handler = switch_matrix_item
        }
    }
}  ---@as GUIListenerDefinition

listeners.player = {
    build_gui_element = function(player, event)
        ---@cast event BuildGUIElementEventData
        if event.trigger == "main_dialog" then build_solver_bar(player) end
    end,
    refresh_gui_element = function(player, event)
        ---@cast event RefreshGUIElementEventData
        local triggers = {solver_bar=true, production_box=true, production=true, factory=true, all=true}
        if triggers[event.trigger] then refresh_solver_bar(player) end
    end
}

return { listeners }
