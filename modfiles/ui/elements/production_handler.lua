production_handler = {}

-- ** TOP LEVEL **
-- Handles any clicks on the recipe icon of an (assembly) line
function production_handler.handle_line_recipe_click(player, line_id, click, direction, action, alt)
    local ui_state = get_ui_state(player)
    local subfactory = ui_state.context.subfactory
    local floor = ui_state.context.floor
    local line = Floor.get(floor, "Line", line_id)

    local archive_status = ui_util.check_archive_status(player)

    if alt and direction == nil then
        ui_util.execute_alt_action(player, "show_recipe",
          {recipe=line.recipe.proto, line_products=Line.get_in_order(line, "Product")})

    elseif direction ~= nil then  -- Shift (assembly) line in the given direction
        if archive_status then return end

        local shifting_function = (alt) and Floor.shift_to_end or Floor.shift
        -- Can't shift second line into the first position on subfloors
        -- (Top line ignores interaction, so no special handling there)
        if not(direction == "negative" and floor.level > 1 and line.gui_position == 2)
          and shifting_function(floor, line, direction) then
            calculation.update(player, subfactory, true)
        else
            local direction_string = (direction == "negative") and {"fp.up"} or {"fp.down"}
            local message = {"fp.error_list_item_cant_be_shifted", {"fp.lrecipe"}, direction_string}
            ui_util.message.enqueue(player, message, "error", 1, false)
        end

        main_dialog.refresh_current_activity(player)

    else
        -- Attaches a subfloor to this line
        if click == "left" then
            local subfloor = line.subfloor
            if subfloor == nil then  -- create new subfloor
                if archive_status then return end

                subfloor = Floor.init(line)  -- attaches itself to the given line automatically
                Subfactory.add(subfactory, subfloor)
                calculation.update(player, subfactory, false)
            end

            ui_state.current_activity = nil
            ui_util.context.set_floor(player, subfloor)
            main_dialog.refresh(player)

        -- Handle removal of clicked (assembly) line
        elseif click == "right" and action == "delete" then
            if archive_status then return end

            if line.subfloor == nil then
                Floor.remove(floor, line)
                calculation.update(player, subfactory, true)
            else
                if ui_state.current_activity == "deleting_line" then
                    Floor.remove(floor, line)
                    ui_state.current_activity = nil
                    ui_state.context.line = nil
                    calculation.update(player, subfactory, true)
                else
                    ui_state.current_activity = "deleting_line"
                    ui_state.context.line = line
                    main_dialog.refresh_current_activity(player)
                end
            end
        end
    end
end


-- Handles the changing of the percentage textfield (doesn't refresh the production table yet)
function production_handler.handle_percentage_change(player, element)
    local ui_state = get_ui_state(player)
    local floor = ui_state.context.floor
    local line = Floor.get(floor, "Line", tonumber(string.match(element.name, "%d+")))

    local new_percentage = tonumber(element.text) or 0
    Line.set_percentage(line, new_percentage)
end

-- Handles the player confirming the given percentage textfield by reloading and refocusing
function production_handler.handle_percentage_confirmation(player, element)
    local line_id = tonumber(string.match(element.name, "%d+"))
    local ui_state = get_ui_state(player)
    ui_state.current_activity = nil

    local scroll_pane = element.parent.parent
    calculation.update(player, ui_state.context.subfactory, true)
    scroll_pane["table_production_pane"]["fp_textfield_line_percentage_" .. line_id].focus()
end


-- Handles the machine changing process
function production_handler.handle_machine_change(player, line_id, machine_id, click, direction, alt)
    if ui_util.check_archive_status(player) then return end

    local ui_state = get_ui_state(player)
    local subfactory = ui_state.context.subfactory
    local floor = ui_state.context.floor
    local line = Floor.get(floor, "Line", line_id)

    -- machine_id being nil means the user wants to change the machine of this (assembly) line
    if machine_id == nil then
        -- Change the machine to be one tier lower/higher if possible
        if direction ~= nil then
            Line.change_machine(line, player, nil, direction)
            calculation.update(player, subfactory, true)

        -- Reset this machine to its default if ALT was pressed
        elseif alt then
            Line.change_machine(line, player, nil, nil)
            line.machine.limit = nil
            line.machine.hard_limit = false
            calculation.update(player, subfactory, true)

        -- Display all the options for this machine category
        elseif click == "left" then
            -- Determine how many machines are applicable to this recipe
            -- This detection will run twice, which might be worth optimizing at some point
            local applicable_machine_count = 0
            for _, machine_proto in pairs(line.machine.category.machines) do
                if Line.is_machine_applicable(line, machine_proto) then
                    applicable_machine_count = applicable_machine_count + 1
                end
            end

            -- Changing machines only makes sense if there are more than one in it's category
            if applicable_machine_count > 1 then
                if applicable_machine_count < 5 then  -- up to 4 machines, no picker is needed
                    ui_state.current_activity = "changing_machine"
                    ui_state.context.line = line  -- won't be reset after use, but that doesn't matter
                    main_dialog.refresh_current_activity(player)

                else  -- Open a chooser dialog presenting all machine choices
                    local modal_data = {
                        button_generator = production_handler.generate_chooser_machine_buttons,
                        click_handler = production_handler.apply_machine_choice,
                        title = {"fp.machine"},
                        text = {"", {"fp.chooser_machine"}, " '", line.recipe.proto.localised_name, "':"},
                        object = line.machine
                    }

                    ui_state.context.line = line  -- won't be reset after use, but that doesn't matter
                    modal_dialog.enter(player, {type="chooser", modal_data=modal_data})
                end
            end

        -- Open the dialog to set a machine count limit
        elseif click == "right" then
            local modal_data = {
                submission_handler = production_handler.apply_machine_options,
                title = {"fp.machine_limit_title"},
                text = {"", {"fp.machine_limit_text"}, " '", line.recipe.proto.localised_name, "':"},
                object = line.machine,
                fields = {
                    {
                        type = "numeric",
                        name = "machine_limit",
                        caption = {"fp.machine_limit_option"},
                        tooltip = {"fp.machine_limit_option_tt"},
                        value = line.machine.limit or "",
                        focus = true
                    },
                    {
                        type = "on_off_switch",
                        name = "hard_limit",
                        caption = {"fp.machine_hard_limit_option"},
                        tooltip = {"fp.machine_hard_limit_option_tt"},
                        value = line.machine.hard_limit or false
                    }
                }
            }

            ui_state.context.line = line  -- won't be reset after use, but that doesn't matter
            modal_dialog.enter(player, {type="options", submit=true, modal_data=modal_data})
        end
    else
        -- Accept the user selection of new machine for this (assembly) line
        if click == "left" then
            local category_id = line.machine.category.id
            local new_machine = global.all_machines.categories[category_id].machines[machine_id]
            Line.change_machine(line, player, new_machine, nil)
            ui_state.current_activity = nil
            calculation.update(player, subfactory, true)
        end
    end
end

-- Generates the buttons for the machine chooser dialog
function production_handler.generate_chooser_machine_buttons(player)
    local ui_state = get_ui_state(player)
    local line = ui_state.context.line

    for machine_id, machine_proto in ipairs(line.machine.category.machines) do
        if Line.is_machine_applicable(line, machine_proto) then
            local button = chooser_dialog.generate_blank_button(player, machine_id)
            -- The actual button is setup by the method shared by non-chooser machine buttons
            production_table.setup_machine_choice_button(player, button, machine_proto,
              ui_state.modal_data.object.proto.id, 36)
        end
    end
end

-- Recieves the result of the machine choice and applies it
function production_handler.apply_machine_choice(player, machine_id)
    local context = get_context(player)
    local category_id = context.line.machine.category.id
    local machine = global.all_machines.categories[category_id].machines[tonumber(machine_id)]
    Line.change_machine(context.line, player, machine, nil)
    calculation.update(player, context.subfactory, true)
end

-- Recieves the result of the machine limit options and applies it
function production_handler.apply_machine_options(player, _, options)
    local context = get_context(player)

    local machine = context.line.machine
    if options.machine_limit == nil then options.hard_limit = false end
    machine.limit, machine.hard_limit = options.machine_limit, options.hard_limit

    calculation.update(player, context.subfactory, true)
end


-- Handles a click on an existing module or on the add-module-button
function production_handler.handle_line_module_click(player, line_id, module_id, click, direction, action, alt)
    if ui_util.check_archive_status(player) then return end

    local ui_state = get_ui_state(player)
    local floor = ui_state.context.floor
    local line = Floor.get(floor, "Line", line_id)
    ui_state.context.line = line
    local limit = Line.empty_slots(line)

    if module_id == nil then  -- meaning the add-module-button was pressed
        modal_dialog.enter(player, {type="module", submit=true, modal_data={selected_object=nil, empty_slots=limit}})

    else  -- meaning an existing module was clicked
        local module = Line.get(line, "Module", module_id)

        if direction ~= nil then  -- change the module to a higher/lower amount/tier
            local tier_map = module_tier_map

            -- Changes the current module tier by the given factor (+1 or -1 in this case)
            local function handle_tier_change(factor)
                local new_proto = tier_map[module.category.id][module.proto.tier + factor]
                if new_proto ~= nil then
                    local new_module = Module.init_by_proto(new_proto, tonumber(module.amount))
                    Line.replace(line, module, new_module)
                else
                    local change_direction = (factor == 1) and {"fp.upgraded"} or {"fp.downgraded"}
                    local message = {"fp.error_object_cant_be_up_downgraded", {"fp.module"}, change_direction}
                    ui_util.message.enqueue(player, message, "error", 1)
                end
            end

            -- alt modifies the module amount, no alt modifies the module tier
            if direction == "positive" then
                if alt then
                    local new_amount = math.min(module.amount + 1, module.amount + limit)
                    if new_amount == module.amount then
                        local message = {"fp.error_object_amount_cant_be_in_decreased", {"fp.module"}, {"fp.increased"}}
                        ui_util.message.enqueue(player, message, "error", 1)
                    else
                        Module.change_amount(module, new_amount)
                    end
                else
                    handle_tier_change(1)
                end

            else  -- direction == "negative"
                if alt then
                    local new_amount = module.amount - 1
                    if new_amount == 0 then  -- no error message possible here
                        Line.remove(line, module)
                    else
                        Module.change_amount(module, new_amount)
                    end
                else
                    handle_tier_change(-1)
                end
            end

            calculation.update(player, ui_state.context.subfactory, true)

        elseif action == "delete" then
            Line.remove(line, module)
            calculation.update(player, ui_state.context.subfactory, true)

        elseif action == "edit" or click == "left" then
            modal_dialog.enter(player, {type="module", submit=true, delete=true, modal_data={selected_object=module,
              empty_slots=(limit + module.amount), selected_module=module.proto}})
        end
    end
end


-- Handles a click on an existing beacon/beacon-module or on the add-beacon-button
function production_handler.handle_line_beacon_click(player, line_id, type, click, direction, action, alt)
    if ui_util.check_archive_status(player) then return end

    local ui_state = get_ui_state(player)
    local floor = ui_state.context.floor
    local line = Floor.get(floor, "Line", line_id)
    ui_state.context.line = line

    if type == nil then  -- meaning the add-beacon-button was pressed
        local limit = prototyper.defaults.get(player, "beacons").module_limit
        modal_dialog.enter(player, {type="beacon", submit=true, modal_data={selected_object=nil, empty_slots=limit}})

    elseif direction ~= nil then  -- check direction here, because click doesn't matter if there is no direction
        if type == "module" then
            local module = line.beacon.module
            local tier_map = module_tier_map

            -- Changes the current module tier by the given factor (+1 or -1 in this case)
            local function handle_tier_change(factor)
                local new_proto = tier_map[module.category.id][module.proto.tier + factor]
                if new_proto ~= nil then
                    local new_module = Module.init_by_proto(new_proto, tonumber(module.amount))
                    Beacon.set_module(line.beacon, new_module)
                else
                    local change_direction = (factor == 1) and {"fp.upgraded"} or {"fp.downgraded"}
                    local message = {"fp.error_object_cant_be_up_downgraded", {"fp.module"}, change_direction}
                    ui_util.message.enqueue(player, message, "error", 1)
                end
            end

            -- alt modifies the module amount, no alt modifies the module tier
            if direction == "positive" then
                if alt then
                    local new_amount = math.min(module.amount + 1, line.beacon.proto.module_limit)
                    if new_amount == module.amount then
                        local message = {"fp.error_object_amount_cant_be_in_decreased", {"fp.module"}, {"fp.increased"}}
                        ui_util.message.enqueue(player, message, "error", 1)
                    else
                        local new_module = Module.init_by_proto(module.proto, tonumber(new_amount))
                        Beacon.set_module(line.beacon, new_module)
                    end
                else
                    handle_tier_change(1)
                end

            else  -- direction == "negative"
                if alt then
                    local new_amount = module.amount - 1
                    if new_amount == 0 then  -- no error message possible here
                        Line.set_beacon(line, nil)
                    else
                        local new_module = Module.init_by_proto(module.proto, tonumber(new_amount))
                        Beacon.set_module(line.beacon, new_module)
                    end
                else
                    handle_tier_change(-1)
                end
            end

        else  -- type == "beacon"
            local beacon = line.beacon

            local function handle_tier_change(factor)
                local new_proto = global.all_beacons.beacons[beacon.proto.id + factor]
                if new_proto ~= nil then
                    local new_beacon = Beacon.init_by_protos(new_proto, beacon.amount, beacon.module.proto,
                      beacon.module.amount, beacon.total_amount)
                    Line.set_beacon(line, new_beacon)
                else
                    local change_direction = (factor == 1) and {"fp.upgraded"} or {"fp.downgraded"}
                    local message = {"fp.error_object_cant_be_up_downgraded", {"fp.beacon"}, change_direction}
                    ui_util.message.enqueue(player, message, "error", 1)
                end
            end

            -- alt modifies the beacon amount, no alt modifies the beacon tier
            if direction == "positive" then
                if alt then -- no error message possible here
                    local new_beacon = Beacon.init_by_protos(beacon.proto, beacon.amount + 1, beacon.module.proto,
                      beacon.module.amount, beacon.total_amount)
                    Line.set_beacon(line, new_beacon)
                else
                    handle_tier_change(1)
                end

            else  -- direction == "negative"
                if alt then
                    local new_amount = beacon.amount - 1
                    if new_amount == 0 then  -- no error message possible here
                        Line.set_beacon(line, nil)
                    else
                        local new_beacon = Beacon.init_by_protos(beacon.proto, new_amount, beacon.module.proto,
                          beacon.module.amount, beacon.total_amount)
                        Line.set_beacon(line, new_beacon)
                    end
                else
                    handle_tier_change(-1)
                end
            end
        end

        calculation.update(player, ui_state.context.subfactory, true)

    elseif action == "delete" then
        Line.set_beacon(line, nil)
        calculation.update(player, ui_state.context.subfactory, true)

    elseif action == "edit" or click == "left" then
        local beacon = line.beacon
        modal_dialog.enter(player, {type="beacon", submit=true, delete=true, modal_data={selected_object=beacon,
          empty_slots=beacon.proto.module_limit, selected_beacon=beacon.proto, selected_module=beacon.module.proto}})
    end
end


-- Handles a click on any of the 3 item buttons of a specific line
function production_handler.handle_item_button_click(player, line_id, class, item_id, click, direction, alt)
    if ui_util.check_archive_status(player) then return end

    local context = get_context(player)
    local line = Floor.get(context.floor, "Line", line_id)
    local item = Line.get(line, class, item_id)

    if alt then
        ui_util.execute_alt_action(player, "show_item", {item=item.proto, click=click})

    elseif direction ~= nil then  -- Shift item in the given direction
        if Line.shift(line, item, direction) then
            production_table.refresh(player)
        else
            local lower_class = string.lower(class)
            local direction_string = (direction == "negative") and {"fp.left"} or {"fp.right"}
            local message = {"fp.error_list_item_cant_be_shifted", {"fp.l" .. lower_class}, direction_string}
            ui_util.message.enqueue(player, message, "error", 1, false)
        end

        main_dialog.refresh_current_activity(player)

    elseif click == "left" and item.proto.type ~= "entity" then
        if item.class == "Ingredient" then  -- Pick recipe to produce this ingredient
            modal_dialog.enter(player, {type="recipe", modal_data={product=item, production_type="produce"}})

        elseif item.class == "Product" then -- Set the priority product
            if line.Product.count < 2 then
                ui_util.message.enqueue(player, {"fp.error_no_prioritizing_single_product"}, "error", 1, true)
            else
                line.priority_product_proto = (line.priority_product_proto ~= item.proto) and item.proto or nil
                calculation.update(player, context.subfactory, true)
            end

        --[[ elseif item.class == "Byproduct" then
            modal_dialog.enter(player, {type="recipe", modal_data={product=item, production_type="consume"}}) ]]
        end

    elseif click == "right" then  -- Open the percentage dialog for this item
        local type_localised_string = {"fp.l" .. string.lower(item.class)}
        local produce_consume = (item.class == "Ingredient") and {"fp.consume"} or {"fp.produce"}

        local modal_data = {
            submission_handler = production_handler.apply_item_options,
            title = {"fp.option_item_title", type_localised_string},
            text = {"fp.option_text", {"fp.option_item_text", type_localised_string}, item.proto.localised_name},
            object = item,
            fields = {
                {
                    type = "numeric",
                    name = "item_amount",
                    caption = {"fp.option_item_amount_label"},
                    tooltip = {"fp.option_item_amount_label_tt", type_localised_string, produce_consume},
                    value = item.amount,
                    width = 160,
                    focus = true
                }
            }
        }

        context.line = line  -- won't be reset after use, but that doesn't matter
        modal_dialog.enter(player, {type="options", submit=true, modal_data=modal_data})
    end
end

-- Recieves the result of the item options and applies it
function production_handler.apply_item_options(player, item, options)
    local context = get_context(player)
    local line = context.line
    local current_amount = item.amount

    -- For products and byproducts, find if the item exists in the other space
    if item.class ~= "Ingredient" then
        local other_class = (item.class == "Product") and "Byproduct" or "Product"
        local opposing_item = Line.get_by_type_and_name(line, other_class, item.proto.type, item.proto.name)
        if opposing_item ~= nil then current_amount = current_amount + opposing_item.amount end
    end

    options.item_amount = options.item_amount or 0
    local new_percentage = (line.percentage * options.item_amount) / current_amount
    Line.set_percentage(line, new_percentage)

    calculation.update(player, context.subfactory, true)
end


-- Handles a click on an line fuel button
function production_handler.handle_fuel_button_click(player, line_id, click, direction, alt)
    if ui_util.check_archive_status(player) then return end

    local context = get_context(player)
    local line = Floor.get(context.floor, "Line", line_id)
    local fuel = line.fuel  -- must exist to be able to get here

    if alt then
        ui_util.execute_alt_action(player, "show_item", {item=fuel.proto, click=click})

    elseif direction ~= nil then  -- change to the previous/next fuel in the list
        local category_id = global.all_fuels.map[fuel.proto.category]
        local prototype_table = global.all_fuels.categories[category_id].fuels

        local function change_fuel_proto(factor)
            local new_proto = prototype_table[fuel.proto.id + factor]
            if new_proto ~= nil then
                line.fuel = Fuel.init_by_proto(new_proto, fuel.amount)
                calculation.update(player, context.subfactory, true)
            else
                local type = (factor == 1) and {"fp.upgraded"} or {"fp.downgraded"}
                local message = {"fp.error_object_cant_be_up_downgraded", {"fp.lfuel"}, type}
                ui_util.message.enqueue(player, message, "error", 1, true)
            end
        end

        if direction == "positive" then
            change_fuel_proto(1)
        else  -- direction == "negative"
            change_fuel_proto(-1)
        end

    else
        if click == "left" then
            modal_dialog.enter(player, {type="recipe", modal_data={product=fuel, production_type="produce"}})

        elseif click == "right" then
            local modal_data = {
                button_generator = production_handler.generate_chooser_fuel_buttons,
                click_handler = production_handler.apply_fuel_choice,
                title = {"fp.fuel"},
                text = {"", {"fp.chooser_fuel_line"}, " '", line.machine.proto.localised_name, "':"},
                object = fuel
            }

            context.line = line  -- won't be reset after use, but that doesn't matter
            modal_dialog.enter(player, {type="chooser", modal_data=modal_data})
        end
    end
end

-- Generates the buttons for the fuel chooser dialog
function production_handler.generate_chooser_fuel_buttons(player)
    local player_table = get_table(player)
    local ui_state = get_ui_state(player)
    local view_name = ui_state.view_state.selected_view.name
    local line = ui_state.context.line

    local old_fuel_proto = ui_state.modal_data.object.proto
    local machine = line.machine  -- This machine is implicitly powered by a burner if this code runs
    for category_name, _ in pairs(machine.proto.burner.categories) do
        local category_id = global.all_fuels.map[category_name]
        for fuel_id, fuel_proto in pairs(global.all_fuels.categories[category_id].fuels) do
            local selected_fuel = (old_fuel_proto.type == fuel_proto.type and old_fuel_proto.name == fuel_proto.name)
            local selected = (selected_fuel) and {"", " (", {"fp.selected"}, ")"} or ""
            local tooltip = {"", fuel_proto.localised_name, selected}

            local fuel_amount = nil
            -- Only add number information if this line has no subfloor (really difficult calculations otherwise)
            if line.subfloor == nil then
                local energy_consumption = calculation.util.determine_energy_consumption(machine.proto, machine.count,
                line.total_effects)  -- don't care about mining productivity in this case, only the consumption-effect
                fuel_amount = calculation.util.determine_fuel_amount(energy_consumption, machine.proto.burner,
                fuel_proto.fuel_value, ui_state.context.subfactory.timescale)

                fuel_amount, appendage = ui_util.determine_item_amount_and_appendage(player_table, view_name,
                  fuel_proto.type, fuel_amount, line.machine)
                tooltip = {"", tooltip, "\n" .. ui_util.format_number(fuel_amount, 4) .. " ", appendage}
            end
            tooltip = {"", tooltip, "\n", ui_util.attributes.fuel(fuel_proto)}

            local fuel_id_string = category_id .. "_" .. fuel_id
            local button = chooser_dialog.generate_blank_button(player, fuel_id_string)
            if selected_fuel then button.style = "fp_button_icon_large_green" end
            button.sprite = fuel_proto.sprite
            button.number = ui_util.format_number(fuel_amount, 4)
            button.tooltip = tooltip
        end
    end
end

-- Recieves the result of a chooser user choice and applies it
function production_handler.apply_fuel_choice(player, new_fuel_id_string)
    local context = get_context(player)
    local split_string = cutil.split(new_fuel_id_string, "_")
    local new_fuel = global.all_fuels.categories[split_string[1]].fuels[split_string[2]]
    context.line.fuel.proto = new_fuel
    calculation.update(player, context.subfactory, true)
end


-- Handles the changing of the comment textfield
function production_handler.handle_comment_change(player, element)
    local line = Floor.get(get_context(player).floor, "Line", tonumber(string.match(element.name, "%d+")))
    line.comment = element.text
end

-- Clears all comments on the current floor
function production_handler.clear_recipe_comments(player)
    local floor = get_context(player).floor
    for _, line in ipairs(Floor.get_in_order(floor, "Line")) do
        line.comment = nil
    end
    production_titlebar.refresh(player)
end