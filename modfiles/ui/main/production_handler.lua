local Floor = require("backend.data.Floor")
local Beacon = require("backend.data.Beacon")

-- ** LOCAL UTIL **
---@param player LuaPlayer
---@param tags MoveLineTags
---@param event EventData.on_gui_click
local function handle_line_move_click(player, tags, event)
    local line = OBJECT_INDEX[tags.line_id]  ---@type Line
    local floor = line.parent

    local spots_to_shift = (event.control) and 5 or ((not event.shift) and 1 or nil)
    if floor.level > 1 and tags.direction == "previous" then
        local spots_to_top = 0
        for previous_line in floor:iterator(nil, line.previous, "previous") do
            if previous_line.id ~= floor.first--[[@cast -nil]].id then
                spots_to_top = spots_to_top + 1
            end
        end
        spots_to_shift = (spots_to_shift == nil) and spots_to_top
            or math.min(spots_to_shift--[[@cast -nil]], spots_to_top)
    end
    floor:shift(line, tags.direction, spots_to_shift)

    solver.update(player)
    lib.gui.run_refresh(player, "production")
end


-- Handles any line recipe, with or without subfloor
---@param player LuaPlayer
---@param tags ActOnLineObjectRecipe
---@param action string
local function handle_line_recipe_click(player, tags, action)
    local line = OBJECT_INDEX[tags.line_id]  ---@as Line
    local relevant_line = (line.class == "Floor") and line.first or line

    if action == "open_subfloor" then
        if relevant_line.recipe.production_type == "consume" then
            lib.messages.raise(player, "error", {"fp.error_no_subfloor_on_byproduct_recipes"}, 1)
            return
        end

        local new_context = line  ---@as LineObject
        if line.class == "Line" then
            if lib.context.get(player, "Factory")--[[@as Factory]].archived then
                lib.messages.raise(player, "error", {"fp.error_no_new_subfloors_in_archive"}, 1)
                return
            end

            local subfloor = Floor.init(line.parent.level + 1)
            line.parent:replace(line, subfloor)
            line.next, line.previous = nil, nil
            subfloor:insert(line)

            new_context = subfloor
            solver.update(player)
        end

        lib.context.set(player, new_context--[[@as ContextObject]])
        lib.gui.run_refresh(player, "production")

    elseif action == "copy" then
        lib.clipboard.copy(player, line)  -- use actual line

    elseif action == "paste" then
        lib.clipboard.paste(player, line)  -- use actual line

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
        player.open_factoriopedia_gui(lib.get_factoriopedia_proto("recipe", proto.name, proto))
    end
end

-- Handles the defining recipe of a floor (ie. first one of a subfloor)
---@param player LuaPlayer
---@param tags ActOnLineObjectRecipe
---@param action string
local function handle_floor_recipe_click(player, tags, action)
    local line = OBJECT_INDEX[tags.line_id]  ---@as Line

    if action == "copy" then
        lib.clipboard.copy(player, line)

    elseif action == "paste" then
        lib.clipboard.paste(player, line)

    elseif action == "toggle" then
        line.active = not line.active
        solver.update(player)
        lib.gui.run_refresh(player, "production")

    elseif action == "factoriopedia" then
        local proto = line.recipe.proto  ---@as FPRecipePrototype
        player.open_factoriopedia_gui(lib.get_factoriopedia_proto("recipe", proto.name, proto))
    end
end

---@param player LuaPlayer
---@param tags ActOnLineMachineTags
---@param action string
local function handle_machine_click(player, tags, action)
    local machine = OBJECT_INDEX[tags.machine_id]  ---@as Machine
    local line = machine.parent

    if action == "add_to_cursor" then
        local success = lib.cursor.set_entity(player, line, machine)
        if success then main_dialog.toggle(player) end

    elseif action == "edit" then
        lib.gui.open_dialog(player, {dialog="machine", modal_data={machine_id=machine.id}})

    elseif action == "copy" then
        lib.clipboard.copy(player, machine)

    elseif action == "paste" then
        lib.clipboard.paste(player, machine)

    elseif action == "factoriopedia" then
        player.open_factoriopedia_gui(prototypes["entity"][machine.proto.name])
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

    if action == "add_to_cursor" then
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
        player.open_factoriopedia_gui(prototypes["entity"][beacon.proto.name])
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

    elseif action == "factoriopedia" then
        player.open_factoriopedia_gui(prototypes["item"][module.proto.name])
    end
end

---@param player LuaPlayer
---@param tags ActOnLineItem
---@param action string
local function handle_item_click(player, tags, action)
    local line = OBJECT_INDEX[tags.line_id]  ---@as LineObject
    local item = line[tags.item_category .. "s"][tags.item_index]

    if action == "prioritize" then
        if line.class ~= "Line" then
            lib.cursor.create_flying_text(player, {"fp.can_only_edit_line_items"})
            return
        elseif #line.products < 2 then
            lib.messages.raise(player, "warning", {"fp.warning_no_prioritizing_single_product"}, 1)
            return
        end  ---@cast line Line

        -- Remove the priority_product if the already selected one is clicked
        line.recipe.priority_product = (line.recipe.priority_product ~= item.proto) and item.proto or nil

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

    elseif action == "edit_temperature" then
        if item.proto.type ~= "fluid" then
            lib.cursor.create_flying_text(player, {"fp.can_only_edit_fluids"})
            return
        elseif line.class ~= "Line" then
            lib.cursor.create_flying_text(player, {"fp.can_only_edit_line_items"})
            return
        end  ---@cast line Line
        if #line.recipe.temperature_data[item.proto.name].applicable_values == 1 then
            lib.cursor.create_flying_text(player, {"fp.can_only_edit_multiple_choices"})
            return
        end

        lib.gui.open_dialog(player, {dialog="item", modal_data={recipe_id=line.recipe.id,
            category_id=item.proto.category_id, name=item.proto.name}})

    elseif action == "copy" then
        local proto = item.proto
        if item.proto.type == "fluid" and line.class == "Line" then
            local item_name = line--[[@as Line]].recipe:get_name_with_temperature(item.proto)
            proto = prototyper.util.find("items", item_name, "fluid")
        end

        local copyable_item = {class="SimpleItem", proto=proto, amount=item.amount}
        lib.clipboard.copy(player, copyable_item)

    elseif action == "paste" then
        if line.class ~= "Line" then return end
        lib.clipboard.paste(player, line, tags)

    elseif action == "add_to_cursor" then
        lib.cursor.handle_item_click(player, item.proto, item.amount)

    elseif action == "factoriopedia" then
        local name = item.proto.name
        if item.proto.temperature then name = item.proto.base_name end
        player.open_factoriopedia_gui(prototypes[item.proto.type][name])
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
        if fuel.proto.type ~= "fluid" then
            lib.cursor.create_flying_text(player, {"fp.can_only_edit_fluids"})
            return
        end

        lib.gui.open_dialog(player, {dialog="item", modal_data={fuel_id=fuel.id,
            category_id=fuel.proto.category_id, name=fuel.proto.name}})

    elseif action == "edit_fuel" then
        lib.gui.open_dialog(player, {dialog="machine", modal_data={machine_id=line.machine.id}})

    elseif action == "copy" then
        lib.clipboard.copy(player, fuel)

    elseif action == "paste" then
        lib.clipboard.paste(player, fuel)

    elseif action == "add_to_cursor" then
        lib.cursor.handle_item_click(player, fuel.proto--[[@as FPFuelPrototype]], fuel.amount)

    elseif action == "factoriopedia" then
        player.open_factoriopedia_gui(prototypes[fuel.proto.type][fuel.proto.name])
    end
end


-- ** EVENTS **
local listeners = {}  ---@type ListenerDefinitions

listeners.gui = {
    on_gui_click = {
        {
            name = "move_line",
            handler = handle_line_move_click
        },
        {
            name = "act_on_line_recipe",
            actions_table = {
                open_subfloor = {shortcut="left", show=true},  -- does its own archive check
                copy = {shortcut="shift-right"},
                paste = {shortcut="shift-left", limitations={archive_open=false}},
                toggle = {shortcut="control-left", limitations={archive_open=false}},
                delete = {shortcut="control-right", limitations={archive_open=false}},
                factoriopedia = {shortcut="alt-left"}
            },
            handler = handle_line_recipe_click
        },
        {
            name = "act_on_floor_recipe",
            actions_table = {
                copy = {shortcut="shift-right"},
                paste = {shortcut="shift-left", limitations={archive_open=false}},
                toggle = {shortcut="control-left", limitations={archive_open=false}},
                factoriopedia = {shortcut="alt-left"}
            },
            handler = handle_floor_recipe_click
        },
        {
            name = "act_on_line_machine",
            actions_table = {
                edit = {shortcut="left", limitations={archive_open=false}, show=true},
                copy = {shortcut="shift-right"},
                paste = {shortcut="shift-left", limitations={archive_open=false}},
                add_to_cursor = {shortcut="alt-right"},
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
                edit = {shortcut="left", limitations={archive_open=false}, show=true},
                copy = {shortcut="shift-right"},
                paste = {shortcut="shift-left", limitations={archive_open=false}},
                delete = {shortcut="control-right", limitations={archive_open=false}},
                add_to_cursor = {shortcut="alt-right"},
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
                edit = {shortcut="left", limitations={archive_open=false}, show=true},
                copy = {shortcut="shift-right"},
                paste = {shortcut="shift-left", limitations={archive_open=false}},
                delete = {shortcut="control-right", limitations={archive_open=false}},
                factoriopedia = {shortcut="alt-left"}
            },
            handler = handle_module_click
        },
        {
            name = "act_on_line_product",
            actions_table = {
                prioritize = {shortcut="left", limitations={archive_open=false, matrix_active=false}, show=true},
                copy = {shortcut="shift-right"},
                add_to_cursor = {shortcut="alt-right"},
                factoriopedia = {shortcut="alt-left"}
            },
            handler = function(player, tags, action)
                ---@cast tags ActOnLineItem
                tags.item_category = "product"
                handle_item_click(player, tags, action--[[@as string]])
            end
        },
        {
            name = "act_on_line_byproduct",
            actions_table = {
                add_recipe_to_end = {shortcut="left", limitations={archive_open=false, matrix_active=true}, show=true},
                add_recipe_below = {limitations={archive_open=false, matrix_active=true}},
                copy = {shortcut="shift-right"},
                add_to_cursor = {shortcut="alt-right"},
                factoriopedia = {shortcut="alt-left"}
            },
            handler = function(player, tags, action)
                ---@cast tags ActOnLineItem
                tags.item_category = "byproduct"
                handle_item_click(player, tags, action--[[@as string]])
            end
        },
        {
            name = "act_on_line_special_byproduct",
            actions_table = {
                add_recipe_to_end = {shortcut="left", limitations={archive_open=false, matrix_active=true}, show=true},
                add_recipe_below = {limitations={archive_open=false, matrix_active=true}}
            },
            handler = function(player, tags, action)
                ---@cast tags ActOnLineItem
                tags.item_category = "byproduct"
                handle_item_click(player, tags, action--[[@as string]])
            end
        },
        {
            name = "act_on_line_ingredient",
            actions_table = {
                add_recipe_to_end = {shortcut="left", limitations={archive_open=false}, show=true},
                add_recipe_below = {limitations={archive_open=false}},
                edit_temperature = {shortcut="control-left", limitations={archive_open=false}, show=true},
                copy = {shortcut="shift-right"},
                paste = {shortcut="shift-left", limitations={archive_open=false}},
                add_to_cursor = {shortcut="alt-right"},
                factoriopedia = {shortcut="alt-left"}
            },
            handler = function(player, tags, action)
                ---@cast tags ActOnLineItem
                tags.item_category = "ingredient"
                handle_item_click(player, tags, action--[[@as string]])
            end
        },
        {
            name = "act_on_line_fuel",
            actions_table = {
                add_recipe_to_end = {shortcut="left", limitations={archive_open=false}, show=true},
                add_recipe_below = {limitations={archive_open=false}},
                edit_temperature = {shortcut="control-left", limitations={archive_open=false}, show=true},
                edit_fuel = {limitations={archive_open=false}},
                copy = {shortcut="shift-right"},
                paste = {shortcut="shift-left", limitations={archive_open=false}},
                add_to_cursor = {shortcut="alt-right"},
                factoriopedia = {shortcut="alt-left"}
            },
            handler = handle_fuel_click
        },
        {
            name = "act_on_line_special_ingredient",
            actions_table = {
                add_recipe_to_end = {shortcut="left", limitations={archive_open=false}, show=true},
                add_recipe_below = {limitations={archive_open=false}}
            },
            handler = function(player, tags, action)
                ---@cast tags ActOnLineItem
                tags.item_category = "ingredient"
                handle_item_click(player, tags, action--[[@as string]])
            end
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
