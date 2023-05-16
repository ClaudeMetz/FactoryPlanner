-- ** LOCAL UTIL **
local function handle_line_move_click(player, tags, event)
    local context = data_util.context(player)
    local floor = Subfactory.get(context.subfactory, "Floor", tags.floor_id)
    local line = Floor.get(floor, "Line", tags.line_id)

    local spots_to_shift = (event.control) and 5 or ((not event.shift) and 1 or nil)
    local translated_direction = (tags.direction == "up") and "negative" or "positive"
    local first_position = (floor.level > 1) and 2 or 1
    Floor.shift(floor, line, first_position, translated_direction, spots_to_shift)

    solver.update(player, context.subfactory)
    ui_util.raise_refresh(player, "subfactory", nil)
end

local function handle_recipe_click(player, tags, action)
    local context = data_util.context(player)
    local floor = Subfactory.get(context.subfactory, "Floor", tags.floor_id)
    local line = Floor.get(floor, "Line", tags.line_id)
    local relevant_line = (line.subfloor) and line.subfloor.defining_line or line

    if action == "open_subfloor" then
        if relevant_line.recipe.production_type == "consume" then
            ui_util.messages.raise(player, "error", {"fp.error_no_subfloor_on_byproduct_recipes"}, 1)
            return
        end

        local subfloor = line.subfloor
        if subfloor == nil then
            if data_util.flags(player).archive_open then
                ui_util.messages.raise(player, "error", {"fp.error_no_new_subfloors_in_archive"}, 1)
                return
            end

            subfloor = Floor.init(line)  -- attaches itself to the given line automatically
            Subfactory.add(context.subfactory, subfloor)
            solver.update(player, context.subfactory)
        end

        ui_util.context.set_floor(player, subfloor)
        ui_util.raise_refresh(player, "production", nil)

    elseif action == "copy" then
        ui_util.clipboard.copy(player, line)  -- use actual line

    elseif action == "paste" then
        ui_util.clipboard.paste(player, line)  -- use actual line

    elseif action == "toggle" then
        relevant_line.active = not relevant_line.active
        solver.update(player, context.subfactory)
        ui_util.raise_refresh(player, "subfactory", nil)

    elseif action == "delete" then
        Floor.remove(floor, line)

        local fold_out_subfloors = data_util.preferences(player).fold_out_subfloors
        if fold_out_subfloors and Floor.count(floor, "Line") < 2 then Floor.reset(floor) end

        solver.update(player, context.subfactory)
        ui_util.raise_refresh(player, "subfactory", nil)

    elseif action == "recipebook" then
        ui_util.open_in_recipebook(player, "recipe", relevant_line.recipe.proto.name)
    end
end


local function handle_percentage_change(player, tags, event)
    local ui_state = data_util.ui_state(player)
    local floor = Subfactory.get(ui_state.context.subfactory, "Floor", tags.floor_id)
    local line = Floor.get(floor, "Line", tags.line_id)

    local relevant_line = (line.subfloor) and line.subfloor.defining_line or line
    relevant_line.percentage = tonumber(event.element.text) or 100

    ui_state.flags.recalculate_on_subfactory_change = true -- set flag to recalculate if necessary
end

local function handle_percentage_confirmation(player, _, _)
    local ui_state = data_util.ui_state(player)
    ui_state.flags.recalculate_on_subfactory_change = false  -- reset this flag as we refresh below
    solver.update(player, ui_state.context.subfactory)
    ui_util.raise_refresh(player, "subfactory", nil)
end


local function handle_machine_click(player, tags, action)
    local context = data_util.context(player)
    local floor = Subfactory.get(context.subfactory, "Floor", tags.floor_id)
    local line = Floor.get(floor, "Line", tags.line_id)
    -- I don't need to care about relevant lines here because this only gets called on lines without subfloor

    if action == "put_into_cursor" then
        local success = ui_util.put_entity_into_cursor(player, line, line.machine)
        if success then main_dialog.toggle(player) end

    elseif action == "edit" then
        ui_util.raise_open_dialog(player, {dialog="machine", modal_data={object=line.machine, line=line}})

    elseif action == "copy" then
        ui_util.clipboard.copy(player, line.machine)

    elseif action == "paste" then
        ui_util.clipboard.paste(player, line.machine)

    elseif action == "reset_to_default" then
        Line.change_machine_to_default(line, player)  -- guaranteed to find something
        line.machine.limit = nil
        line.machine.force_limit = true
        local message = Line.apply_mb_defaults(line, player)

        solver.update(player, context.subfactory)
        ui_util.raise_refresh(player, "subfactory", nil)
        if message ~= nil then ui_util.messages.raise(player, message.category, message.text, 1) end

    elseif action == "recipebook" then
        ui_util.open_in_recipebook(player, "entity", line.machine.proto.name)
    end
end

local function handle_machine_module_add(player, tags, event)
    local context = data_util.context(player)
    local floor = Subfactory.get(context.subfactory, "Floor", tags.floor_id)
    local line = Floor.get(floor, "Line", tags.line_id)

    if event.shift then  -- paste
        ui_util.clipboard.paste(player, line.machine)
    else
        ui_util.raise_open_dialog(player, {dialog="machine", modal_data={object=line.machine, line=line}})
    end
end


local function handle_beacon_click(player, tags, action)
    local context = data_util.context(player)
    local floor = Subfactory.get(context.subfactory, "Floor", tags.floor_id)
    local line = Floor.get(floor, "Line", tags.line_id)
    -- I don't need to care about relevant lines here because this only gets called on lines without subfloor

    if action == "put_into_cursor" then
        local success = ui_util.put_entity_into_cursor(player, line, line.beacon)
        if success then main_dialog.toggle(player) end

    elseif action == "edit" then
        ui_util.raise_open_dialog(player, {dialog="beacon", modal_data={object=line.beacon, line=line}})

    elseif action == "copy" then
        ui_util.clipboard.copy(player, line.beacon)

    elseif action == "paste" then
        ui_util.clipboard.paste(player, line.beacon)

    elseif action == "delete" then
        Line.set_beacon(line, nil)
        solver.update(player, context.subfactory)
        ui_util.raise_refresh(player, "subfactory", nil)

    elseif action == "recipebook" then
        ui_util.open_in_recipebook(player, "entity", line.beacon.proto.name)
    end
end

local function handle_beacon_add(player, tags, event)
    local context = data_util.context(player)
    local floor = Subfactory.get(context.subfactory, "Floor", tags.floor_id)
    local line = Floor.get(floor, "Line", tags.line_id)

    if event.shift then  -- paste
        -- Use a fake beacon to paste on top of
        local fake_beacon = {parent=line, class="Beacon"}
        ui_util.clipboard.paste(player, fake_beacon)
    else
        ui_util.raise_open_dialog(player, {dialog="beacon", modal_data={object=nil, line=line}})
    end
end


local function handle_module_click(player, tags, action)
    local context = data_util.context(player)
    local floor = Subfactory.get(context.subfactory, "Floor", tags.floor_id)
    local line = Floor.get(floor, "Line", tags.line_id)
    -- I don't need to care about relevant lines here because this only gets called on lines without subfloor
    local parent_entity = line[tags.parent_type]
    local module = ModuleSet.get(parent_entity.module_set, tags.module_id)

    if action == "edit" then
        ui_util.raise_open_dialog(player, {dialog=tags.parent_type, modal_data={object=parent_entity, line=line}})

    elseif action == "copy" then
        ui_util.clipboard.copy(player, module)

    elseif action == "paste" then
        ui_util.clipboard.paste(player, module)

    elseif action == "delete" then
        local module_set = parent_entity.module_set
        ModuleSet.remove(module_set, module)

        if parent_entity.class == "Beacon" and module_set.module_count == 0 then
            Line.set_beacon(line, nil)
        end

        ModuleSet.normalize(module_set, {effects=true})
        solver.update(player, context.subfactory)
        ui_util.raise_refresh(player, "subfactory", nil)

    elseif action == "recipebook" then
        ui_util.open_in_recipebook(player, "item", module.proto.name)
    end
end


function GENERIC_HANDLERS.apply_item_options(player, options, action)
    if action == "submit" then
        local ui_state = data_util.ui_state(player)
        local item = ui_state.modal_data.object
        local relevant_line = (item.parent.subfloor) and item.parent.subfloor.defining_line or item.parent

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

        solver.update(player, ui_state.context.subfactory)
        ui_util.raise_refresh(player, "subfactory", nil)
    end
end

local function handle_item_click(player, tags, action)
    local context = data_util.context(player)
    local floor = Subfactory.get(context.subfactory, "Floor", tags.floor_id)
    local line = Floor.get(floor, "Line", tags.line_id)
    local item = Line.get(line, tags.class, tags.item_id)

    if action == "prioritize" then
        if line.Product.count < 2 then
            ui_util.messages.raise(player, "warning", {"fp.warning_no_prioritizing_single_product"}, 1)
        else
            -- Remove the priority_product if the already selected one is clicked
            line.priority_product_proto = (line.priority_product_proto ~= item.proto) and item.proto or nil

            solver.update(player, context.subfactory)
            ui_util.raise_refresh(player, "subfactory", nil)
        end

    elseif action == "add_recipe_to_end" or action == "add_recipe_below" then
        local production_type = (tags.class == "Byproduct") and "consume" or "produce"
        local add_after_position = (action == "add_recipe_below") and line.gui_position or nil
        ui_util.raise_open_dialog(player, {dialog="recipe", modal_data={product_proto=item.proto, floor_id=floor.id,
            production_type=production_type, add_after_position=add_after_position}})

    elseif action == "specify_amount" then
        -- Set the view state so that the amount shown in the dialog makes sense
        view_state.select(player, "items_per_timescale")
        ui_util.raise_refresh(player, "subfactory", nil)

        local type_localised_string = {"fp.pl_" .. tags.class:lower(), 1}
        local produce_consume = (tags.class == "Ingredient") and {"fp.consume"} or {"fp.produce"}

        local modal_data = {
            title = {"fp.options_item_title", type_localised_string},
            text = {"fp.options_item_text", item.proto.localised_name},
            submission_handler_name = "apply_item_options",
            object = item,
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
        ui_util.raise_open_dialog(player, {dialog="options", modal_data=modal_data})

    elseif action == "copy" then
        ui_util.clipboard.copy(player, item)

    elseif action == "put_into_cursor" then
        ui_util.add_item_to_cursor_combinator(player, item.proto, item.amount)

    elseif action == "recipebook" then
        ui_util.open_in_recipebook(player, item.proto.type, item.proto.name)
    end
end

local function handle_fuel_click(player, tags, action)
    local context = data_util.context(player)
    local floor = Subfactory.get(context.subfactory, "Floor", tags.floor_id)
    local line = Floor.get(floor, "Line", tags.line_id)
    local fuel = line.machine.fuel  -- must exist to be able to get here

    if action == "add_recipe_to_end" or action == "add_recipe_below" then
        local add_after_position = (action == "add_recipe_below") and line.gui_position or nil
        ui_util.raise_open_dialog(player, {dialog="recipe", modal_data={product_proto=fuel.proto, floor_id=floor.id,
            production_type="produce", add_after_position=add_after_position}})

    elseif action == "edit" then  -- fuel is changed through the machine dialog
        ui_util.raise_open_dialog(player, {dialog="machine", modal_data={object=line.machine, line=line}})

    elseif action == "copy" then
        ui_util.clipboard.copy(player, fuel)

    elseif action == "paste" then
        ui_util.clipboard.paste(player, fuel)

    elseif action == "put_into_cursor" then
        ui_util.add_item_to_cursor_combinator(player, fuel.proto, fuel.amount)

    elseif action == "recipebook" then
        ui_util.open_in_recipebook(player, fuel.proto.type, fuel.proto.name)
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
            handler = (function(player, tags, _)
                local context = data_util.context(player)
                local floor = Subfactory.get(context.subfactory, "Floor", tags.floor_id)
                local line = Floor.get(floor, "Line", tags.line_id)
                local relevant_line = (line.subfloor) and line.subfloor.defining_line or line
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
            handler = (function(player, tags, event)
                local context = data_util.context(player)
                local floor = Subfactory.get(context.subfactory, "Floor", tags.floor_id)
                Floor.get(floor, "Line", tags.line_id).comment = event.element.text
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

return { listeners }
