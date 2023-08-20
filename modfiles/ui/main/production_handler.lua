local Floor = require("backend.data.Floor")
local Beacon = require("backend.data.Beacon")

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
    local machine = OBJECT_INDEX[tags.machine_id]
    local line = machine.parent

    if action == "put_into_cursor" then
        local success = util.cursor.set_entity(player, line, machine)
        if success then main_dialog.toggle(player) end

    elseif action == "edit" then
        util.raise.open_dialog(player, {dialog="machine", modal_data={machine_id=machine.id}})

    elseif action == "copy" then
        util.clipboard.copy(player, machine)

    elseif action == "paste" then
        util.clipboard.paste(player, machine)

    elseif action == "reset_to_default" then
        line:change_machine_to_default(player)  -- guaranteed to find something
        machine.limit = nil
        machine.force_limit = true
        local message = line:apply_mb_defaults(player)

        solver.update(player, util.context.get(player, "Factory"))
        util.raise.refresh(player, "subfactory", nil)
        if message ~= nil then util.messages.raise(player, message.category, message.text, 1) end

    elseif action == "recipebook" then
        util.open_in_recipebook(player, "entity", machine.proto.name)
    end
end

local function handle_machine_module_add(player, tags, event)
    local machine = OBJECT_INDEX[tags.machine_id]

    if event.shift then  -- paste
        util.clipboard.paste(player, machine)
    else
        util.raise.open_dialog(player, {dialog="machine", modal_data={machine_id=machine.id}})
    end
end


local function handle_beacon_click(player, tags, action)
    local beacon = OBJECT_INDEX[tags.beacon_id]
    local line = beacon.parent

    if action == "put_into_cursor" then
        local success = util.cursor.set_entity(player, line, beacon)
        if success then main_dialog.toggle(player) end

    elseif action == "edit" then
        util.raise.open_dialog(player, {dialog="beacon", modal_data={line_id=line.id}})

    elseif action == "copy" then
        util.clipboard.copy(player, beacon)

    elseif action == "paste" then
        util.clipboard.paste(player, beacon)

    elseif action == "delete" then
        line:set_beacon(nil)
        solver.update(player, util.context.get(player, "Factory"))
        util.raise.refresh(player, "subfactory", nil)

    elseif action == "recipebook" then
        util.open_in_recipebook(player, "entity", beacon.proto.name)
    end
end

local function handle_beacon_add(player, tags, event)
    local line = OBJECT_INDEX[tags.line_id]

    if event.shift then  -- paste
        local dummy_beacon = Beacon.init({}, line)
        util.clipboard.paste(player, dummy_beacon)
    else
        util.raise.open_dialog(player, {dialog="beacon", modal_data={line_id=line.id}})
    end
end


local function handle_module_click(player, tags, action)
    local module = OBJECT_INDEX[tags.module_id]

    if action == "edit" then
        local line = module.parent.parent.parent
        if module.parent.parent.class == "Machine" then
            util.raise.open_dialog(player, {dialog="machine", modal_data={machine_id=line.machine.id}})
        else
            util.raise.open_dialog(player, {dialog="beacon", modal_data={line_id=line.id}})
        end

    elseif action == "copy" then
        util.clipboard.copy(player, module)

    elseif action == "paste" then
        util.clipboard.paste(player, module)

    elseif action == "delete" then
        local module_set = module.parent
        module_set:remove(module)

        if module_set.parent.class == "Beacon" and module_set.module_count == 0 then
            module_set.parent.parent:set_beacon(nil)
        end

        module_set:normalize({effects=true})
        solver.update(player, util.context.get(player, "Factory"))
        util.raise.refresh(player, "subfactory", nil)

    elseif action == "recipebook" then
        util.open_in_recipebook(player, "item", module.proto.name)
    end
end


local function apply_item_options(player, options, action)
    if action == "submit" then
        local item = OBJECT_INDEX[options.item_id]
        local relevant_line = (item.parent.class == "Floor") and item.parent.first or item.parent
        local item_category = util.globals.modal_data(player).item_category

        local current_amount, item_amount = item.amount, options.item_amount or item.amount
        if item_category ~= "ingredient" then
            local other_category = (item_category == "product") and "byproduct" or "product"
            local corresponding_item = relevant_line[other_category .. "s"]:find({proto=item.proto})

            if corresponding_item then  -- Further adjustments if item is both product and byproduct
                -- In either case, we need to consider the sum of both types as the current amount
                current_amount = current_amount + corresponding_item.amount

                -- If it's a byproduct, we want to set its amount to the exact number entered, which this does
                if item_category == "byproduct" then item_amount = item_amount + corresponding_item.amount end
            end
        end

        relevant_line.percentage = (current_amount == 0) and 100
            or (relevant_line.percentage * item_amount) / current_amount

        solver.update(player, util.context.get(player, "Factory"))
        util.raise.refresh(player, "subfactory", nil)
    end
end

local function handle_item_click(player, tags, action)
    local item = OBJECT_INDEX[tags.item_id]
    local line = item.parent

    if action == "prioritize" then
        if line.Product.count < 2 then
            util.messages.raise(player, "warning", {"fp.warning_no_prioritizing_single_product"}, 1)
        else
            -- Remove the priority_product if the already selected one is clicked
            line.priority_product = (line.priority_product ~= item.proto) and item.proto or nil

            solver.update(player, util.context.get(player, "Factory"))
            util.raise.refresh(player, "subfactory", nil)
        end

    elseif action == "add_recipe_to_end" or action == "add_recipe_below" then
        local production_type = (tags.item_category == "byproduct") and "input" or "output"
        local add_after_line = (action == "add_recipe_below") and line or nil
        util.raise.open_dialog(player, {dialog="recipe", modal_data={add_after_line=add_after_line,
            production_type=production_type, category_id=item.proto.category_id, product_id=item.proto.id}})

    elseif action == "specify_amount" then
        -- Set the view state so that the amount shown in the dialog makes sense
        view_state.select(player, "items_per_timescale")
        util.raise.refresh(player, "subfactory", nil)

        local type_localised_string = {"fp.pl_" .. tags.item_category, 1}
        local produce_consume = (tags.item_category == "ingredient") and {"fp.consume"} or {"fp.produce"}

        local modal_data = {
            title = {"fp.options_item_title", type_localised_string},
            text = {"fp.options_item_text", item.proto.localised_name},
            submission_handler_name = "apply_item_options",
            item_category = tags.item_category,
            item_id = item.id,
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
    local fuel = OBJECT_INDEX[tags.fuel_id]
    local line = fuel.parent.parent

    if action == "add_recipe_to_end" or action == "add_recipe_below" then
        local add_after_line = (action == "add_recipe_below") and line or nil
        local category = PROTOTYPE_MAPS.items[fuel.proto.type]
        local proto_id = category.members[fuel.proto.name].id
        util.raise.open_dialog(player, {dialog="recipe", modal_data={add_after_line=add_after_line,
            production_type="produce", category_id=category.id, product_id=proto_id}})

    elseif action == "edit" then  -- fuel is changed through the machine dialog
        util.raise.open_dialog(player, {dialog="machine", modal_data={machine_id=fuel.parent.id}})

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
