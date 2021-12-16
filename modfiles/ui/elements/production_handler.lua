production_handler = {}

-- ** LOCAL UTIL **
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


local function compile_machine_chooser_buttons(player, line, applicable_prototypes)
    local round_button_numbers = data_util.get("preferences", player).round_button_numbers
    local timescale = data_util.get("context", player).subfactory.timescale

    local category_id = global.all_machines.map[line.recipe.proto.category]
    local default_proto = prototyper.defaults.get(player, "machines", category_id)
    local current_proto = line.machine.proto

    local button_definitions = {}
    for _, machine_proto in ipairs(applicable_prototypes) do
        -- Need to get total effects here to include mining productivity
        local crafts_per_tick = calculation.util.determine_crafts_per_tick(machine_proto,
          line.recipe.proto, Line.get_total_effects(line, player))
        local machine_count = calculation.util.determine_machine_count(crafts_per_tick,
          line.uncapped_production_ratio, timescale, machine_proto.launch_sequence_time)

        local button_number = (round_button_numbers) and math.ceil(machine_count) or machine_count

        -- Have to do this stupid crap because localisation plurals only work on integers
        local formatted_number = ui_util.format_number(machine_count, 4)
        local plural_parameter = (formatted_number == "1") and 1 or 2
        local amount_line = {"fp.two_word_title", formatted_number, {"fp.pl_machine", plural_parameter}}

        local definition = {
            element_id = machine_proto.id,
            sprite = machine_proto.sprite,
            button_number = button_number,
            localised_name = machine_proto.localised_name,
            amount_line = amount_line,
            tooltip_appendage = data_util.get_attributes("machines", machine_proto),
            selected = (current_proto.id == machine_proto.id),
            preferred = (default_proto.id == machine_proto.id)
        }

        table.insert(button_definitions, definition)
    end

    return button_definitions
end

function GENERIC_HANDLERS.apply_machine_choice(player, machine_id, event)
    local ui_state = data_util.get("ui_state", player)
    local machine = ui_state.modal_data.object

    local machine_category_id = global.all_machines.map[machine.proto.category]
    local machine_proto = global.all_machines.categories[machine_category_id].machines[tonumber(machine_id)]
    Line.change_machine(machine.parent, player, machine_proto, nil)

    -- Optionally adjust the preferred prototype
    if event.shift then prototyper.defaults.set(player, "machines", machine_proto.id, machine_category_id) end

    calculation.update(player, ui_state.context.subfactory)
    main_dialog.refresh(player, "subfactory")
end

function GENERIC_HANDLERS.handle_machine_limit_change(modal_data, element)
    local switch = modal_data.modal_elements["force_limit"]
    local machine_limit = tonumber(element.text)

    -- If it goes from empty to filled, reset a possible previous switch state
    if modal_data.previous_limit == nil and modal_data.previous_switch_state then
        switch.switch_state = modal_data.previous_switch_state
    -- If it goes from filled to empty, save the switch state end set it to be disabled
    elseif machine_limit == nil then
        modal_data.previous_switch_state = switch.switch_state
        switch.switch_state = "right"
    end

    switch.enabled = (machine_limit ~= nil)  -- The switch only makes sense if you have a machine limit
    modal_data.previous_limit = machine_limit  -- Record the previous limit to know how it changes
end

function GENERIC_HANDLERS.apply_machine_options(player, options, action)
    if action == "submit" then
        local ui_state = data_util.get("ui_state", player)
        local machine = ui_state.modal_data.object

        if options.machine_limit == nil then options.force_limit = false end
        machine.limit, machine.force_limit = options.machine_limit, options.force_limit

        calculation.update(player, ui_state.context.subfactory)
        main_dialog.refresh(player, "subfactory")
    end
end

local function handle_machine_click(player, tags, action)
    local context = data_util.get("context", player)
    local line = Floor.get(context.floor, "Line", tags.line_id)
    -- I don't need to care about relevant lines here because this only gets called on lines without subfloor

    if action == "change" then
        local machine_category_id = global.all_machines.map[line.machine.proto.category]
        local category_prototypes = global.all_machines.categories[machine_category_id].machines

        local applicable_prototypes = {}  -- determine whether there's more than one machine for this recipe
        for _, machine_proto in ipairs(category_prototypes) do
            if Line.is_machine_applicable(line, machine_proto) then
                table.insert(applicable_prototypes, machine_proto)
            end
        end

        if #applicable_prototypes <= 1 then  -- changing machines only makes sense if there is something to change to
            title_bar.enqueue_message(player, {"fp.warning_no_other_machine_choice"}, "warning", 1, true)
        else
            local modal_data = {
                title = {"fp.pl_machine", 1},
                text = {"fp.chooser_machine", line.recipe.proto.localised_name},
                text_tooltip = {"fp.chooser_machine_tt"},
                click_handler_name = "apply_machine_choice",
                button_definitions = compile_machine_chooser_buttons(player, line, applicable_prototypes),
                object = line.machine
            }
            modal_dialog.enter(player, {type="chooser", modal_data=modal_data})
        end

    elseif action == "set_limit" then
        local modal_data = {
            title = {"fp.options_machine_title"},
            text = {"fp.options_machine_text", line.machine.proto.localised_name},
            submission_handler_name = "apply_machine_options",
            object = line.machine,
            fields = {
                {
                    type = "numeric_textfield",
                    name = "machine_limit",
                    change_handler_name = "handle_machine_limit_change",
                    caption = {"fp.options_machine_limit"},
                    tooltip = {"fp.options_machine_limit_tt"},
                    text = line.machine.limit,  -- can be nil
                    focus = true
                },
                {
                    type = "on_off_switch",
                    name = "force_limit",
                    caption = {"fp.options_machine_force_limit"},
                    tooltip = {"fp.options_machine_force_limit_tt"},
                    state = line.machine.force_limit or false
                }
            }
        }
        modal_dialog.enter(player, {type="options", modal_data=modal_data})

    elseif action == "upgrade" or action == "downgrade" then
        if Line.change_machine(line, player, nil, action) == false then
            local direction_string = (action == "upgrade") and {"fp.upgraded"} or {"fp.downgraded"}
            local message = {"fp.error_object_cant_be_up_downgraded", {"fp.pl_machine", 1}, direction_string}
            title_bar.enqueue_message(player, message, "error", 1, true)
        else
            calculation.update(player, context.subfactory)
            main_dialog.refresh(player, "subfactory")
        end

    elseif action == "reset_to_default" then
        Line.change_machine(line, player, nil, nil)  -- guaranteed to find something
        line.machine.limit = nil
        line.machine.force_limit = false

        calculation.update(player, context.subfactory)
        main_dialog.refresh(player, "subfactory")

    elseif action == "put_into_cursor" then
        local module_list = {}
        for _, module in pairs(Machine.get_in_order(line.machine, "Module")) do
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
    end
end


local function handle_module_click(player, tags, action)
    local context = data_util.get("context", player)
    local line = Floor.get(context.floor, "Line", tags.line_id)
    -- I don't need to care about relevant lines here because this only gets called on lines without subfloor
    local module = Machine.get(line.machine, "Module", tags.module_id)

    if action == "edit" then
        modal_dialog.enter(player, {type="module", modal_data={object=module, machine=line.machine}})

    elseif action == "delete" then
        Machine.remove(line.machine, module)
        calculation.update(player, context.subfactory)
        main_dialog.refresh(player, "subfactory")
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
        local module_list = {}
        for _, module in pairs(Beacon.get_in_order(line.beacon, "Module")) do
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


local function compile_fuel_chooser_buttons(player, line, applicable_prototypes)
    local ui_state = data_util.get("ui_state", player)
    local timescale = ui_state.context.subfactory.timescale

    local view_state_metadata = view_state.generate_metadata(player, ui_state.context.subfactory, 4, true)
    local current_proto = line.machine.fuel.proto
    local button_definitions = {}

    local energy_consumption = calculation.util.determine_energy_consumption(line.machine.proto, line.machine.count,
      line.total_effects)  -- don't care about mining productivity in this case, only the consumption-effect

    for _, fuel_proto in pairs(applicable_prototypes) do
        local raw_fuel_amount = calculation.util.determine_fuel_amount(energy_consumption, line.machine.proto.burner,
          fuel_proto.fuel_value, timescale)
        local amount, number_tooltip = view_state_metadata.processor(view_state_metadata, raw_fuel_amount,
          fuel_proto, line.machine.count)  -- Raw processor call because we only have a prototype, no object

        local category_id = global.all_fuels.map[fuel_proto.category]
        local definition = {
            element_id = category_id .. "_" .. fuel_proto.id,
            sprite = fuel_proto.sprite,
            button_number = amount,
            localised_name = fuel_proto.localised_name,
            amount_line = number_tooltip or "",
            tooltip_appendage = data_util.get_attributes("fuels", fuel_proto),
            selected = (current_proto.category == fuel_proto.category and current_proto.id == fuel_proto.id)
        }
        table.insert(button_definitions, definition)
    end

    return button_definitions
end

function GENERIC_HANDLERS.apply_fuel_choice(player, new_fuel_id_string, _)
    local ui_state = data_util.get("ui_state", player)

    local split_string = split_string(new_fuel_id_string, "_")
    local new_fuel_proto = global.all_fuels.categories[split_string[1]].fuels[split_string[2]]

    ui_state.modal_data.object.proto = new_fuel_proto
    calculation.update(player, ui_state.context.subfactory)
    main_dialog.refresh(player, "subfactory")
end

local function handle_fuel_click(player, tags, action)
    local context = data_util.get("context", player)
    local line = Floor.get(context.floor, "Line", tags.line_id)
    -- I don't need to care about relevant lines here because this only gets called on lines without subfloor
    local fuel = line.machine.fuel  -- must exist to be able to get here

    if action == "add_recipe_to_end" or action == "add_recipe_below" then
        modal_dialog.enter(player, {type="recipe", modal_data={product_proto=fuel.proto, production_type="produce",
          add_after_position=((action == "add_recipe_below") and line.gui_position or nil)}})

    elseif action == "change" then
        local applicable_prototypes = {}
        -- Applicable fuels come from all categories that this burner supports
        for category_name, _ in pairs(line.machine.proto.burner.categories) do
            local category_id = global.all_fuels.map[category_name]
            if category_id ~= nil then
                for _, fuel_proto in pairs(global.all_fuels.categories[category_id].fuels) do
                    table.insert(applicable_prototypes, fuel_proto)
                end
            end
        end

        local modal_data = {
            title = {"fp.pl_fuel", 1},
            text = {"fp.chooser_fuel", line.machine.proto.localised_name},
            click_handler_name = "apply_fuel_choice",
            button_definitions = compile_fuel_chooser_buttons(player, line, applicable_prototypes),
            object = fuel
        }
        modal_dialog.enter(player, {type="chooser", modal_data=modal_data})

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
                change = {"left", {archive_open=false}},
                set_limit = {"right", {archive_open=false, matrix_active=false}},
                upgrade = {"shift-left", {archive_open=false}},
                downgrade = {"control-left", {archive_open=false}},
                reset_to_default = {"control-right", {archive_open=false}},
                put_into_cursor = {"alt-left", {archive_open=false}}
            },
            handler = handle_machine_click
        },
        {
            name = "add_line_module",
            handler = (function(player, tags, _)
                local line = Floor.get(data_util.get("context", player).floor, "Line", tags.line_id)
                modal_dialog.enter(player, {type="module", modal_data={object=nil, machine=line.machine}})
            end)
        },
        {
            name = "act_on_line_module",
            modifier_actions = {
                edit = {"right", {archive_open=false}},
                delete = {"control-right", {archive_open=false}}
            },
            handler = handle_module_click
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
                put_into_cursor = {"alt-left", {archive_open=false}}
            },
            handler = handle_beacon_click
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
