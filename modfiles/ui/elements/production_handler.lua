production_handler = {}

-- ** LOCAL UTIL **
-- Fills the cursor with a blueprint for the given entity, which is either a machine or a beacon
local function set_cursor_blueprint(player, entity_name, module_list, recipe_name)
    local script_inventory = game.create_inventory(1)
    local blank_slot = script_inventory[1]

    blank_slot.set_stack{name="fp_cursor_blueprint"}
    blank_slot.set_blueprint_entities{{entity_number=1, name=entity_name, position={0, 0},
      items=module_list, recipe=recipe_name}}
    player.add_to_clipboard(blank_slot)
    player.activate_paste()
    script_inventory.destroy()

    main_dialog.toggle(player)
end


local function handle_toggle_click(player, checkbox, metadata)
    local line_id = tonumber(string.match(checkbox.name, "%d+"))
    local context = data_util.get("context", player)
    local line = Floor.get(context.floor, "Line", line_id)

    local relevant_line = (line.subfloor) and line.subfloor.defining_line or line

    -- Simple clicking just sets relevant line state and alt-clicking inverts states of all lines
    if not metadata.alt then
        relevant_line.active = checkbox.state
    else
        -- Check if there is an inactive line in the floor
        local has_inactive_lines = false;
        for _, current_line in ipairs(Floor.get_in_order(context.floor, "Line")) do
            local current_relevant_line = (current_line.subfloor) and current_line.subfloor.defining_line or current_line
            if not current_relevant_line.active then
                has_inactive_lines = true
                break
            end
        end

        -- Set new checkbox states
        local new_active_state = has_inactive_lines and relevant_line.active
        for _, current_line in ipairs(Floor.get_in_order(context.floor, "Line")) do
            local current_relevant_line = (current_line.subfloor) and current_line.subfloor.defining_line or current_line
            current_relevant_line.active = new_active_state
        end
        relevant_line.active = true
    end

    calculation.update(player, context.subfactory)
    main_dialog.refresh(player, "subfactory")
end

local function handle_recipe_click(player, button, metadata)
    local line_id = tonumber(string.match(button.name, "%d+"))
    local context = data_util.get("context", player)
    local line = Floor.get(context.floor, "Line", line_id)

    if metadata.direction then  -- Shifts line in the given direction
        if not ui_util.check_archive_status(player) then return end

        local shifting_function = (metadata.alt) and Floor.shift_to_end or Floor.shift
        -- Can't shift second line into the first position on subfloors. Top line is disabled, so no special handling
        if not (metadata.direction == "negative" and context.floor.level > 1 and line.gui_position == 2)
          and shifting_function(context.floor, line, metadata.direction) then
            calculation.update(player, context.subfactory)
            main_dialog.refresh(player, "subfactory")
        else
            local direction_string = (metadata.direction == "negative") and {"fp.up"} or {"fp.down"}
            local message = {"fp.error_list_item_cant_be_shifted", {"fp.pl_recipe", 1}, direction_string}
            title_bar.enqueue_message(player, message, "error", 1, true)
        end

    elseif metadata.alt then
        local relevant_line = (line.subfloor) and line.subfloor.defining_line or line
        data_util.execute_alt_action(player, "show_recipe",
          {recipe=relevant_line.recipe.proto, line_products=Line.get_in_order(line, "Product")})

    elseif metadata.click == "left" then  -- Attaches a subfloor to this line
        if not ui_util.check_archive_status(player) then return end

        local subfloor = line.subfloor
        if not subfloor and line.recipe.production_type == "consume" then
            title_bar.enqueue_message(player, {"fp.error_no_subfloor_on_byproduct_recipes"}, "error", 1, true)
        else
            if subfloor == nil then
                subfloor = Floor.init(line)  -- attaches itself to the given line automatically
                Subfactory.add(context.subfactory, subfloor)
                calculation.update(player, context.subfactory)
            end

            ui_util.context.set_floor(player, subfloor)
            main_dialog.refresh(player, "production_detail")
        end

    elseif metadata.action == "delete" then  -- removes this line, including subfloor(s)
        if not ui_util.check_archive_status(player) then return end

        Floor.remove(context.floor, line)
        calculation.update(player, context.subfactory)
        main_dialog.refresh(player, "subfactory")
    end
end


local function handle_percentage_change(player, textfield)
    local line_id = tonumber(string.match(textfield.name, "%d+"))
    local ui_state = data_util.get("ui_state", player)
    local line = Floor.get(ui_state.context.floor, "Line", line_id)

    local relevant_line = (line.subfloor) and line.subfloor.defining_line or line
    relevant_line.percentage = tonumber(textfield.text) or 0

    ui_state.flags.recalculate_on_subfactory_change = true -- set flag to recalculate if necessary
end

local function handle_percentage_confirmation(player, textfield)
    local line_id = tonumber(string.match(textfield.name, "%d+"))
    local textfield_name = textfield.name  -- get it here before it becomes invalid
    local ui_state = data_util.get("ui_state", player)

    ui_state.flags.recalculate_on_subfactory_change = false  -- reset this flag as we refresh
    calculation.update(player, ui_state.context.subfactory)
    main_dialog.refresh(player, "subfactory")

    ui_state.main_elements.production_table.table["flow_percentage_" .. line_id][textfield_name].focus()
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

local function apply_machine_choice(player, machine_id, metadata)
    local ui_state = data_util.get("ui_state", player)
    local machine = ui_state.modal_data.object

    local machine_category_id = global.all_machines.map[machine.proto.category]
    local machine_proto = global.all_machines.categories[machine_category_id].machines[tonumber(machine_id)]
    Line.change_machine(machine.parent, player, machine_proto, nil)

    -- Optionally adjust the preferred prototype
    if metadata.alt then prototyper.defaults.set(player, "machines", machine_proto.id, machine_category_id) end

    calculation.update(player, ui_state.context.subfactory)
    main_dialog.refresh(player, "subfactory")
end

local function machine_limit_change(modal_data, textfield)
    local switch = modal_data.modal_elements["fp_switch_on_off_options_hard_limit"]
    local machine_limit = tonumber(textfield.text)

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

local function apply_machine_options(player, options, action)
    if action == "submit" then
        local ui_state = data_util.get("ui_state", player)
        local machine = ui_state.modal_data.object

        if options.machine_limit == nil then options.hard_limit = false end
        machine.limit, machine.hard_limit = options.machine_limit, options.hard_limit

        calculation.update(player, ui_state.context.subfactory)
        main_dialog.refresh(player, "subfactory")
    end
end

local function handle_machine_click(player, button, metadata)
    if not ui_util.check_archive_status(player) then return end

    local line_id = tonumber(string.match(button.name, "%d+"))
    local context = data_util.get("context", player)
    local line = Floor.get(context.floor, "Line", line_id)
    -- I don't need to care about relevant lines here because this only gets called on lines without subfloor

    if metadata.direction then
        local success = Line.change_machine(line, player, nil, metadata.direction)

        if not success then
            title_bar.refresh_message(player)
        else
            calculation.update(player, context.subfactory)
            main_dialog.refresh(player, "subfactory")
        end

    elseif metadata.alt then
        if metadata.click == "right" then  -- resets this machine to its default state
            Line.change_machine(line, player, nil, nil)
            line.machine.limit = nil
            line.machine.hard_limit = false

            calculation.update(player, context.subfactory)
            main_dialog.refresh(player, "subfactory")

        elseif metadata.click == "left" then
            local module_list = {}
            for _, module in pairs(Machine.get_in_order(line.machine, "Module")) do
                module_list[module.proto.name] = module.amount
            end

            set_cursor_blueprint(player, line.machine.proto.name, module_list, line.recipe.proto.name)
        end

    elseif metadata.click == "left" then
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
                click_handler = apply_machine_choice,
                button_definitions = compile_machine_chooser_buttons(player, line, applicable_prototypes),
                object = line.machine
            }
            modal_dialog.enter(player, {type="chooser", modal_data=modal_data})
        end

    elseif metadata.click == "right" and context.subfactory.matrix_free_items == nil then
        local modal_data = {
            title = {"fp.options_machine_title"},
            text = {"fp.options_machine_text", line.machine.proto.localised_name},
            submission_handler = apply_machine_options,
            object = line.machine,
            fields = {
                {
                    type = "numeric_textfield",
                    name = "machine_limit",
                    change_handler = machine_limit_change,
                    caption = {"fp.options_machine_limit"},
                    tooltip = {"fp.options_machine_limit_tt"},
                    text = line.machine.limit,  -- can be nil
                    focus = true
                },
                {
                    type = "on_off_switch",
                    name = "hard_limit",
                    caption = {"fp.options_machine_hard_limit"},
                    tooltip = {"fp.options_machine_hard_limit_tt"},
                    state = line.machine.hard_limit or false
                }
            }
        }
        modal_dialog.enter(player, {type="options", modal_data=modal_data})
    end
end


local function handle_module_click(player, button, metadata)
    if not ui_util.check_archive_status(player) then return end
    if metadata.alt then return end  -- not implemented for modules

    local split_string = split_string(button.name, "_")
    local context = data_util.get("context", player)

    local line = Floor.get(context.floor, "Line", split_string[6])
    -- I don't need to care about relevant lines here because this only gets called on lines without subfloor
    local module = Machine.get(line.machine, "Module", split_string[7])

    if metadata.click == "left" or metadata.action == "edit" then
        modal_dialog.enter(player, {type="module", modal_data={object=module, machine=line.machine}})

    elseif metadata.action == "delete" then
        Machine.remove(line.machine, module)
        calculation.update(player, context.subfactory)
        main_dialog.refresh(player, "subfactory")
    end
end


local function handle_beacon_click(player, button, metadata)
    if not ui_util.check_archive_status(player) then return end

    local line_id = tonumber(string.match(button.name, "%d+"))
    local context = data_util.get("context", player)
    local line = Floor.get(context.floor, "Line", line_id)
    -- I don't need to care about relevant lines here because this only gets called on lines without subfloor

    if metadata.alt and metadata.click == "left" then
        local beacon_module = line.beacon.module
        local module_list = {[beacon_module.proto.name] = beacon_module.amount}
        set_cursor_blueprint(player, line.beacon.proto.name, module_list, nil)

    elseif metadata.click == "left" or metadata.action == "edit" then
        modal_dialog.enter(player, {type="beacon", modal_data={object=line.beacon, line=line}})

    elseif metadata.action == "delete" then
        Line.set_beacon(line, nil)
        calculation.update(player, context.subfactory)
        main_dialog.refresh(player, "subfactory")
    end
end


local function apply_item_options(player, options, action)
    if action == "submit" then
        local ui_state = data_util.get("ui_state", player)
        local item = ui_state.modal_data.object
        local relevant_line = (item.parent.subfloor) and item.parent.subfloor.defining_line or item.parent

        local current_amount, item_amount = item.amount, options.item_amount or 0
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

local function handle_item_click(player, button, metadata)
    local split_string = split_string(button.name, "_")
    local context = data_util.get("context", player)

    local line = Floor.get(context.floor, "Line", split_string[6])
    -- I don't need to care about relevant lines here because this only gets called on lines without subfloor
    local class = split_string[5]
    local item = Line.get(line, class, split_string[7])

    if metadata.alt then
        data_util.execute_alt_action(player, "show_item", {item=item.proto, click=metadata.click})

    elseif not ui_util.check_archive_status(player) then
        return

    elseif metadata.click == "left" and item.proto.type ~= "entity" then  -- Handles the specific type of item actions
        if class == "Product" then -- Set the priority product
            if line.Product.count < 2 then
                title_bar.enqueue_message(player, {"fp.warning_no_prioritizing_single_product"}, "warning", 1, true)
            elseif context.subfactory.matrix_free_items == nil then
                -- Remove the priority_product if the already selected one is clicked
                line.priority_product_proto = (line.priority_product_proto ~= item.proto) and item.proto or nil

                calculation.update(player, context.subfactory)
                main_dialog.refresh(player, "subfactory")
            end

        else  -- Byproduct or Ingredient
            local production_type = (class == "Byproduct") and "consume" or "produce"
            -- The sequential solver does not support byproduct recipes at the moment
            if production_type == "consume" and context.subfactory.matrix_free_items == nil then
                title_bar.enqueue_message(player, {"fp.error_cant_add_byproduct_recipe"}, "error", 1, true)
            else
                modal_dialog.enter(player, {type="recipe", modal_data={product=item, production_type=production_type,
                  add_after_position=((metadata.shift) and line.gui_position or nil)}})
            end
        end

    elseif metadata.click == "right" and context.subfactory.matrix_free_items == nil then
        -- Set the view state so that the amount shown in the dialog makes sense
        local view_actually_changed = view_state.select(player, "items_per_timescale")
        if view_actually_changed then main_dialog.refresh(player, "subfactory") end

        local type_localised_string = {"fp.pl_" .. class:lower(), 1}
        local produce_consume = (class == "Ingredient") and {"fp.consume"} or {"fp.produce"}

        local modal_data = {
            title = {"fp.options_item_title", type_localised_string},
            text = {"fp.options_item_text", item.proto.localised_name},
            submission_handler = apply_item_options,
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
        fuel_proto.type, line.machine.count)  -- Raw processor call because we only have a prototype, no object

        local category_id = global.all_fuels.map[fuel_proto.category]
        local definition = {
            element_id = category_id .. "_" .. fuel_proto.id,
            sprite = fuel_proto.sprite,
            button_number = amount,
            localised_name = fuel_proto.localised_name,
            amount_line = number_tooltip or "",
            tooltip_appendage = data_util.get_attributes("fuels", fuel_proto),
            selected = (current_proto.type == fuel_proto.type and current_proto.id == fuel_proto.id)
        }
        table.insert(button_definitions, definition)
    end

    return button_definitions
end

local function apply_fuel_choice(player, new_fuel_id_string, _)
    local ui_state = data_util.get("ui_state", player)

    local split_string = split_string(new_fuel_id_string, "_")
    local new_fuel_proto = global.all_fuels.categories[split_string[1]].fuels[split_string[2]]

    ui_state.modal_data.object.proto = new_fuel_proto
    calculation.update(player, ui_state.context.subfactory)
    main_dialog.refresh(player, "subfactory")
end

local function handle_fuel_click(player, button, metadata)
    local line_id = tonumber(string.match(button.name, "%d+"))
    local context = data_util.get("context", player)
    local line = Floor.get(context.floor, "Line", line_id)
    -- I don't need to care about relevant lines here because this only gets called on lines without subfloor
    local fuel = line.machine.fuel  -- must exist to be able to get here

    if metadata.alt then
        data_util.execute_alt_action(player, "show_item", {item=fuel.proto, click=metadata.click})

    elseif not ui_util.check_archive_status(player) then
        return

    elseif metadata.click == "left" then
        modal_dialog.enter(player, {type="recipe", modal_data={product=fuel, production_type="produce",
          add_after_position=((metadata.shift) and line.gui_position or nil)}})

    elseif metadata.click == "right" then
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
            click_handler = apply_fuel_choice,
            button_definitions = compile_fuel_chooser_buttons(player, line, applicable_prototypes),
            object = fuel
        }
        modal_dialog.enter(player, {type="chooser", modal_data=modal_data})
    end
end


-- ** EVENTS **
production_handler.gui_events = {
    on_gui_click = {
        {
            pattern = "^fp_sprite%-button_production_recipe_%d+$",
            timeout = 10,
            handler = handle_recipe_click
        },
        {
            pattern = "^fp_sprite%-button_production_machine_%d+$",
            handler = handle_machine_click
        },
        {
            pattern = "^fp_sprite%-button_production_add_module_%d+$",
            handler = (function(player, element, _)
                local line_id = tonumber(string.match(element.name, "%d+"))
                local line = Floor.get(data_util.get("context", player).floor, "Line", line_id)
                modal_dialog.enter(player, {type="module", modal_data={object=nil, machine=line.machine}})
            end)
        },
        {
            pattern = "^fp_sprite%-button_production_machine_Module_%d+_%d+$",
            handler = handle_module_click
        },
        {
            pattern = "^fp_sprite%-button_production_add_beacon_%d+$",
            handler = (function(player, element, _)
                local line_id = tonumber(string.match(element.name, "%d+"))
                local line = Floor.get(data_util.get("context", player).floor, "Line", line_id)
                modal_dialog.enter(player, {type="beacon", modal_data={object=nil, line=line}})
            end)
        },
        {
            pattern = "^fp_sprite%-button_production_beacon_%d+$",
            handler = handle_beacon_click
        },
        {   -- This catches Product, Byproduct and Ingredient, but not fuel
            pattern = "^fp_sprite%-button_production_item_[A-Z][a-z]+_%d+_%d+$",
            handler = handle_item_click
        },
        {   -- This only the fuel button (no item id necessary)
            pattern = "^fp_sprite%-button_production_fuel_%d+$",
            handler = handle_fuel_click
        },
        {
            pattern = "^fp_checkbox_production_toggle_%d+$",
            handler = handle_toggle_click
        }
    },
    on_gui_text_changed = {
        {
            pattern = "^fp_textfield_production_percentage_%d+$",
            handler = handle_percentage_change
        },
        {
            pattern = "^fp_textfield_production_comment_%d+$",
            handler = (function(player, element)
                local line_id = tonumber(string.match(element.name, "%d+"))
                local line = Floor.get(data_util.get("context", player).floor, "Line", line_id)
                line.comment = element.text
            end)
        }
    },
    on_gui_confirmed = {
        {
            pattern = "^fp_textfield_production_percentage_%d+$",
            handler = handle_percentage_confirmation
        }
    }
}
