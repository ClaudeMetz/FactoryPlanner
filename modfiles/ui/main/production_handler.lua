local Floor = require("backend.data.Floor")
local Beacon = require("backend.data.Beacon")
local SimpleItem = require("backend.data.SimpleItem")

-- ** LOCAL UTIL **
---@param player LuaPlayer
---@param tags PlaceLineTags
local function place_line(player, tags, _)
    local ui_state = lib.globals.ui_state(player)
    local held_line = OBJECT_INDEX[ui_state.held_object_id]  ---@as LineObject
    local relative_line = OBJECT_INDEX[tags.line_id]  ---@as LineObject
    local floor = relative_line.parent  ---@as Floor

    floor:move(held_line, relative_line, tags.direction)
    ui_state.held_object_id = nil  -- consume the held object

    solver.update(player)
    lib.gui.run_refresh(player, "production")
end

---@param line Line
---@return Floor
local function convert_line_to_subfloor(line)
    local subfloor = Floor.init(line.parent.level + 1)
    line.parent:replace(line, subfloor)
    line.next, line.previous = nil, nil
    subfloor:insert(line)
    return subfloor
end


-- Handles any line recipe, with or without subfloor
---@param player LuaPlayer
---@param tags ActOnLineObjectRecipe
---@param action string
local function handle_line_recipe_click(player, tags, action)
    local line = OBJECT_INDEX[tags.line_id]  ---@as Line
    local relevant_line = (line.class == "Floor") and line.first or line

    if action == "open_subfloor" then
        local new_context = line  ---@as LineObject
        if line.class == "Line" then
            new_context = convert_line_to_subfloor(line)
            solver.update(player)
        end

        lib.context.set(player, new_context--[[@as ContextObject]])
        lib.gui.run_refresh(player, "production")

    elseif action == "copy" then
        lib.clipboard.copy(player, line)  -- use actual line

    elseif action == "paste" then
        if line.class == "Line" then
            local subfloor = convert_line_to_subfloor(line)
            if not lib.clipboard.paste(player, subfloor) then
                subfloor.parent:replace(subfloor, line)
            end
        else
            lib.clipboard.paste(player, line)
        end

    elseif action == "toggle" then
        relevant_line.active = not relevant_line.active
        solver.update(player)
        lib.gui.run_refresh(player, "production")

    elseif action == "delete" then
        local floor = line.parent
        floor:remove(line, true)

        local selected_floor = lib.context.get(player, "Floor")  ---@as Floor
        if floor.level > selected_floor.level and floor:count() == 1 then
            floor.parent:replace(floor, floor.first--[[@cast -nil]])
        end

        solver.update(player)
        lib.gui.run_refresh(player, "production")

    elseif action == "factoriopedia" then
        local proto = relevant_line.recipe.proto  ---@as FPRecipePrototype
        player.open_factoriopedia_gui(lib.get_factoriopedia_proto(proto))
    end
end

---@param player LuaPlayer
---@param tags ActOnLineMachineTags
---@param action string
local function handle_machine_click(player, tags, action)
    local machine = OBJECT_INDEX[tags.machine_id]  ---@as Machine
    local line = machine.parent

    if action == "pipette" then
        local success = lib.cursor.set_entity(player, line, machine)
        if success then main_dialog.toggle(player) end

    elseif action == "edit" then
        lib.gui.open_dialog(player, {dialog="machine", modal_data={machine_id=machine.id}})

    elseif action == "copy" then
        lib.clipboard.copy(player, machine)

    elseif action == "paste" then
        lib.clipboard.paste(player, machine)

    elseif action == "factoriopedia" then
        player.open_factoriopedia_gui(lib.get_factoriopedia_proto(machine.proto))
    end
end

---@param player LuaPlayer
---@param tags AddModuleTags
---@param event EventData.on_gui_click
local function handle_module_add(player, tags, event)
    local object = OBJECT_INDEX[tags.object_id]  ---@as Machine | Beacon

    if event.shift then  -- paste
        lib.clipboard.paste(player, object)
    else
        if object.class == "Machine" then
            lib.gui.open_dialog(player, {dialog="machine", modal_data={machine_id=object.id}})
        else  -- "Beacon"
            lib.gui.open_dialog(player, {dialog="beacon", modal_data={line_id=object.parent.id}})
        end
    end
end

---@param player LuaPlayer
---@param tags ActOnLineBeaconTags
---@param action string
local function handle_beacon_click(player, tags, action)
    local beacon = OBJECT_INDEX[tags.beacon_id]  ---@as Beacon
    local line = beacon.parent

    if action == "pipette" then
        local success = lib.cursor.set_entity(player, line, beacon)
        if success then main_dialog.toggle(player) end

    elseif action == "edit" then
        lib.gui.open_dialog(player, {dialog="beacon", modal_data={line_id=line.id}})

    elseif action == "copy" then
        lib.clipboard.copy(player, beacon)

    elseif action == "paste" then
        lib.clipboard.paste(player, beacon)

    elseif action == "delete" then
        line:set_beacon(nil)
        solver.update(player)
        lib.gui.run_refresh(player, "production")

    elseif action == "factoriopedia" then
        player.open_factoriopedia_gui(lib.get_factoriopedia_proto(beacon.proto))
    end
end

---@param player LuaPlayer
---@param tags AddLineBeaconTags
---@param event EventData.on_gui_click
local function handle_beacon_add(player, tags, event)
    local line = OBJECT_INDEX[tags.line_id]  ---@as Line

    if event.shift then  -- paste
        local dummy_beacon = Beacon.init(line)
        lib.clipboard.paste(player, dummy_beacon)
    else
        lib.gui.open_dialog(player, {dialog="beacon", modal_data={line_id=line.id}})
    end
end

---@param player LuaPlayer
---@param tags ActOnLineModuleTags
---@param action string
local function handle_module_click(player, tags, action)
    local module = OBJECT_INDEX[tags.module_id]  ---@as Module

    if action == "edit" then
        local line = module.parent.parent.parent
        if module.parent.parent.class == "Machine" then
            lib.gui.open_dialog(player, {dialog="machine", modal_data={machine_id=line.machine.id}})
        else
            lib.gui.open_dialog(player, {dialog="beacon", modal_data={line_id=line.id}})
        end

    elseif action == "copy" then
        lib.clipboard.copy(player, module)

    elseif action == "paste" then
        lib.clipboard.paste(player, module)

    elseif action == "delete" then
        local module_set = module.parent
        module_set:remove(module)

        if module_set.parent.class == "Beacon" and module_set.module_count == 0 then
            module_set.parent.parent:set_beacon(nil)
        end

        module_set:normalize({effects=true})
        solver.update(player)
        lib.gui.run_refresh(player, "production")

    elseif action == "pipette" then
        player.pipette(prototypes.item[module.proto.name], module.quality_proto.name, true)

    elseif action == "factoriopedia" then
        player.open_factoriopedia_gui(lib.get_factoriopedia_proto(module.proto))
    end
end

---@param player LuaPlayer
---@param tags ActOnLineItem
---@param action string
local function handle_item_click(player, tags, action)
    local line = OBJECT_INDEX[tags.line_id]  ---@as LineObject
    local item_list = (tags.flags.catalyst) and line--[[@as Line]].recipe.catalysts or line
    local item = item_list[tags.item_category .. "s"][tags.item_index]

    if action == "prioritize" then  ---@cast line Line
        local consuming = (line.recipe.production_type == "consume")

        local proto = item.proto
        -- Ingredients are kept under their base name, so the temperature needs adding back on
        if consuming and proto.type == "fluid" then
            local item_name = line.recipe:get_name_with_temperature(proto)
            proto = prototyper.util.find("items", item_name, "fluid")  ---@as FPItemPrototype
        end

        -- Remove the priority_item if the already selected one is clicked
        line.recipe.priority_item = (line.recipe.priority_item ~= proto) and proto or nil

        solver.update(player)
        lib.gui.run_refresh(player, "production")

    elseif action == "add_recipe_to_end" or action == "add_recipe_below" then
        local production_type = (tags.item_category == "byproduct") and "consume" or "produce"
        local add_after_line_id = (action == "add_recipe_below") and line.id or nil

        local proto, recipe_id = item.proto, nil
        if production_type == "produce" and proto.type == "fluid" and line.class == "Line" then
            local item_name = line.recipe:get_name_with_temperature(item.proto)
            proto = prototyper.util.find("items", item_name, "fluid")
            -- If a no-temperature fluid is passed, it'll show all compatible temperatures/recipes
            recipe_id = line.recipe.id
        end

        lib.gui.open_dialog(player, {dialog="recipe", modal_data={recipe_id=recipe_id,
            add_after_line_id=add_after_line_id, production_type=production_type,
            category_id=proto.category_id, product_id=proto.id}})

    elseif action == "edit_temperature" then  ---@cast line Line
        lib.gui.open_dialog(player, {dialog="item", modal_data={recipe_id=line.recipe.id,
            category_id=item.proto.category_id, name=item.proto.name}})

    elseif action == "copy" then
        local proto = item.proto
        if item.proto.type == "fluid" and line.class == "Line" then
            local item_name = line--[[@as Line]].recipe:get_name_with_temperature(item.proto)
            proto = prototyper.util.find("items", item_name, "fluid")
        end

        local copyable_item = SimpleItem.init(nil, proto, item.amount)
        lib.clipboard.copy(player, copyable_item)

    elseif action == "paste" then
        lib.clipboard.paste(player, item)

    elseif action == "pipette" then
        lib.cursor.pipette_item(player, item.proto)

    elseif action == "put_into_combinator" then
        lib.cursor.put_into_combinator(player, item.proto, item.amount)

    elseif action == "factoriopedia" then
        player.open_factoriopedia_gui(lib.get_factoriopedia_proto(item.proto))
    end
end

---@param player LuaPlayer
---@param tags ActOnLineFuelTags
---@param action string
local function handle_fuel_click(player, tags, action)
    local fuel = OBJECT_INDEX[tags.fuel_id]  ---@as Fuel
    local line = fuel.parent.parent

    if action == "add_recipe_to_end" or action == "add_recipe_below" then
        local add_after_line_id = (action == "add_recipe_below") and line.id or nil

        local proto = prototyper.util.find("items", fuel.proto.name, fuel.proto.type)
        if fuel.proto.type == "fluid" then
            proto = prototyper.util.find("items", fuel:get_name_with_temperature(), "fluid")
            -- If a no-temperature fluid is passed, it'll show all compatible temperatures/recipes
        end  ---@cast proto FPItemPrototype

        lib.gui.open_dialog(player, {dialog="recipe", modal_data={fuel_id=fuel.id,
            add_after_line_id=add_after_line_id, production_type="produce",
            category_id=proto.category_id, product_id=proto.id}})

    elseif action == "edit_temperature" then
        lib.gui.open_dialog(player, {dialog="item", modal_data={fuel_id=fuel.id,
            category_id=fuel.proto.category_id, name=fuel.proto.name}})

    elseif action == "edit_fuel" then
        lib.gui.open_dialog(player, {dialog="machine", modal_data={machine_id=line.machine.id}})

    elseif action == "copy" then
        lib.clipboard.copy(player, fuel)

    elseif action == "paste" then
        lib.clipboard.paste(player, fuel)

    elseif action == "pipette" then
        lib.cursor.pipette_item(player, fuel.proto--[[@as FPFuelPrototype]])

    elseif action == "put_into_combinator" then
        lib.cursor.put_into_combinator(player, fuel.proto--[[@as FPFuelPrototype]], fuel.amount)

    elseif action == "factoriopedia" then
        player.open_factoriopedia_gui(lib.get_factoriopedia_proto(fuel.proto))
    end
end


-- ** EVENTS **
local listeners = {}  ---@type ListenerDefinitions

---@param flags GUIActionFlags
---@return boolean
local function is_regular_recipe(flags)
    return not flags.defining_recipe
end

---@param flags GUIActionFlags
---@return boolean?
local function show_add_item_recipe(flags)
    return not flags.product and not flags.catalyst
        and (not flags.entity or flags.special)
end

---@param flags GUIActionFlags
---@return boolean?
local function show_item_temperature(flags)
    return flags.fluid and flags.ingredient and not flags.subfloor
end

---@param flags GUIActionFlags
---@return boolean?
local function show_prioritize_item(flags)
    if flags.entity or flags.catalyst or flags.subfloor then return false end
    if flags.consuming then return flags.ingredient end
    return flags.product
end

---@param flags GUIActionFlags
---@return boolean?
local function is_fluid(flags)
    return flags.fluid
end

---@param flags GUIActionFlags
---@return boolean
---@return LocalisedString? warning
local function can_paste_recipe(flags)
    if flags.defining_recipe then return false, {"fp.subfloor_defining_recipe_paste"} end
    return lib.actions.can_edit_factory(flags)
end

---@param flags GUIActionFlags
---@return boolean
---@return LocalisedString? warning
local function can_delete_recipe(flags)
    if flags.defining_recipe then return false, {"fp.subfloor_defining_recipe_delete"} end
    return lib.actions.can_edit_factory(flags)
end

---@param flags GUIActionFlags
---@return boolean
---@return LocalisedString? warning
local function can_open_subfloor(flags)
    if flags.consuming then return false, {"fp.subfloor_consuming_recipe"} end
    if flags.archived and not flags.subfloor then return false, {"fp.subfloor_archived_factory"} end
    return true
end

---@param flags GUIActionFlags
---@return boolean
---@return LocalisedString? warning
local function can_prioritize(flags)
    if flags.archived then return false, {"fp.factory_archived_edit"} end
    if not flags.sequential then return false, {"fp.prioritize_requires_sequential"} end
    return true
end

listeners.gui = {
    on_gui_click = {
        {
            name = "place_line",
            timeout = 10,
            handler = place_line
        },
        {
            name = "pick_up_line",
            handler = function(player, tags, _)
                ---@cast tags PickUpLineTags
                local ui_state = lib.globals.ui_state(player)
                ui_state.held_object_id = (tags.line_id ~= ui_state.held_object_id)
                    and tags.line_id or nil
                lib.gui.run_refresh(player, "production_table")
            end
        },
        {
            name = "act_on_line_recipe",
            actions_table = {
                open_subfloor = {shortcut="left", core=true, show=is_regular_recipe, enable=can_open_subfloor},
                copy = {shortcut="shift-right"},
                paste = {shortcut="shift-left", enable=can_paste_recipe},
                toggle = {shortcut="control-left", enable=lib.actions.can_edit_factory},
                delete = {input="delete", enable=can_delete_recipe},
                factoriopedia = {shortcut="alt-left", enable=lib.actions.can_open_factoriopedia}
            },
            handler = handle_line_recipe_click
        },
        {
            name = "act_on_line_machine",
            actions_table = {
                edit = {shortcut="left", core=true, enable=lib.actions.can_edit_factory},
                copy = {shortcut="shift-right"},
                paste = {shortcut="shift-left", enable=lib.actions.can_edit_factory},
                pipette = {input="pipette", enable=lib.actions.can_pipette},
                factoriopedia = {shortcut="alt-left"}
            },
            handler = handle_machine_click
        },
        {
            name = "add_module",
            handler = handle_module_add
        },
        {
            name = "act_on_line_beacon",
            actions_table = {
                edit = {shortcut="left", core=true, enable=lib.actions.can_edit_factory},
                copy = {shortcut="shift-right"},
                paste = {shortcut="shift-left", enable=lib.actions.can_edit_factory},
                delete = {input="delete", enable=lib.actions.can_edit_factory},
                pipette = {input="pipette", enable=lib.actions.can_pipette},
                factoriopedia = {shortcut="alt-left"}
            },
            handler = handle_beacon_click
        },
        {
            name = "add_line_beacon",
            handler = handle_beacon_add
        },
        {
            name = "act_on_line_module",
            actions_table = {
                edit = {shortcut="left", core=true, enable=lib.actions.can_edit_factory},
                copy = {shortcut="shift-right"},
                paste = {shortcut="shift-left", enable=lib.actions.can_edit_factory},
                delete = {input="delete", enable=lib.actions.can_edit_factory},
                pipette = {input="pipette"},
                factoriopedia = {shortcut="alt-left"}
            },
            handler = handle_module_click
        },
        {
            name = "act_on_line_item",
            actions_table = {
                add_recipe_to_end = {shortcut="left", core=true, show=show_add_item_recipe, enable=lib.actions.can_add_recipe},
                add_recipe_below = {show=show_add_item_recipe, enable=lib.actions.can_add_recipe},
                edit_temperature = {shortcut="control-left", core=true, show=show_item_temperature, enable=lib.actions.can_edit_temperature},
                prioritize = {shortcut="control-right", show=show_prioritize_item, enable=can_prioritize},
                copy = {shortcut="shift-right"},
                paste = {shortcut="shift-left", show=show_item_temperature, enable=lib.actions.can_edit_temperature},
                pipette = {input="pipette", enable=lib.actions.can_pipette},
                put_into_combinator = {input="put_into_combinator", enable=lib.actions.can_put_into_combinator},
                factoriopedia = {shortcut="alt-left", enable=lib.actions.can_open_factoriopedia}
            },
            handler = handle_item_click
        },
        {
            name = "act_on_line_fuel",
            actions_table = {
                add_recipe_to_end = {shortcut="left", core=true, enable=lib.actions.can_add_recipe},
                add_recipe_below = {enable=lib.actions.can_add_recipe},
                edit_temperature = {shortcut="control-left", core=true, show=is_fluid, enable=lib.actions.can_edit_temperature},
                edit_fuel = {enable=lib.actions.can_edit_factory},
                copy = {shortcut="shift-right"},
                paste = {shortcut="shift-left", enable=lib.actions.can_edit_factory},
                pipette = {input="pipette", enable=lib.actions.can_pipette},
                put_into_combinator = {input="put_into_combinator", enable=lib.actions.can_put_into_combinator},
                factoriopedia = {shortcut="alt-left"}
            },
            handler = handle_fuel_click
        }
    },
    on_gui_checked_state_changed = {
        {
            name = "checkmark_line",
            handler = function(_, tags, _)
                ---@cast tags CheckmarkLineTags
                local line = OBJECT_INDEX[tags.line_id]  ---@as Line
                local relevant_line = (line.class == "Floor") and line.first or line
                relevant_line.done = not relevant_line.done
            end
        }
    },
    on_gui_text_changed = {
        {
            name = "change_line_percentage",
            handler = function(player, tags, event)
                ---@cast tags ChangeLinePercentageTags
                ---@cast event EventData.on_gui_text_changed
                local line = OBJECT_INDEX[tags.line_id]  ---@as Line
                local relevant_line = (line.class == "Floor") and line.first or line
                relevant_line.percentage = tonumber(event.element.text) or 100

                -- Re-run solve only after a delay so it doesn't become out of sync
                local factory = lib.context.get(player, "Factory")  ---@as Factory
                factory:schedule_solver_update(game.tick + 300, player)
            end
        },
        {
            name = "line_comment",
            handler = function(_, tags, event)
                ---@cast tags LineCommentTags
                ---@cast event EventData.on_gui_text_changed
                local line = OBJECT_INDEX[tags.line_id]  ---@as Line
                local relevant_line = (line.class == "Floor") and line.first or line
                relevant_line.comment = event.element.text
            end
        }
    },
    on_gui_confirmed = {
        {
            name = "set_line_percentage",
            handler = function(player, _, _)
                solver.update(player)
                lib.gui.run_refresh(player, "production")
            end
        }
    }
}  ---@as GUIListenerDefinition

return { listeners }
