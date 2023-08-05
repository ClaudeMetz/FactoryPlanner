local Floor = require("backend.data.Floor")

-- ** LOCAL UTIL **
local function handle_line_move_click(player, tags, event)
    local line = OBJECT_INDEX[tags.line_id]
    local spots_to_shift = (event.control) and 5 or ((not event.shift) and 1 or nil)
    line.parent:shift(line, tags.direction, spots_to_shift)

    solver.update(player, util.context.get(player, "Factory"))
    util.raise.refresh(player, "subfactory", nil)
end

local function handle_recipe_click(player, tags, action)
    local factory = util.context.get(player, "Factory")  --[[@as Factory]]
    local line = OBJECT_INDEX[tags.line_id]
    local relevant_line = (line.class == "Floor") and line.first or line

    if action == "open_subfloor" then
        if relevant_line.production_type == "input" then
            util.messages.raise(player, "error", {"fp.error_no_subfloor_on_byproduct_recipes"}, 1)
            return
        end

        local new_context = line
        if line.class == "Line" then
            if factory.archived then
                util.messages.raise(player, "error", {"fp.error_no_new_subfloors_in_archive"}, 1)
                return
            end

            local subfloor = Floor.init(line.parent.level + 1)
            line.parent:replace(line, subfloor)
            line.next, line.previous = nil, nil
            subfloor:insert(line)

            new_context = subfloor
            solver.update(player, factory)
        end

        util.context.set(player, new_context)
        util.raise.refresh(player, "production", nil)

    elseif action == "copy" then
        util.clipboard.copy(player, line)  -- use actual line

    elseif action == "paste" then
        util.clipboard.paste(player, line)  -- use actual line

    elseif action == "toggle" then
        relevant_line.active = not relevant_line.active
        solver.update(player, factory)
        util.raise.refresh(player, "subfactory", nil)

    elseif action == "delete" then
        util.context.remove(player, line)
        line.parent:remove(line)

        solver.update(player, factory)
        util.raise.refresh(player, "subfactory", nil)

    elseif action == "recipebook" then
        util.open_in_recipebook(player, "recipe", relevant_line.recipe_proto.name)
    end
end


local function handle_percentage_change(player, tags, event)
    local line = OBJECT_INDEX[tags.line_id]
    local relevant_line = (line.class == "Floor") and line.first or line
    relevant_line.percentage = tonumber(event.element.text) or 100

    util.globals.ui_state(player).flags.recalculate_on_subfactory_change = true -- set flag to recalculate if necessary
end

local function handle_percentage_confirmation(player, _, _)
    util.globals.ui_state(player).flags.recalculate_on_subfactory_change = false  -- reset this flag as we refresh below
    solver.update(player, util.context.get(player, "Factory"))
    util.raise.refresh(player, "subfactory", nil)
end


local function handle_machine_click(player, tags, action)
    local context = util.globals.context(player)
    local floor = Subfactory.get(context.subfactory, "Floor", tags.floor_id)
    local line = Floor.get(floor, "Line", tags.line_id)
    -- I don't need to care about relevant lines here because this only gets called on lines without subfloor

    if action == "put_into_cursor" then
        local success = util.cursor.set_entity(player, line, line.machine)
        if success then main_dialog.toggle(player) end

    elseif action == "edit" then
        util.raise.open_dialog(player, {dialog="machine", modal_data={floor_id=floor.id, line_id=line.id,
            recipe_name=line.recipe.proto.localised_name}})

    elseif action == "copy" then
        util.clipboard.copy(player, line.machine)

    elseif action == "paste" then
        util.clipboard.paste(player, line.machine)

    elseif action == "reset_to_default" then
        Line.change_machine_to_default(line, player)  -- guaranteed to find something
        line.machine.limit = nil
        line.machine.force_limit = true
        local message = Line.apply_mb_defaults(line, player)

        solver.update(player, context.subfactory)
        util.raise.refresh(player, "subfactory", nil)
        if message ~= nil then util.messages.raise(player, message.category, message.text, 1) end

    elseif action == "recipebook" then
        util.open_in_recipebook(player, "entity", line.machine.proto.name)
    end
end

local function handle_machine_module_add(player, tags, event)
    local context = util.globals.context(player)
    local floor = Subfactory.get(context.subfactory, "Floor", tags.floor_id)
    local line = Floor.get(floor, "Line", tags.line_id)

    if event.shift then  -- paste
        util.clipboard.paste(player, line.machine)
    else
        util.raise.open_dialog(player, {dialog="machine", modal_data={floor_id=floor.id, line_id=line.id,
            recipe_name=line.recipe.proto.localised_name}})
    end
end


local function handle_beacon_click(player, tags, action)
    local context = util.globals.context(player)
    local floor = Subfactory.get(context.subfactory, "Floor", tags.floor_id)
    local line = Floor.get(floor, "Line", tags.line_id)
    -- I don't need to care about relevant lines here because this only gets called on lines without subfloor

    if action == "put_into_cursor" then
        local success = util.cursor.set_entity(player, line, line.beacon)
        if success then main_dialog.toggle(player) end

    elseif action == "edit" then
        util.raise.open_dialog(player, {dialog="beacon", modal_data={floor_id=floor.id, line_id=line.id,
            machine_name=line.machine.proto.localised_name, edit=true}})

    elseif action == "copy" then
        util.clipboard.copy(player, line.beacon)

    elseif action == "paste" then
        util.clipboard.paste(player, line.beacon)

    elseif action == "delete" then
        Line.set_beacon(line, nil)
        solver.update(player, context.subfactory)
        util.raise.refresh(player, "subfactory", nil)

    elseif action == "recipebook" then
        util.open_in_recipebook(player, "entity", line.beacon.proto.name)
    end
end

local function handle_beacon_add(player, tags, event)
    local context = util.globals.context(player)
    local floor = Subfactory.get(context.subfactory, "Floor", tags.floor_id)
    local line = Floor.get(floor, "Line", tags.line_id)

    if event.shift then  -- paste
        -- Use a fake beacon to paste on top of
        local fake_beacon = {parent=line, class="Beacon"}
        util.clipboard.paste(player, fake_beacon)
    else
        util.raise.open_dialog(player, {dialog="beacon", modal_data={floor_id=floor.id, line_id=line.id,
            machine_name=line.machine.proto.localised_name, edit=false}})
    end
end


local function handle_module_click(player, tags, action)
    local context = util.globals.context(player)
    local floor = Subfactory.get(context.subfactory, "Floor", tags.floor_id)
    local line = Floor.get(floor, "Line", tags.line_id)
    -- I don't need to care about relevant lines here because this only gets called on lines without subfloor
    local parent_entity = line[tags.parent_type]
    local module = ModuleSet.get(parent_entity.module_set, tags.module_id)

    if action == "edit" then
        util.raise.open_dialog(player, {dialog=tags.parent_type, modal_data={floor_id=floor.id, line_id=line.id,
            recipe_name=line.recipe.proto.localised_name, machine_name=line.machine.proto.localised_name, edit=true}})

    elseif action == "copy" then
        util.clipboard.copy(player, module)

    elseif action == "paste" then
        util.clipboard.paste(player, module)

    elseif action == "delete" then
        local module_set = parent_entity.module_set
        ModuleSet.remove(module_set, module)

        if parent_entity.class == "Beacon" and module_set.module_count == 0 then
            Line.set_beacon(line, nil)
        end

        ModuleSet.normalize(module_set, {effects=true})
        solver.update(player, context.subfactory)
        util.raise.refresh(player, "subfactory", nil)

    elseif action == "recipebook" then
        util.open_in_recipebook(player, "item", module.proto.name)
    end
end


local function apply_item_options(player, options, action)
    if action == "submit" then
        local ui_state = util.globals.ui_state(player)
        local modal_data = ui_state.modal_data

        local subfactory = ui_state.context.subfactory
        local floor = Subfactory.get(subfactory, "Floor", modal_data.floor_id)
        local line = Floor.get(floor, "Line", modal_data.line_id)
        local item = Line.get(line, modal_data.item_class, modal_data.item_id)
        local relevant_line = (line.subfloor) and line.subfloor.defining_line or line

        local current_amount, item_amount = item.amount, options.item_amount or item.amount
        if item.class ~= "Ingredient" then
            local other_class = (item.class == "Product") and "Byproduct" or "Product"
            local corresponding_item = Line.get_by_type_and_name(relevant_line, other_class,
                item.proto.type, item.proto.name)

            if corresponding_item then  -- Further adjustments if item is both product and byproduct
                -- In either case, we need to consider the sum of both types as the current amount
                current_amount = current_amount + corresponding_item.amount

                -- If it's a byproduct, we want to set its amount to the exact number entered, which this does
                if item.class == "Byproduct" then item_amount = item_amount + corresponding_item.amount end
            end
        end

        relevant_line.percentage = (current_amount == 0) and 100
            or (relevant_line.percentage * item_amount) / current_amount

        solver.update(player, subfactory)
        util.raise.refresh(player, "subfactory", nil)
    end
end

local function handle_item_click(player, tags, action)
    local context = util.globals.context(player)
    local floor = Subfactory.get(context.subfactory, "Floor", tags.floor_id)
    local line = Floor.get(floor, "Line", tags.line_id)
    local item = Line.get(line, tags.class, tags.item_id)

    if action == "prioritize" then
        if line.Product.count < 2 then
            util.messages.raise(player, "warning", {"fp.warning_no_prioritizing_single_product"}, 1)
        else
            -- Remove the priority_product if the already selected one is clicked
            line.priority_product_proto = (line.priority_product_proto ~= item.proto) and item.proto or nil

            solver.update(player, context.subfactory)
            util.raise.refresh(player, "subfactory", nil)
        end

    elseif action == "add_recipe_to_end" or action == "add_recipe_below" then
        local production_type = (tags.class == "Byproduct") and "consume" or "produce"
        local add_after_position = (action == "add_recipe_below") and line.gui_position or nil
        util.raise.open_dialog(player, {dialog="recipe", modal_data={category_id=item.proto.category_id,
            product_id=item.proto.id, floor_id=floor.id, production_type=production_type,
            add_after_position=add_after_position}})

    elseif action == "specify_amount" then
        -- Set the view state so that the amount shown in the dialog makes sense
        view_state.select(player, "items_per_timescale")
        util.raise.refresh(player, "subfactory", nil)

        local type_localised_string = {"fp.pl_" .. tags.class:lower(), 1}
        local produce_consume = (tags.class == "Ingredient") and {"fp.consume"} or {"fp.produce"}

        local modal_data = {
            title = {"fp.options_item_title", type_localised_string},
            text = {"fp.options_item_text", item.proto.localised_name},
            submission_handler_name = "apply_item_options",
            item_class = item.class, item_id = item.id,
            floor_id = floor.id, line_id = line.id,
            fields = {
                {
                    type = "numeric_textfield",
                    name = "item_amount",
                    caption = {"fp.options_item_amount"},
                    tooltip = {"fp.options_item_amount_tt", type_localised_string, produce_consume},
                    text = item.amount,
                    width = 140,
                    focus = true
                }
            }
        }
        util.raise.open_dialog(player, {dialog="options", modal_data=modal_data})

    elseif action == "copy" then
        util.clipboard.copy(player, item)

    elseif action == "put_into_cursor" then
        util.cursor.add_to_item_combinator(player, item.proto, item.amount)

    elseif action == "recipebook" then
        util.open_in_recipebook(player, item.proto.type, item.proto.name)
    end
end

local function handle_fuel_click(player, tags, action)
    local context = util.globals.context(player)
    local floor = Subfactory.get(context.subfactory, "Floor", tags.floor_id)
    local line = Floor.get(floor, "Line", tags.line_id)
    local fuel = line.machine.fuel  -- must exist to be able to get here

    if action == "add_recipe_to_end" or action == "add_recipe_below" then
        local add_after_position = (action == "add_recipe_below") and line.gui_position or nil
        local category = PROTOTYPE_MAPS.items[fuel.proto.type]
        local proto_id = category.members[fuel.proto.name].id
        util.raise.open_dialog(player, {dialog="recipe", modal_data={category_id=category.id,
            product_id=proto_id, floor_id=floor.id, production_type="produce",
            add_after_position=add_after_position}})

    elseif action == "edit" then  -- fuel is changed through the machine dialog
        util.raise.open_dialog(player, {dialog="machine", modal_data={floor_id=floor.id, line_id=line.id,
            recipe_name=line.recipe.proto.localised_name}})

    elseif action == "copy" then
        util.clipboard.copy(player, fuel)

    elseif action == "paste" then
        util.clipboard.paste(player, fuel)

    elseif action == "put_into_cursor" then
        util.cursor.add_to_item_combinator(player, fuel.proto, fuel.amount)

    elseif action == "recipebook" then
        util.open_in_recipebook(player, fuel.proto.type, fuel.proto.name)
    end
end


-- ** EVENTS **
local listeners = {}

listeners.gui = {
    on_gui_click = {
        {
            name = "move_line",
            handler = handle_line_move_click
        },
        {
            name = "act_on_line_recipe",
            modifier_actions = {
                open_subfloor = {"left"},  -- does its own archive check
                copy = {"shift-right"},
                paste = {"shift-left", {archive_open=false}},
                toggle = {"control-left", {archive_open=false}},
                delete = {"control-right", {archive_open=false}},
                recipebook = {"alt-right", {recipebook=true}}
            },
            handler = handle_recipe_click
        },
        {
            name = "act_on_line_machine",
            modifier_actions = {
                edit = {"right", {archive_open=false}},
                copy = {"shift-right"},
                paste = {"shift-left", {archive_open=false}},
                reset_to_default = {"control-right", {archive_open=false}},
                put_into_cursor = {"alt-left"},
                recipebook = {"alt-right", {recipebook=true}}
            },
            handler = handle_machine_click
        },
        {
            name = "add_machine_module",
            handler = handle_machine_module_add
        },
        {
            name = "act_on_line_beacon",
            modifier_actions = {
                edit = {"right", {archive_open=false}},
                copy = {"shift-right"},
                paste = {"shift-left", {archive_open=false}},
                delete = {"control-right", {archive_open=false}},
                put_into_cursor = {"alt-left"},
                recipebook = {"alt-right", {recipebook=true}}
            },
            handler = handle_beacon_click
        },
        {
            name = "add_line_beacon",
            handler = handle_beacon_add
        },
        {
            name = "act_on_line_module",
            modifier_actions = {
                edit = {"right", {archive_open=false}},
                copy = {"shift-right"},
                paste = {"shift-left", {archive_open=false}},
                delete = {"control-right", {archive_open=false}},
                recipebook = {"alt-right", {recipebook=true}}
            },
            handler = handle_module_click
        },
        {
            name = "act_on_line_product",
            modifier_actions = {
                prioritize = {"left", {archive_open=false, matrix_active=false}},
                specify_amount = {"right", {archive_open=false, matrix_active=false}},
                copy = {"shift-right"},
                put_into_cursor = {"alt-left"},
                recipebook = {"alt-right", {recipebook=true}}
            },
            handler = handle_item_click
        },
        {
            name = "act_on_line_byproduct",
            modifier_actions = {
                add_recipe_to_end = {"left", {archive_open=false, matrix_active=true}},
                add_recipe_below = {"control-left", {archive_open=false, matrix_active=true}},
                specify_amount = {"right", {archive_open=false, matrix_active=false}},
                copy = {"shift-right"},
                put_into_cursor = {"alt-left"},
                recipebook = {"alt-right", {recipebook=true}}
            },
            handler = handle_item_click
        },
        {
            name = "act_on_line_ingredient",
            modifier_actions = {
                add_recipe_to_end = {"left", {archive_open=false}},
                add_recipe_below = {"control-left", {archive_open=false}},
                specify_amount = {"right", {archive_open=false, matrix_active=false}},
                copy = {"shift-right"},
                put_into_cursor = {"alt-left"},
                recipebook = {"alt-right", {recipebook=true}}
            },
            handler = handle_item_click
        },
        {
            name = "act_on_line_fuel",
            modifier_actions = {
                add_recipe_to_end = {"left", {archive_open=false}},
                add_recipe_below = {"control-left", {archive_open=false}},
                edit = {"right", {archive_open=false}},
                copy = {"shift-right"},
                paste = {"shift-left", {archive_open=false}},
                put_into_cursor = {"alt-left"},
                recipebook = {"alt-right", {recipebook=true}}
            },
            handler = handle_fuel_click
        }
    },
    on_gui_checked_state_changed = {
        {
            name = "checkmark_line",
            handler = (function(_, tags, _)
                local line = OBJECT_INDEX[tags.line_id]
                local relevant_line = (line.class == "Floor") and line.first or line
                relevant_line.done = not relevant_line.done
            end)
        }
    },
    on_gui_text_changed = {
        {
            name = "line_percentage",
            handler = handle_percentage_change
        },
        {
            name = "line_comment",
            handler = (function(_, tags, event)
                local line = OBJECT_INDEX[tags.line_id]
                local relevant_line = (line.class == "Floor") and line.first or line
                relevant_line.comment = event.element.text
            end)
        }
    },
    on_gui_confirmed = {
        {
            name = "line_percentage",
            handler = handle_percentage_confirmation
        }
    }
}

listeners.global = {
    apply_item_options = apply_item_options
}

return { listeners }
