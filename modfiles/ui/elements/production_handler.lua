production_handler = {}

-- ** LOCAL UTIL **
local function compile_machine_chooser_buttons(player, line, applicable_prototypes)
    local round_button_numbers = data_util.get("preferences", player).round_button_numbers
    local timescale = data_util.get("context", player).subfactory.timescale

    local current_proto = line.machine.proto
    local button_definitions = {}

    for _, machine_proto in ipairs(applicable_prototypes) do
        local crafts_per_tick = calculation.util.determine_crafts_per_tick(machine_proto,
          line.recipe.proto, Line.get_total_effects(line, player))
        local machine_count = calculation.util.determine_machine_count(crafts_per_tick,
          line.uncapped_production_ratio, timescale, machine_proto.is_rocket_silo)

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
            tooltip_appendage = ui_util.get_attributes("machines", machine_proto),
            selected = (current_proto.id == machine_proto.id)
        }

        table.insert(button_definitions, definition)
    end

    return button_definitions
end

local function compile_fuel_chooser_buttons(player, line, applicable_prototypes)
    local ui_state = data_util.get("ui_state", player)
    local view_name = ui_state.view_state.selected_view.name
    local timescale = ui_state.context.subfactory.timescale

    local current_proto = line.machine.fuel.proto
    local button_definitions = {}

    for _, fuel_proto in pairs(applicable_prototypes) do
        local category_id = global.all_fuels.map[fuel_proto.category]

        local energy_consumption = calculation.util.determine_energy_consumption(line.machine.proto, line.machine.count,
          line.total_effects)  -- don't care about mining productivity in this case, only the consumption-effect
        local raw_fuel_amount = calculation.util.determine_fuel_amount(energy_consumption, line.machine.proto.burner,
          fuel_proto.fuel_value, timescale)

        -- TODO this util function is so crappy
        local fuel_amount, appendage = ui_util.determine_item_amount_and_appendage(player, view_name,
            fuel_proto.type, raw_fuel_amount, line.machine)
        local amount_line = {"fp.two_word_title", ui_util.format_number(fuel_amount, 4), appendage}


        local definition = {
            element_id = category_id .. "_" .. fuel_proto.id,
            sprite = fuel_proto.sprite,
            button_number = fuel_amount,
            localised_name = fuel_proto.localised_name,
            amount_line = amount_line,
            tooltip_appendage = ui_util.get_attributes("fuels", fuel_proto),
            selected = (current_proto.type == fuel_proto.type and current_proto.id == fuel_proto.id)
        }

        table.insert(button_definitions, definition)
    end

    return button_definitions
end


-- ** TOP LEVEL **
-- Handles any clicks on the recipe icon of an (assembly) line
function production_handler.handle_line_recipe_click(player, line_id, click, direction, action, alt)
    local ui_state = get_ui_state(player)
    local subfactory = ui_state.context.subfactory
    local floor = ui_state.context.floor
    local line = Floor.get(floor, "Line", line_id)

    local archive_status = ui_util.check_archive_status(player)

    if alt and direction == nil then
        local relevant_line = (line.subfloor == nil) and line or Floor.get(line.subfloor, "Line", 1)
        ui_util.execute_alt_action(player, "show_recipe",
          {recipe=relevant_line.recipe.proto, line_products=Line.get_in_order(line, "Product")})

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
            titlebar.enqueue_message(player, message, "error", 1, true)
        end

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

            ui_util.context.set_floor(player, subfloor)
            main_dialog.refresh(player)

        -- Handle removal of clicked (assembly) line
        elseif click == "right" and action == "delete" then
            if archive_status then return end

            Floor.remove(floor, line)
            calculation.update(player, subfactory, true)
        end
    end
end


-- Handles the changing of the percentage textfield (doesn't refresh the production table yet)
function production_handler.handle_percentage_change(player, element)
    local ui_state = get_ui_state(player)
    local floor = ui_state.context.floor
    local line = Floor.get(floor, "Line", tonumber(string.match(element.name, "%d+")))
    local relevant_line = (line.subfloor == nil) and line or Floor.get(line.subfloor, "Line", 1)

    relevant_line.percentage = tonumber(element.text) or 0
end

-- Handles the player confirming the given percentage textfield by reloading and refocusing
function production_handler.handle_percentage_confirmation(player, element)
    local line_id = tonumber(string.match(element.name, "%d+"))
    local ui_state = get_ui_state(player)

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
    local relevant_line = (line.subfloor == nil) and line or Floor.get(line.subfloor, "Line", 1)
    local recipe_proto = relevant_line.recipe.proto

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
            local current_machine_proto = line.machine.proto
            local applicable_prototypes = {}

            local machine_category_id = global.all_machines.map[current_machine_proto.category]
            local category_prototypes = global.all_machines.categories[machine_category_id].machines

            -- Determine if there is more than one machine that applies to this machine
            for _, machine_proto in ipairs(category_prototypes) do
                if Line.is_machine_applicable(line, machine_proto) then
                    table.insert(applicable_prototypes, machine_proto)
                end
            end

            -- Changing machines only makes sense if there are more than one in its category
            if #applicable_prototypes > 1 then  -- Open a chooser dialog presenting all machine choices
                local modal_data = {
                    title = {"fp.pl_machine", 1},
                    text = {"fp.chooser_machine", recipe_proto.localised_name},
                    click_handler = production_handler.apply_machine_choice,
                    button_definitions = compile_machine_chooser_buttons(player, line, applicable_prototypes),
                    object = line.machine,
                }

                modal_dialog.enter(player, {type="chooser", modal_data=modal_data})
            end

        -- Open the dialog to set a machine count limit
        elseif click == "right" then
            local modal_data = {
                title = {"fp.options_machine_title"},
                text = {"fp.options_machine_text", line.machine.proto.localised_name},
                submission_handler = production_handler.apply_machine_options,
                object = line.machine,
                fields = {
                    {
                        type = "numeric_textfield",
                        name = "machine_limit",
                        change_handler = production_handler.machine_limit_change,
                        caption = {"fp.options_machine_limit"},
                        tooltip = {"fp.options_machine_limit_tt"},
                        text = line.machine.limit or "",
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

            modal_dialog.enter(player, {type="options", submit=true, modal_data=modal_data})
        end
    end
end


-- Recieves the result of the machine choice and applies it
function production_handler.apply_machine_choice(player, machine_id)
    local ui_state = data_util.get("ui_state", player)
    local machine = ui_state.modal_data.object

    local machine_category_id = global.all_machines.map[machine.proto.category]
    local machine_proto = global.all_machines.categories[machine_category_id].machines[tonumber(machine_id)]

    Line.change_machine(machine.parent, player, machine_proto, nil)
    calculation.update(player, ui_state.context.subfactory, true)
end

-- Sets the state of the hard limit switch according to what the entered limit is
function production_handler.machine_limit_change(modal_data, textfield)
    local switch = modal_data.ui_elements["fp_switch_on_off_options_hard_limit"]
    local machine_limit = tonumber(textfield.text)
    if machine_limit == nil then switch.switch_state = "right" end
    switch.enabled = (machine_limit ~= nil)
end

-- Recieves the result of the machine limit options and applies it
function production_handler.apply_machine_options(player, options, action)
    if action == "submit" then
        local ui_state = data_util.get("ui_state", player)
        local machine = ui_state.modal_data.object

        if options.machine_limit == nil then options.hard_limit = false end
        machine.limit, machine.hard_limit = options.machine_limit, options.hard_limit

        calculation.update(player, ui_state.context.subfactory, true)
    end
end


-- Handles a click on an existing module or on the add-module-button
function production_handler.handle_line_module_click(player, line_id, module_id, click, direction, action, alt)
    if ui_util.check_archive_status(player) then return end

    local ui_state = get_ui_state(player)
    local floor = ui_state.context.floor
    local line = Floor.get(floor, "Line", line_id)

    if module_id == nil then  -- meaning the add-module-button was pressed
        modal_dialog.enter(player, {type="module", submit=true, modal_data={object=nil, machine=line.machine}})

    else  -- meaning an existing module was clicked
        local module = Machine.get(line.machine, "Module", module_id)

        if direction ~= nil then  -- change the module to a higher/lower amount/tier
            local tier_map = MODULE_TIER_MAP

            -- Changes the current module tier by the given factor (+1 or -1 in this case)
            local function handle_tier_change(factor)
                local module_category_id = global.all_modules.map[module.proto.category]
                local new_proto = tier_map[module_category_id][module.proto.tier + factor]
                if new_proto ~= nil then
                    local new_module = Module.init_by_proto(new_proto, tonumber(module.amount))
                    Machine.replace(line.machine, module, new_module)
                else
                    local change_direction = (factor == 1) and {"fp.upgraded"} or {"fp.downgraded"}
                    local message = {"fp.error_object_cant_be_up_downgraded", {"fp.module"}, change_direction}
                    titlebar.enqueue_message(player, message, "error", 1)
                end
            end

            -- alt modifies the module amount, no alt modifies the module tier
            if direction == "positive" then
                if alt then
                    local limit = Machine.empty_slot_count(line.machine)
                    local new_amount = math.min(module.amount + 1, module.amount + limit)
                    if new_amount == module.amount then
                        local message = {"fp.error_object_amount_cant_be_in_decreased", {"fp.module"}, {"fp.increased"}}
                        titlebar.enqueue_message(player, message, "error", 1)
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
                        Machine.remove(line.machine, module)
                    else
                        Module.change_amount(module, new_amount)
                    end
                else
                    handle_tier_change(-1)
                end
            end

            calculation.update(player, ui_state.context.subfactory, true)

        elseif action == "delete" then
            Machine.remove(line.machine, module)
            calculation.update(player, ui_state.context.subfactory, true)

        elseif action == "edit" or click == "left" then
            modal_dialog.enter(player, {type="module", submit=true, delete=true,
              modal_data={object=module, machine=line.machine}})
        end
    end
end


-- Handles a click on an existing beacon/beacon-module or on the add-beacon-button
function production_handler.handle_line_beacon_click(player, line_id, type, click, direction, action, alt)
    if ui_util.check_archive_status(player) then return end

    local ui_state = get_ui_state(player)
    local floor = ui_state.context.floor
    local line = Floor.get(floor, "Line", line_id)

    if type == nil then  -- meaning the add-beacon-button was pressed
        modal_dialog.enter(player, {type="beacon", submit=true, modal_data={object=nil, line=line}})

    elseif direction ~= nil then  -- check direction here, because click doesn't matter if there is no direction
        if type == "module" then
            local module = line.beacon.module
            local tier_map = MODULE_TIER_MAP

            -- Changes the current module tier by the given factor (+1 or -1 in this case)
            local function handle_tier_change(factor)
                local module_category_id = global.all_modules.map[module.proto.category]
                local new_proto = tier_map[module_category_id][module.proto.tier + factor]
                if new_proto ~= nil then
                    local new_module = Module.init_by_proto(new_proto, tonumber(module.amount))
                    Beacon.set_module(line.beacon, new_module)
                else
                    local change_direction = (factor == 1) and {"fp.upgraded"} or {"fp.downgraded"}
                    local message = {"fp.error_object_cant_be_up_downgraded", {"fp.module"}, change_direction}
                    titlebar.enqueue_message(player, message, "error", 1)
                end
            end

            -- alt modifies the module amount, no alt modifies the module tier
            if direction == "positive" then
                if alt then
                    local new_amount = math.min(module.amount + 1, line.beacon.proto.module_limit)
                    if new_amount == module.amount then
                        local message = {"fp.error_object_amount_cant_be_in_decreased", {"fp.module"}, {"fp.increased"}}
                        titlebar.enqueue_message(player, message, "error", 1)
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
                    titlebar.enqueue_message(player, message, "error", 1)
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
        modal_dialog.enter(player, {type="beacon", submit=true, delete=true,
          modal_data={object=line.beacon, line=line}})
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

    elseif click == "left" and item.proto.type ~= "entity" then
        if item.class == "Ingredient" then  -- Pick recipe to produce this ingredient
            modal_dialog.enter(player, {type="recipe", modal_data={product=item, production_type="produce",
              add_after_position=((direction == "positive") and line.gui_position or nil)}})

        elseif item.class == "Product" then -- Set the priority product
            if line.Product.count < 2 then
                titlebar.enqueue_message(player, {"fp.error_no_prioritizing_single_product"}, "error", 1, true)
            else
                -- Remove the priority_product if the already selected one is clicked
                local priority_proto = (line.priority_product_proto ~= item.proto) and item.proto or nil
                -- The priority_product is always stored on the first line of the subfloor, if there is one
                local relevant_line = (line.subfloor == nil) and line or Floor.get(line.subfloor, "Line", 1)
                relevant_line.priority_product_proto = priority_proto

                calculation.update(player, context.subfactory, true)
            end

        --[[ elseif item.class == "Byproduct" then
            modal_dialog.enter(player, {type="recipe", modal_data={product=item, production_type="consume"}}) ]]
        end

    elseif click == "right" then  -- Open the percentage dialog for this item
        local type_localised_string = {"fp.pl_" .. string.lower(item.class), 1}
        local produce_consume = (item.class == "Ingredient") and {"fp.consume"} or {"fp.produce"}

        local modal_data = {
            title = {"fp.options_item_title", type_localised_string},
            text = {"fp.options_item_text", item.proto.localised_name},
            submission_handler = production_handler.apply_item_options,
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

        modal_dialog.enter(player, {type="options", submit=true, modal_data=modal_data})
    end
end

-- Recieves the result of the item options and applies it
function production_handler.apply_item_options(player, options, action)
    if action == "submit" then
        local ui_state = data_util.get("ui_state", player)
        local item = ui_state.modal_data.object
        local current_amount = item.amount

        local line = item.parent
        local relevant_line = (line.subfloor == nil) and line or Floor.get(line.subfloor, "Line", 1)

        if item.class ~= "Ingredient" then  -- For products and byproducts, find if the item exists in the other space
            local other_class = (item.class == "Product") and "Byproduct" or "Product"
            local opposing_item = Line.get_by_type_and_name(relevant_line, other_class,
              item.proto.type, item.proto.name)
            if opposing_item ~= nil then current_amount = current_amount + opposing_item.amount end
        end

        options.item_amount = options.item_amount or 0
        relevant_line.percentage = (relevant_line.percentage * options.item_amount) / current_amount

        calculation.update(player, ui_state.context.subfactory, true)
    end
end


-- Handles a click on an line fuel button
function production_handler.handle_fuel_button_click(player, line_id, click, direction, alt)
    if ui_util.check_archive_status(player) then return end

    local context = get_context(player)
    local line = Floor.get(context.floor, "Line", line_id)
    local fuel = line.machine.fuel  -- must exist to be able to get here

    if alt then
        ui_util.execute_alt_action(player, "show_item", {item=fuel.proto, click=click})

    else
        if click == "left" then
            modal_dialog.enter(player, {type="recipe", modal_data={product=fuel, production_type="produce",
              add_after_position=((direction == "positive") and line.gui_position or nil)}})

        elseif click == "right" then
            local machine_proto = line.machine.proto
            local applicable_prototypes = {}

            -- Applicable fuels come from all categories that this burner supports
            for category_name, _ in pairs(machine_proto.burner.categories) do
                local category_id = global.all_fuels.map[category_name]
                if category_id ~= nil then
                    for _, fuel_proto in pairs(global.all_fuels.categories[category_id].fuels) do
                        table.insert(applicable_prototypes, fuel_proto)
                    end
                end
            end

            local modal_data = {
                title = {"fp.pl_fuel", 1},
                text = {"fp.chooser_fuel", machine_proto.localised_name},
                click_handler = production_handler.apply_fuel_choice,
                button_definitions = compile_fuel_chooser_buttons(player, line, applicable_prototypes),
                object = fuel,
            }

            modal_dialog.enter(player, {type="chooser", modal_data=modal_data})
        end
    end
end

-- Recieves the result of a chooser user choice and applies it
function production_handler.apply_fuel_choice(player, new_fuel_id_string)
    local ui_state = data_util.get("ui_state", player)

    local split_string = split_string(new_fuel_id_string, "_")
    local new_fuel_proto = global.all_fuels.categories[split_string[1]].fuels[split_string[2]]

    ui_state.modal_data.object.proto = new_fuel_proto
    calculation.update(player, ui_state.context.subfactory, true)
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