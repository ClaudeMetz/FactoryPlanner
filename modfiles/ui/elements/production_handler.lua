production_handler = {}

-- ** LOCAL UTIL **
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
        local relevant_line = (line.subfloor == nil) and line or Floor.get(line.subfloor, "Line", 1)
        data_util.execute_alt_action(player, "show_recipe",
          {recipe=relevant_line.recipe.proto, line_products=Line.get_in_order(line, "Product")})

    elseif metadata.click == "left" then  -- Attaches a subfloor to this line
        local subfloor = line.subfloor

        if subfloor == nil then
            if not ui_util.check_archive_status(player) then return end

            subfloor = Floor.init(line)  -- attaches itself to the given line automatically
            Subfactory.add(context.subfactory, subfloor)
            calculation.update(player, context.subfactory)
        end

        ui_util.context.set_floor(player, subfloor)
        main_dialog.refresh(player, "subfactory")

    -- Handle removal of clicked (assembly) line
    elseif metadata.action == "delete" then
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

    local relevant_line = (line.subfloor == nil) and line or Floor.get(line.subfloor, "Line", 1)
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
            tooltip_appendage = data_util.get_attributes("machines", machine_proto),
            selected = (current_proto.id == machine_proto.id)
        }

        table.insert(button_definitions, definition)
    end

    return button_definitions
end

local function apply_machine_choice(player, machine_id)
    local ui_state = data_util.get("ui_state", player)
    local machine = ui_state.modal_data.object

    local machine_category_id = global.all_machines.map[machine.proto.category]
    local machine_proto = global.all_machines.categories[machine_category_id].machines[tonumber(machine_id)]
    Line.change_machine(machine.parent, player, machine_proto, nil)

    calculation.update(player, ui_state.context.subfactory)
    main_dialog.refresh(player, "subfactory")
end

local function machine_limit_change(modal_data, textfield)
    -- Sets the state of the hard limit switch according to what the entered limit is
    local switch = modal_data.modal_elements["fp_switch_on_off_options_hard_limit"]
    local machine_limit = tonumber(textfield.text)
    if machine_limit == nil then switch.switch_state = "right" end
    switch.enabled = (machine_limit ~= nil)
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
    -- I don't need to care about relevant lines here because this only gets called on lines without subfloor

    local line_id = tonumber(string.match(button.name, "%d+"))
    local context = data_util.get("context", player)
    local line = Floor.get(context.floor, "Line", line_id)

    if metadata.direction then  -- up/downgrades the machine
        Line.change_machine(line, player, nil, metadata.direction)

        calculation.update(player, context.subfactory)
        main_dialog.refresh(player, "subfactory")

    elseif metadata.alt then  -- resets this machine to its default state
        Line.change_machine(line, player, nil, nil)
        line.machine.limit = nil
        line.machine.hard_limit = false

        calculation.update(player, context.subfactory)
        main_dialog.refresh(player, "subfactory")

    elseif metadata.click == "left" then  -- opens the machine chooser
        local machine_category_id = global.all_machines.map[line.machine.proto.category]
        local category_prototypes = global.all_machines.categories[machine_category_id].machines

        local applicable_prototypes = {}  -- determine whether there's more than one machine for this recipe
        for _, machine_proto in ipairs(category_prototypes) do
            if Line.is_machine_applicable(line, machine_proto) then
                table.insert(applicable_prototypes, machine_proto)
            end
        end

        if #applicable_prototypes > 1 then  -- changing machines only makes sense if there is something to change to
            local modal_data = {
                title = {"fp.pl_machine", 1},
                text = {"fp.chooser_machine", line.recipe.proto.localised_name},
                click_handler = apply_machine_choice,
                button_definitions = compile_machine_chooser_buttons(player, line, applicable_prototypes),
                object = line.machine
            }
            modal_dialog.enter(player, {type="chooser", modal_data=modal_data})
        else
            title_bar.enqueue_message(player, {"fp.error_no_other_machine_choice"}, "error", 1, true)
        end

    elseif metadata.click == "right" then  -- open the machine limit options
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


-- ** TOP LEVEL **
production_handler.gui_events = {
    on_gui_click = {
        {
            pattern = "^fp_sprite%-button_production_recipe_%d+$",
            timeout = 20,
            handler = (function(player, element, metadata)
                handle_recipe_click(player, element, metadata)
            end)
        },
        {
            pattern = "^fp_sprite%-button_production_machine_%d+$",
            handler = (function(player, element, metadata)
                handle_machine_click(player, element, metadata)
            end)
        }
    },
    on_gui_text_changed = {
        {
            pattern = "^fp_textfield_production_percentage_%d+$",
            handler = (function(player, element)
                handle_percentage_change(player, element)
            end)
        }
    },
    on_gui_confirmed = {
        {
            pattern = "^fp_textfield_production_percentage_%d+$",
            handler = (function(player, element)
                handle_percentage_confirmation(player, element)
            end)
        }
    }
}