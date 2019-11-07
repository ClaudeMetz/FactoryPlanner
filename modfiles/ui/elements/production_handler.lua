-- Handles any clicks on the recipe icon of an (assembly) line
function handle_line_recipe_click(player, line_id, click, direction, alt)
    local ui_state = get_ui_state(player)
    local subfactory = ui_state.context.subfactory
    local floor = ui_state.context.floor
    local line = Floor.get(floor, "Line", line_id)

    local archive_status = ui_util.check_archive_status(player)
    
    if alt then  -- Open item in FNEI
        ui_util.fnei.show_recipe(line.recipe, Line.get_in_order(line, "Product"))

    elseif direction ~= nil then  -- Shift (assembly) line in the given direction
        if archive_status then return end

        -- Can't shift second line into the first position on subfloors
        -- (Top line ignores interaction, so no special handling there)
        if not(direction == "negative" and floor.level > 1 and line.gui_position == 2) then
            Floor.shift(floor, line, direction)
            calculation.update(player, subfactory, true)
        end

    else
        -- Attaches a subfloor to this line
        if click == "left" then
            if line.subfloor == nil then  -- create new subfloor
                if archive_status then return end

                local subfloor = Floor.init(line)
                line.subfloor = Subfactory.add(subfactory, subfloor)
                calculation.update(player, subfactory, false)
            end
            ui_state.current_activity = nil
            data_util.context.set_floor(player, line.subfloor)
            refresh_main_dialog(player)
            
        -- Handle removal of clicked (assembly) line
        elseif click == "right" then
            if archive_status then return end

            if line.subfloor == nil then
                Floor.remove(floor, line)
                calculation.update(player, subfactory, true)
            else
                if ui_state.current_activity == "deleting_line" then
                    Floor.remove(floor, line)
                    ui_state.current_activity = nil
                    calculation.update(player, subfactory, true)
                else
                    ui_state.current_activity = "deleting_line"
                    ui_state.context.line = line
                    refresh_main_dialog(player)
                end
            end
        end
    end
end


-- Handles the changing of the percentage textfield (doesn't refresh the production table yet)
function handle_percentage_change(player, element)
    local ui_state = get_ui_state(player)
    local floor = ui_state.context.floor
    local line = Floor.get(floor, "Line", tonumber(string.match(element.name, "%d+")))

    local new_percentage = tonumber(element.text) or 0
    line.percentage = new_percentage
    
    -- Update related datasets
    if line.subfloor then Floor.get(line.subfloor, "Line", 1).percentage = new_percentage
    elseif line.id == 1 and floor.origin_line then floor.origin_line.percentage = new_percentage end
end

-- Handles the player confirming the given percentage textfield by reloading and refocusing
function handle_percentage_confirmation(player, element)
    local line_id = tonumber(string.match(element.name, "%d+"))
    local ui_state = get_ui_state(player)
    ui_state.current_activity = nil

    local scroll_pane = element.parent.parent
    calculation.update(player, ui_state.context.subfactory, true)
    scroll_pane["table_production_pane"]["fp_textfield_line_percentage_" .. line_id].focus()
end


-- Handles the machine changing process
function handle_machine_change(player, line_id, machine_id, click, direction)
    if ui_util.check_archive_status(player) then return end

    local ui_state = get_ui_state(player)
    local subfactory = ui_state.context.subfactory
    local floor = ui_state.context.floor
    local line = Floor.get(floor, "Line", line_id)
    
    -- machine_id being nil means the user wants to change the machine of this (assembly) line
    if machine_id == nil then
        -- Change the machine to be one tier lower/higher if possible
        if direction ~= nil then
            data_util.machine.change(player, line, nil, direction)
            calculation.update(player, subfactory, true)

        -- Display all the options for this machine category
        elseif click == "left" then            
            -- Changing machines only makes sense if there are more than one in it's category
            if #line.machine.category.machines > 1 then
                if #line.machine.category.machines < 5 then  -- up to 4 machines, no picker is needed
                    ui_state.current_activity = "changing_machine"
                    ui_state.context.line = line  -- won't be reset after use, but that doesn't matter
                    refresh_main_dialog(player)

                else  -- Open a chooser dialog presenting all machine choices
                    local modal_data = {
                        reciever_name = "machine",
                        title = {"label.machine"},
                        text = {"", {"label.chooser_machine"}, " '", line.recipe.proto.localised_name, "':"},
                        object = line.machine
                    }
                    
                    ui_state.context.line = line  -- won't be reset after use, but that doesn't matter
                    enter_modal_dialog(player, {type="chooser", modal_data=modal_data})
                end
            end
        
        -- Open the dialog to set a machine count cap
        elseif click == "right" then
            local modal_data = {
                reciever_name = "machine",
                title = {"label.machine_cap"},
                text = {"", {"label.options_machine_cap"}, " '", line.recipe.proto.localised_name, "':"},
                object = line.machine,
                fields = {
                    {
                        type = "numeric",
                        name = "machine_limit",
                        caption = "Limit",
                        value = line.machine.count_cap or "",
                        focus = true
                    }--[[ ,
                    {
                        type = "on_off_switch",
                        name = "force_limit",
                        caption = "Enforce limit",
                        tooltip = "forces stuff",
                        value = false
                    } ]]
                }
            }

            ui_state.context.line = line  -- won't be reset after use, but that doesn't matter
            enter_modal_dialog(player, {type="options", submit=true, modal_data=modal_data})
        end
    else
        -- Accept the user selection of new machine for this (assembly) line
        if click == "left" then
            local new_machine = global.all_machines.categories[line.machine.category.id].machines[machine_id]
            data_util.machine.change(player, line, new_machine, nil)
            ui_state.current_activity = nil
            calculation.update(player, subfactory, true)
        end
    end
end

-- Generates the buttons for the machine chooser dialog
function generate_chooser_machine_buttons(player)
    local ui_state = get_ui_state(player)
    local line = ui_state.context.line

    for machine_id, machine in ipairs(line.machine.category.machines) do
        if data_util.machine.is_applicable(machine, line.recipe) then
            local button = generate_blank_chooser_button(player, machine_id)
            -- The actual button is setup by the method shared by non-chooser machine buttons
            setup_machine_choice_button(player, button, machine, ui_state.modal_data.object.proto.id, 36)
        end
    end
end

-- Recieves the result of the machine choice and applies it
function apply_chooser_machine_choice(player, machine_id)
    local context = get_context(player)
    local machine = global.all_machines.categories[context.line.machine.category.id].machines[tonumber(machine_id)]
    data_util.machine.change(player, context.line, machine, nil)
    calculation.update(player, context.subfactory, false)
end

-- Recieves the result of the machine cap choice and applies it
function apply_options_machine_choice(player, machine, options)
    local context = get_context(player)
    -- tonumber() has already converted an empty string to nil
    Line.set_machine_count_cap(context.line, options.machine_limit)
    calculation.update(player, context.subfactory, false)
end


-- Handles a click on an existing module or on the add-module-button
function handle_line_module_click(player, line_id, module_id, click, direction, alt)
    if ui_util.check_archive_status(player) then return end

    local ui_state = get_ui_state(player)
    local floor = ui_state.context.floor
    local line = Floor.get(floor, "Line", line_id)
    ui_state.context.line = line
    local limit = Line.empty_slots(line)

    if module_id == nil then  -- meaning the add-module-button was pressed
        enter_modal_dialog(player, {type="module", object=nil, submit=true, modal_data={empty_slots=limit}})

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
                end
            end

            -- alt modifies the module amount, no alt modifies the module tier
            if direction == "positive" then
                if alt then
                    local new_amount = math.min(module.amount + 1, module.amount + limit)
                    Line.change_module_amount(line, module, new_amount)
                else
                    handle_tier_change(1)
                end

            else  -- direction == "negative"
                if alt then
                    local new_amount = module.amount - 1
                    if new_amount == 0 then 
                        Line.remove(line, module)
                    else
                        Line.change_module_amount(line, module, new_amount)
                    end
                else
                    handle_tier_change(-1)
                end
            end

            calculation.update(player, ui_state.context.subfactory, true)

        else
            if click == "left" then  -- open the modules modal dialog
                enter_modal_dialog(player, {type="module", object=module, submit=true, delete=true,
                  modal_data={empty_slots=(limit + module.amount), selected_module=module.proto}})

            else  -- click == "right"; delete the module
                Line.remove(line, module)
                calculation.update(player, ui_state.context.subfactory, true)

            end
        end
    end
end

-- Handles a click on an existing beacon/beacon-module or on the add-beacon-button
function handle_line_beacon_click(player, line_id, type, click, direction, alt)
    if ui_util.check_archive_status(player) then return end

    local ui_state = get_ui_state(player)
    local floor = ui_state.context.floor
    local line = Floor.get(floor, "Line", line_id)
    ui_state.context.line = line

    if type == nil then  -- meaning the add-beacon-button was pressed
        local limit = get_preferences(player).preferred_beacon.module_limit
        enter_modal_dialog(player, {type="beacon", object=nil, submit=true, modal_data={empty_slots=limit}})

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
                end
            end

            -- alt modifies the module amount, no alt modifies the module tier
            if direction == "positive" then
                if alt then
                    local new_amount = math.min(module.amount + 1, line.beacon.proto.module_limit)
                    local new_module = Module.init_by_proto(module.proto, tonumber(new_amount))
                    Beacon.set_module(line.beacon, new_module)
                else
                    handle_tier_change(1)
                end

            else  -- direction == "negative"
                if alt then
                    local new_amount = module.amount - 1
                    if new_amount == 0 then 
                        Line.remove_beacon(line)
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

            -- alt modifies the beacon amount, no alt modifies the beacon tier
            if direction == "positive" then
                if alt then
                    local new_beacon = Beacon.init_by_protos(beacon.proto, beacon.amount + 1, beacon.module.proto,
                      beacon.module.amount)
                    Line.set_beacon(line, new_beacon)
                else
                    local new_proto = global.all_beacons.beacons[beacon.proto.id + 1]
                    if new_proto ~= nil then
                        local new_beacon = Beacon.init_by_protos(new_proto, beacon.amount, beacon.module.proto,
                          beacon.module.amount)
                        Line.set_beacon(line, new_beacon)
                    end
                end

            else  -- direction == "negative"
                if alt then
                    local new_amount = beacon.amount - 1
                    if new_amount == 0 then 
                        Line.remove_beacon(line)
                    else
                        local new_beacon = Beacon.init_by_protos(beacon.proto, new_amount, beacon.module.proto,
                      beacon.module.amount)
                    Line.set_beacon(line, new_beacon)
                    end
                else
                    local new_proto = global.all_beacons.beacons[beacon.proto.id - 1]
                    if new_proto ~= nil then
                        local new_beacon = Beacon.init_by_protos(new_proto, beacon.amount, beacon.module.proto,
                          beacon.module.amount)
                        Line.set_beacon(line, new_beacon)
                    end
                end
            end
        end

        calculation.update(player, ui_state.context.subfactory, true)

    else  -- click is left or right, makes no difference
        local beacon = line.beacon
        enter_modal_dialog(player, {type="beacon", object=beacon, submit=true, delete=true, modal_data=
          {empty_slots=beacon.proto.module_limit, selected_beacon=beacon.proto, selected_module=beacon.module.proto}})
    end
end


-- Handles a click on any of the 3 item buttons of a specific line
function handle_item_button_click(player, line_id, class, item_id, click, direction, alt)
    if ui_util.check_archive_status(player) then return end

    local ui_state = get_ui_state(player)
    local line = Floor.get(ui_state.context.floor, "Line", line_id)
    local item = Line.get(line, class, item_id)

    if alt then  -- Open item in FNEI
        ui_util.fnei.show_item(item, click)

    elseif direction ~= nil then  -- Shift item in the given direction
        Line.shift(line, item, direction)
        refresh_production_table(player)
        
    else
        if click == "right" and item.class == "Fuel" then
            local modal_data = {
                reciever_name = "fuel",
                title = {"label.fuel"},
                object = item
            }

            -- Set different message depending on whether this fuel is on a line with a subfloor or not
            if line.subfloor == nil then
                modal_data.text = {"", {"label.chooser_fuel_line"}, " '", line.machine.proto.localised_name, "':"}
            else
                modal_data.text = {"", {"label.chooser_fuel_floor"}, " '", item.proto.localised_name, "':"}
            end

            ui_state.context.line = line  -- won't be reset after use, but that doesn't matter
            enter_modal_dialog(player, {type="chooser", modal_data=modal_data})

        -- Pick recipe to produce said ingredient
        elseif click == "left" and item.proto.type ~= "entity" then
            if item.class == "Ingredient" or item.class == "Fuel" then
                enter_modal_dialog(player, {type="recipe_picker", object=item, modal_data={production_type="produce"}})

            elseif item.class == "Product" then
                if line.Product.count < 2 then
                    ui_util.message.enqueue(player, {"label.error_no_prioritizing_single_product"}, "error", 1)
                else
                    local priority_product_proto = (line.priority_product_proto ~= item.proto) and item.proto or nil
                    Line.set_priority_product(line, priority_product_proto)
                    calculation.update(player, ui_state.context.subfactory, true)
                end

            elseif item.class == "Byproduct" then
                --enter_modal_dialog(player, {type="recipe_picker", object=item, modal_data={production_type="consume"}})
            end
        end
    end
end

-- Generates the buttons for the fuel chooser dialog
function generate_chooser_fuel_buttons(player)
    local player_table = get_table(player)
    local ui_state = get_ui_state(player)
    local view = ui_state.view_state[ui_state.view_state.selected_view_id]
    local line = ui_state.context.line

    local old_fuel_id = global.all_fuels.map[ui_state.modal_data.object.proto.name]
    local machine = line.machine
    for new_fuel_id, fuel_proto in pairs(global.all_fuels.fuels) do
        local selected = (old_fuel_id == new_fuel_id) and {"", " (", {"tooltip.selected"}, ")"} or ""
        local tooltip = {"", fuel_proto.localised_name, selected}

        local fuel_amount = nil
        -- Only add number information if this line has no subfloor (really difficult calculations otherwise)
        if line.subfloor == nil then
            local energy_consumption = calculation.util.determine_energy_consumption(machine.proto, machine.count,
              line.total_effects)  -- don't care about mining productivity in this case, only the consumption-effect
            fuel_amount = calculation.util.determine_fuel_amount(energy_consumption, machine.proto.burner,
              fuel_proto.fuel_value, ui_state.context.subfactory.timescale)

            fuel_amount = ui_util.calculate_item_button_number(player_table, view, fuel_amount,
              fuel_proto.type, line.machine.count)
            fuel_amount = ui_util.format_number(fuel_amount, 4)

            local m = (tonumber(fuel_amount) == 1) and {"tooltip.item"} or {"tooltip.items"}
            tooltip = {"", tooltip, "\n", fuel_amount, " ", m}
        end
        tooltip = {"", tooltip, "\n", ui_util.generate_fuel_attributes_tooltip(fuel_proto)}

        local button = generate_blank_chooser_button(player, new_fuel_id)
        if old_fuel_id == new_fuel_id then button.style = "fp_button_icon_large_green" end
        button.sprite = fuel_proto.sprite
        button.number = fuel_amount
        button.tooltip = tooltip
    end
end

-- Recieves the result of a chooser user choice and applies it
function apply_chooser_fuel_choice(player, new_fuel_id)
    local context = get_context(player)
    local line = context.line

    local old_fuel = get_ui_state(player).modal_data.object.proto
    local new_fuel = global.all_fuels.fuels[tonumber(new_fuel_id)]
    
    -- Sets the new fuel to all relevant lines on the given floor and all it's subfloors
    local function apply_fuel_to_floor(floor)
        for _, line in ipairs(Floor.get_in_order(floor, "Line")) do
            if line.subfloor == nil then
                local current_fuel = Line.get_by_name(line, "Fuel", old_fuel.name)
                if current_fuel ~= nil then current_fuel.proto = new_fuel end
            else
                apply_fuel_to_floor(line.subfloor)
            end
        end
    end
    
    if line.subfloor == nil then  -- subfloor-less lines are always limited to 1 fuel type
        Line.get_by_gui_position(line, "Fuel", 1).proto = new_fuel
        if line.id == 1 and line.parent and line.parent.level > 1 then
            Line.get_by_gui_position(line.parent.origin_line, "Fuel", 1).proto = new_fuel
        end
    else
        apply_fuel_to_floor(line.subfloor)
    end

    calculation.update(player, context.subfactory, false)
end


-- Handles the changing of the comment textfield
function handle_comment_change(player, element)
    local line = Floor.get(get_context(player).floor, "Line", tonumber(string.match(element.name, "%d+")))
    line.comment = element.text
end

-- Clears all comments on the current floor
function clear_recipe_comments(player)
    local floor = get_context(player).floor
    for _, line in ipairs(Floor.get_in_order(floor, "Line")) do
        line.comment = nil
    end
    refresh_production_pane(player)
end