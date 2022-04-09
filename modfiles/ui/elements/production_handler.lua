production_handler = {}

-- ** LOCAL UTIL **
-- Checks whether the given (internal) prototype can be blueprinted
local function is_entity_blueprintable(proto)
    return (not game.entity_prototypes[proto.name].has_flag("not-blueprintable"))
end

local function handle_done_click(player, tags, _)
    local line = Floor.get(data_util.get("context", player).floor, "Line", tags.line_id)
    local relevant_line = (line.subfloor) and line.subfloor.defining_line or line
    relevant_line.done = not relevant_line.done

    -- Refreshing the whole table here is wasteful, but I don't have good selective refreshing yet
    main_dialog.refresh(player, "production_table")
end

local function handle_line_move_click(player, tags, event)
    local context = data_util.get("context", player)
    local line = Floor.get(context.floor, "Line", tags.line_id)

    local shifting_function = (event.shift) and Floor.shift_to_end or Floor.shift
    local translated_direction = (tags.direction == "up") and "negative" or "positive"

    -- Can't shift second line into the first position on subfloors. Top line is disabled, so no special handling
    if (context.floor.level > 1 and tags.direction == "up" and (line.gui_position == 2 or event.shift)) or
      not shifting_function(context.floor, line, translated_direction) then
        local message = {"fp.error_list_item_cant_be_shifted", {"fp.pl_recipe", 1}, {"fp." .. tags.direction}}
        title_bar.enqueue_message(player, message, "error", 1, true)
      else
        calculation.update(player, context.subfactory)
        main_dialog.refresh(player, "subfactory")
    end
end

local function handle_recipe_click(player, tags, action)
    local context = data_util.get("context", player)
    local line = Floor.get(context.floor, "Line", tags.line_id)
    local relevant_line = (line.subfloor) and line.subfloor.defining_line or line

    if action == "open_subfloor" then
        if relevant_line.recipe.production_type == "consume" then
            title_bar.enqueue_message(player, {"fp.error_no_subfloor_on_byproduct_recipes"}, "error", 1, true)
            return
        end

        local subfloor = line.subfloor
        if subfloor == nil then
            if data_util.get("flags", player).archive_open then
                title_bar.enqueue_message(player, {"fp.error_no_new_subfloors_in_archive"}, "error", 1, true)
                return
            end

            subfloor = Floor.init(line)  -- attaches itself to the given line automatically
            Subfactory.add(context.subfactory, subfloor)
            calculation.update(player, context.subfactory)
        end

        ui_util.context.set_floor(player, subfloor)
        main_dialog.refresh(player, "production_detail")

    elseif action == "toggle" then
        relevant_line.active = not relevant_line.active
        calculation.update(player, context.subfactory)
        main_dialog.refresh(player, "subfactory")

    elseif action == "delete" then
        Floor.remove(context.floor, line)
        calculation.update(player, context.subfactory)
        main_dialog.refresh(player, "subfactory")

    elseif action == "recipebook" then
        data_util.open_in_recipebook(player, "recipe", relevant_line.recipe.proto.name)
    end
end


local function handle_percentage_change(player, tags, event)
    local ui_state = data_util.get("ui_state", player)
    local line = Floor.get(ui_state.context.floor, "Line", tags.line_id)

    local relevant_line = (line.subfloor) and line.subfloor.defining_line or line
    relevant_line.percentage = tonumber(event.element.text) or 100

    ui_state.flags.recalculate_on_subfactory_change = true -- set flag to recalculate if necessary
end

local function handle_percentage_confirmation(player, _, _)
    local ui_state = data_util.get("ui_state", player)
    ui_state.flags.recalculate_on_subfactory_change = false  -- reset this flag as we refresh below
    calculation.update(player, ui_state.context.subfactory)
    main_dialog.refresh(player, "subfactory")
end

local function handle_machine_click(player, tags, action)
    local context = data_util.get("context", player)
    local line = Floor.get(context.floor, "Line", tags.line_id)
    -- I don't need to care about relevant lines here because this only gets called on lines without subfloor

    if action == "edit" then
        modal_dialog.enter(player, {type="machine", modal_data={object=line.machine, line=line}})

    elseif action == "upgrade" or action == "downgrade" then
        if Line.change_machine_by_action(line, player, action) == false then
            local direction_string = (action == "upgrade") and {"fp.upgraded"} or {"fp.downgraded"}
            local message = {"fp.error_object_cant_be_up_downgraded", {"fp.pl_machine", 1}, direction_string}
            title_bar.enqueue_message(player, message, "error", 1, true)
        else
            calculation.update(player, context.subfactory)
            main_dialog.refresh(player, "subfactory")
        end

    elseif action == "reset_to_default" then
        Line.change_machine_to_default(line, player)  -- guaranteed to find something
        line.machine.limit = nil
        line.machine.force_limit = false
        local message = Line.apply_mb_defaults(line, player)

        calculation.update(player, context.subfactory)
        main_dialog.refresh(player, "subfactory")
        if message ~= nil then title_bar.enqueue_message(player, message.text, message.type, 1, true) end

    elseif action == "put_into_cursor" then
        if not is_entity_blueprintable(line.machine.proto) then return end

        local module_list = {}
        for _, module in pairs(ModuleSet.get_in_order(line.machine.module_set)) do
            module_list[module.proto.name] = module.amount
        end

        local blueprint_entity = {
            entity_number = 1,
            name = line.machine.proto.name,
            position = {0, 0},
            items = module_list,
            recipe = line.recipe.proto.name
        }

        data_util.create_cursor_blueprint(player, {blueprint_entity})
        main_dialog.toggle(player)

    elseif action == "recipebook" then
        data_util.open_in_recipebook(player, "entity", line.machine.proto.name)
    end
end


local function handle_beacon_click(player, tags, action)
    local context = data_util.get("context", player)
    local line = Floor.get(context.floor, "Line", tags.line_id)
    -- I don't need to care about relevant lines here because this only gets called on lines without subfloor

    if action == "edit" then
        modal_dialog.enter(player, {type="beacon", modal_data={object=line.beacon, line=line}})

    elseif action == "delete" then
        Line.set_beacon(line, nil)
        calculation.update(player, context.subfactory)
        main_dialog.refresh(player, "subfactory")

    elseif action == "put_into_cursor" then
        if not is_entity_blueprintable(line.beacon.proto) then return end

        local module_list = {}
        for _, module in pairs(ModuleSet.get_in_order(line.beacon.module_set)) do
            module_list[module.proto.name] = module.amount
        end

        local blueprint_entity = {
            entity_number = 1,
            name = line.beacon.proto.name,
            position = {0, 0},
            items = module_list
        }

        data_util.create_cursor_blueprint(player, {blueprint_entity})
        main_dialog.toggle(player)

    elseif action == "recipebook" then
        data_util.open_in_recipebook(player, "entity", line.beacon.proto.name)
    end
end


local function handle_module_click(player, tags, action)
    local context = data_util.get("context", player)
    local line = Floor.get(context.floor, "Line", tags.line_id)
    -- I don't need to care about relevant lines here because this only gets called on lines without subfloor
    local parent_entity = line[tags.parent_type]

    if action == "edit" then
        modal_dialog.enter(player, {type=tags.parent_type, modal_data={object=parent_entity, line=line}})

    elseif action == "delete" then
        local module_set = parent_entity.module_set
        local module = ModuleSet.get(module_set, tags.module_id)
        ModuleSet.remove(module_set, module)

        if parent_entity.class == "Beacon" and module_set.module_count == 0 then
            Line.set_beacon(line, nil)
        end

        calculation.update(player, context.subfactory)
        main_dialog.refresh(player, "subfactory")

    elseif action == "recipebook" then
        local module = ModuleSet.get(parent_entity.module_set, tags.module_id)
        data_util.open_in_recipebook(player, "item", module.proto.name)
    end
end


function GENERIC_HANDLERS.apply_item_options(player, options, action)
    if action == "submit" then
        local ui_state = data_util.get("ui_state", player)
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

        relevant_line.percentage = (relevant_line.percentage * item_amount) / current_amount

        calculation.update(player, ui_state.context.subfactory)
        main_dialog.refresh(player, "subfactory")
    end
end

local function handle_item_click(player, tags, action)
    local context = data_util.get("context", player)
    local line = Floor.get(context.floor, "Line", tags.line_id)
    -- I don't need to care about relevant lines here because this only gets called on lines without subfloor
    local item = Line.get(line, tags.class, tags.item_id)

    if action == "prioritize" then
        if line.Product.count < 2 then
            title_bar.enqueue_message(player, {"fp.warning_no_prioritizing_single_product"}, "warning", 1, true)
        else
            -- Remove the priority_product if the already selected one is clicked
            line.priority_product_proto = (line.priority_product_proto ~= item.proto) and item.proto or nil

            calculation.update(player, context.subfactory)
            main_dialog.refresh(player, "subfactory")
        end

    elseif action == "add_recipe_to_end" or action == "add_recipe_below" then
        local production_type = (tags.class == "Byproduct") and "consume" or "produce"
        local add_after_position = (action == "add_recipe_below") and line.gui_position or nil
        modal_dialog.enter(player, {type="recipe", modal_data={product_proto=item.proto, production_type=production_type, add_after_position=add_after_position}})

    elseif action == "specify_amount" then
        -- Set the view state so that the amount shown in the dialog makes sense
        view_state.select(player, "items_per_timescale", "subfactory")  -- refreshes "subfactory" if necessary

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
        modal_dialog.enter(player, {type="options", modal_data=modal_data})

    elseif action == "recipebook" then
        data_util.open_in_recipebook(player, item.proto.type, item.proto.name)
    end
end

local function handle_fuel_click(player, tags, action)
    local context = data_util.get("context", player)
    local line = Floor.get(context.floor, "Line", tags.line_id)
    -- I don't need to care about relevant lines here because this only gets called on lines without subfloor
    local fuel = line.machine.fuel  -- must exist to be able to get here

    if action == "add_recipe_to_end" or action == "add_recipe_below" then
        modal_dialog.enter(player, {type="recipe", modal_data={product_proto=fuel.proto, production_type="produce",
          add_after_position=((action == "add_recipe_below") and line.gui_position or nil)}})

    elseif action == "change" then  -- fuel is changed through the machine dialog now
        modal_dialog.enter(player, {type="machine", modal_data={object=line.machine, line=line}})

    elseif action == "recipebook" then
        data_util.open_in_recipebook(player, fuel.proto.type, fuel.proto.name)
    end
end


-- ** EVENTS **
production_handler.gui_events = {
    on_gui_click = {
        {
            name = "checkmark_line",
            handler = handle_done_click
        },
        {
            name = "move_line",
            handler = handle_line_move_click
        },
        {
            name = "act_on_line_recipe",
            modifier_actions = {
                open_subfloor = {"left"},  -- does its own archive check
                toggle = {"control-left", {archive_open=false}},
                delete = {"control-right", {archive_open=false}},
                recipebook = {"alt-right", {recipebook=true}}
            },
            timeout = 10,
            handler = handle_recipe_click
        },
        {
            name = "act_on_line_machine",
            modifier_actions = {
                edit = {"right", {archive_open=false}},
                upgrade = {"shift-left", {archive_open=false}},
                downgrade = {"control-left", {archive_open=false}},
                reset_to_default = {"control-right", {archive_open=false}},
                put_into_cursor = {"alt-left", {archive_open=false}},
                recipebook = {"alt-right", {recipebook=true}}
            },
            handler = handle_machine_click
        },
        {
            name = "add_line_beacon",
            handler = (function(player, tags, _)
                local line = Floor.get(data_util.get("context", player).floor, "Line", tags.line_id)
                modal_dialog.enter(player, {type="beacon", modal_data={object=nil, line=line}})
            end)
        },
        {
            name = "act_on_line_beacon",
            modifier_actions = {
                edit = {"right", {archive_open=false}},
                delete = {"control-right", {archive_open=false}},
                put_into_cursor = {"alt-left", {archive_open=false}},
                recipebook = {"alt-right", {recipebook=true}}
            },
            handler = handle_beacon_click
        },
        {
            name = "act_on_line_module",
            modifier_actions = {
                edit = {"right", {archive_open=false}},
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
                recipebook = {"alt-right", {recipebook=true}}
            },
            handler = handle_item_click
        },
        {
            name = "act_on_line_byproduct",
            modifier_actions = {
                add_recipe_to_end = {"left", {archive_open=false, matrix_active=true}},
                add_recipe_below = {"shift-left", {archive_open=false, matrix_active=true}},
                specify_amount = {"right", {archive_open=false, matrix_active=false}},
                recipebook = {"alt-right", {recipebook=true}}
            },
            handler = handle_item_click
        },
        {
            name = "act_on_line_ingredient",
            modifier_actions = {
                add_recipe_to_end = {"left", {archive_open=false}},
                add_recipe_below = {"shift-left", {archive_open=false}},
                specify_amount = {"right", {archive_open=false, matrix_active=false}},
                recipebook = {"alt-right", {recipebook=true}}
            },
            handler = handle_item_click
        },
        {
            name = "act_on_line_fuel",
            modifier_actions = {
                add_recipe_to_end = {"left", {archive_open=false}},
                add_recipe_below = {"shift-left", {archive_open=false}},
                change = {"right", {archive_open=false}},
                recipebook = {"alt-right", {recipebook=true}}
            },
            handler = handle_fuel_click
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
                local floor = data_util.get("context", player).floor
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
