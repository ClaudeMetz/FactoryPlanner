solver_bar = {}

local ITEM_WEIGHT_LIMIT = 5

---@param player LuaPlayer
---@param proto FPItemPrototype
function solver_bar.add_item_weight(player, proto)
    local floor = lib.context.get(player, "Floor")  ---@as Floor
    local weights = floor.simplex_item_weights

    for _, entry in ipairs(weights) do
        if entry.proto.type == proto.type and entry.proto.name == proto.name then return end
    end
    table.insert(weights, {proto=proto, weight=0})
    lib.gui.run_refresh(player, "solver_bar")
end

-- ** LOCAL UTIL **
---@param player LuaPlayer
---@param tags Tags
---@param action string
local function change_item_weight(player, tags, action)
    local floor = lib.context.get(player, "Floor")  ---@as Floor
    local weights = floor.simplex_item_weights
    local index = tags.item_index --[[@as integer]]
    local entry = weights[index]
    if not entry then return end

    if action == "delete" then
        table.remove(weights, index)
    elseif action == "increase_weight" then
        entry.weight = math.min(entry.weight + 1, ITEM_WEIGHT_LIMIT)
    elseif action == "decrease_weight" then
        entry.weight = math.max(entry.weight - 1, -ITEM_WEIGHT_LIMIT)
    end

    solver.update(player)
    lib.gui.run_refresh(player, "production")
end

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
    ui_state.tooltips.solver_bar = {}
    solver_flow.clear()
    solver_frame.visible = false

    local factory = lib.context.get(player, "Factory")  ---@as Factory?
    if ui_state.districts_view or factory == nil or not factory.valid then return end
    local floor = lib.context.get(player, "Floor")  ---@as Floor

    local label_error = solver_flow.add{type="label", style="fp_label_solver", visible=false}  ---@type LuaGuiElement
    if floor.solver_error and floor.solver_error ~= "free_items_unbalanced" then
        label_error.caption = {"fp.error_message", {"fp.info_label", {"fp.solver_error_" .. floor.solver_error}}}
        label_error.tooltip = {"fp.solver_error_" .. floor.solver_error .. "_tt"}
        label_error.visible = true
        solver_frame.visible = true
    end

    if factory.archived then return end
    if floor.solver == "simplex" then
        local weights = floor.simplex_item_weights
        if not next(weights) then return end

        local label = solver_flow.add{type="label", caption={"fp.info_label", {"fp.modified_weights"}},
            tooltip={"fp.modified_weights_tt"}, style="fp_label_solver"}
        label.style.bottom_padding = 0
        local flow = solver_flow.add{type="flow", direction="horizontal"}
        for index, entry in ipairs(weights) do
            local proto = entry.proto  ---@as FPItemPrototype
            local caption = (entry.weight > 0 and "+" or "") .. entry.weight
            local flags = {
                increase_weight = (entry.weight < ITEM_WEIGHT_LIMIT),
                decrease_weight = (entry.weight > -ITEM_WEIGHT_LIMIT)
            }
            local tags = {mod="fp", on_gui_click="change_item_weight", item_index=index,
                on_gui_hover="set_tooltip", context="solver_bar", flags=flags}
            local button = flow.add{type="sprite-button", sprite=proto.sprite, caption=caption,
                style="fp_sprite-button_item_weight", mouse_button_filter={"left-and-right"},
                raise_hover_events=true, tags=tags}
            ui_state.tooltips.solver_bar[button.index] = {"fp.item_weight_tt", proto.localised_name, caption}
        end
        solver_frame.visible = true
        return
    end

    if floor.solver ~= "gaussian" or floor:count() == 0 then return end
    label_error.visible = true

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

        label_error.caption = {"fp.error_message", {"fp.info_label", {"fp.remove_unrestricted_items", num_items_to_remove, {"fp.pl_item", num_items_to_remove}}}}
        label_error.tooltip = {"fp.remove_unrestricted_items_tt", num_items_to_remove, {"fp.pl_item", num_items_to_remove}}
        solver_frame.visible = true

        local flow_unrestricted = solver_flow.add{type="flow", direction="horizontal"}
        build_unrestricted_item_buttons(flow_unrestricted, "unrestricted", "default", floor.linear_dependence_data.linearly_dependent_free_items)
    elseif num_needed_free_items ~= 0 then
        local needs_choice = floor.linear_dependence_data and #floor.linear_dependence_data.allowed_free_items > 0 or false

        if needs_choice then
            label_error.caption = {"fp.error_message", {"fp.info_label", {"fp.choose_unrestricted_items",
                num_needed_free_items, {"fp.pl_item", num_needed_free_items}}}}
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

---@param flags GUIActionFlags
---@return boolean?
---@return LocalisedString? warning
local function can_increase_weight(flags)
    if not flags.increase_weight then return false, {"fp.item_weight_limit", ITEM_WEIGHT_LIMIT} end
    return true
end

---@param flags GUIActionFlags
---@return boolean?
---@return LocalisedString? warning
local function can_decrease_weight(flags)
    if not flags.decrease_weight then return false, {"fp.item_weight_limit", ITEM_WEIGHT_LIMIT} end
    return true
end

listeners.gui = {
    on_gui_click = {
        {
            name = "change_item_weight",
            actions_table = {
                increase_weight = {shortcut="left", core=true, enable=can_increase_weight},
                decrease_weight = {shortcut="shift-left", core=true, enable=can_decrease_weight},
                delete = {input="delete", core=true}
            },
            handler = change_item_weight
        },
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
