machine_dialog = {}

-- ** LOCAL UTIL **
local choice_structures = {}

function choice_structures.refresh_machine(player)
    local ui_state = data_util.get("ui_state", player)
    local line = ui_state.modal_data.line

    local table_machine = ui_state.modal_data.modal_elements.machine_table
    table_machine.clear()

    local machine_category_id = global.all_machines.map[line.machine.proto.category]
    local category_prototypes = global.all_machines.categories[machine_category_id].machines
    local current_proto = line.machine.proto

    local round_button_numbers = data_util.get("preferences", player).round_button_numbers
    local timescale = ui_state.context.subfactory.timescale

    for _, machine_proto in ipairs(category_prototypes) do
        if Line.is_machine_applicable(line, machine_proto) then
            -- Need to get total effects here to include mining productivity
            local crafts_per_tick = calculation.util.determine_crafts_per_tick(machine_proto,
              line.recipe.proto, line.total_effects)
            local machine_count = calculation.util.determine_machine_count(crafts_per_tick,
              line.uncapped_production_ratio, timescale, machine_proto.launch_sequence_time)

            local button_number = (round_button_numbers) and math.ceil(machine_count) or machine_count

            -- Have to do this stupid crap because localisation plurals only work on integers
            local formatted_number = ui_util.format_number(machine_count, 4)
            local plural_parameter = (formatted_number == "1") and 1 or 2
            local amount_line = {"fp.two_word_title", formatted_number, {"fp.pl_machine", plural_parameter}}

            local attributes = data_util.get_attributes("machines", machine_proto)
            local tooltip = {"", machine_proto.localised_name, "\n", amount_line, "\n\n", attributes}

            local selected = (machine_proto.id == current_proto.id)
            local button_style = (selected) and "flib_slot_button_green" or "flib_slot_button_default"

            table_machine.add{type="sprite-button", sprite=machine_proto.sprite, number=button_number,
              tooltip=tooltip, tags={mod="fp", on_gui_click="choose_machine", proto_id=machine_proto.id},
              style=button_style, mouse_button_filter={"left"}}
        end
    end
end

function choice_structures.refresh_fuel(player)
    local ui_state = data_util.get("ui_state", player)
    local line = ui_state.modal_data.line

    local modal_elements = ui_state.modal_data.modal_elements
    modal_elements.fuel_table.clear()

    local machine_burner = line.machine.proto.burner
    modal_elements.fuel_table.visible = (machine_burner ~= nil)
    modal_elements.fuel_info_label.visible = (machine_burner == nil)
    if machine_burner == nil then return end

    local view_state_metadata = view_state.generate_metadata(player, ui_state.context.subfactory, 4, true)
    local timescale = ui_state.context.subfactory.timescale
    local current_proto = line.machine.fuel.proto

    local energy_consumption = calculation.util.determine_energy_consumption(line.machine.proto, line.machine.count,
      line.total_effects)  -- don't care about mining productivity in this case, only the consumption-effect

    -- Applicable fuels come from all categories that this burner supports
    for category_name, _ in pairs(line.machine.proto.burner.categories) do
        local category_id = global.all_fuels.map[category_name]
        if category_id ~= nil then
            for _, fuel_proto in pairs(global.all_fuels.categories[category_id].fuels) do
                local raw_fuel_amount = calculation.util.determine_fuel_amount(energy_consumption, machine_burner,
                  fuel_proto.fuel_value, timescale)
                local amount, number_tooltip = view_state_metadata.processor(view_state_metadata, raw_fuel_amount,
                  fuel_proto, line.machine.count)  -- Raw processor call because we only have a prototype, no object

                local attributes = data_util.get_attributes("fuels", fuel_proto)
                local tooltip = {"", fuel_proto.localised_name, "\n", number_tooltip, "\n\n", attributes}

                local selected = (current_proto.category == fuel_proto.category and current_proto.id == fuel_proto.id)
                local button_style = (selected) and "flib_slot_button_green" or "flib_slot_button_default"

                modal_elements.fuel_table.add{type="sprite-button", sprite=fuel_proto.sprite, number=amount,
                  tags={mod="fp", on_gui_click="choose_fuel", proto_id=(category_id .. "_" .. fuel_proto.id)},
                  tooltip=tooltip, style=button_style, mouse_button_filter={"left"}}
            end
        end
    end
end

local function refresh_limit_elements(player)
    local modal_data = data_util.get("modal_data", player)
    local textfield = modal_data.modal_elements.limit_textfield
    local switch = modal_data.modal_elements.force_limit_switch

    textfield.text = tostring(modal_data.object.limit or "")
    switch.switch_state = ui_util.switch.convert_to_state(modal_data.object.force_limit)
    switch.enabled = (modal_data.object.limit ~= nil)
end


local function add_choices_row(player, type, table_choices)
    local modal_elements = data_util.get("modal_elements", player)

    local label = table_choices.add{type="label", caption={"fp.pu_" .. type, 1}}
    label.style.font = "heading-3"

    local flow = table_choices.add{type="flow", direction="horizontal"}
    local frame = flow.add{type="frame", direction="horizontal", style="slot_button_deep_frame"}
    local table = frame.add{type="table", column_count=8, style="filter_slot_table"}
    modal_elements[type .. "_table"] = table

    if type == "fuel" then
        local label_info = flow.add{type="label", caption={"fp.machine_does_not_use_fuel"}}
        label_info.style.padding = {10, -8}
        modal_elements["fuel_info_label"] = label_info
    end

    choice_structures["refresh_" .. type](player)
end

local function add_limit_frame(content_frame, modal_elements)
    local frame_limit = content_frame.add{type="frame", direction="horizontal", style="fp_frame_bordered_stretch"}
    local table_limit = frame_limit.add{type="table", column_count=2}
    table_limit.style.horizontal_spacing = 20
    table_limit.style.margin = {4, 0}
    local flow_limit = table_limit.add{type="flow", direction="horizontal", style="fp_flow_horizontal_centered"}

    local label_limit = flow_limit.add{type="label", caption={"fp.info_label", {"fp.machine_limit"}},
      tooltip={"fp.machine_limit_tt"}}
    label_limit.style.font = "heading-3"
    local textfield_limit = flow_limit.add{type="textfield", tags={mod="fp", on_gui_text_changed="machine_limit"}}
    textfield_limit.style.width = 45
    ui_util.setup_numeric_textfield(textfield_limit, true, false)
    modal_elements["limit_textfield"] = textfield_limit

    local flow_force_limit = table_limit.add{type="flow", direction="horizontal", style="fp_flow_horizontal_centered"}
    local label_force_limit = flow_force_limit.add{type="label", caption={"fp.info_label", {"fp.machine_force_limit"}},
      tooltip={"fp.machine_force_limit_tt"}}
    label_force_limit.style.font = "heading-3"
    local switch_force_limit = ui_util.switch.add_on_off(flow_force_limit, "machine_force_limit", {}, "left")
    modal_elements["force_limit_switch"] = switch_force_limit
end


local function handle_machine_choice(player, tags, _)
    local modal_data = data_util.get("modal_data", player)
    local current_machine = modal_data.object

    local machine_category_id = global.all_machines.map[current_machine.proto.category]
    local machine_proto = global.all_machines.categories[machine_category_id].machines[tags.proto_id]
    Line.change_machine_to_proto(modal_data.line, player, machine_proto)

    choice_structures.refresh_machine(player)
    choice_structures.refresh_fuel(player)
    modal_data.refresh = true
end

local function handle_fuel_choice(player, tags, _)
    local modal_data = data_util.get("modal_data", player)

    local split_string = split_string(tags.proto_id, "_")
    local new_fuel_proto = global.all_fuels.categories[split_string[1]].fuels[split_string[2]]
    modal_data.object.fuel.proto = new_fuel_proto

    choice_structures.refresh_fuel(player)
    modal_data.refresh = true
end

local function machine_limit(player, _, event)
    local modal_data = data_util.get("modal_data", player)
    local machine = modal_data.object

    machine.limit = tonumber(event.element.text)
    if machine.limit == nil then machine.force_limit = false end

    refresh_limit_elements(player)
    modal_data.refresh = true
end

local function machine_force_limit(player, _, event)
    local modal_data = data_util.get("modal_data", player)

    local switch_state = ui_util.switch.convert_to_boolean(event.element.switch_state)
    modal_data.object.force_limit = switch_state

    refresh_limit_elements(player)
    modal_data.refresh = true
end


-- ** TOP LEVEL **
machine_dialog.dialog_settings = (function(modal_data)
    return {
        caption = {"fp.two_word_title", {"fp.edit"}, {"fp.pl_machine", 1}},
        subheader_text = {"fp.machine_dialog_description", modal_data.line.recipe.proto.localised_name},
        create_content_frame = true
    }
end)

function machine_dialog.open(player, modal_data)
    local modal_elements = modal_data.modal_elements
    local content_frame = modal_elements.content_frame

    modal_data.refresh = nil  -- set to true if anything about the machine is changed

    -- Choices
    local frame_choices = content_frame.add{type="frame", direction="vertical", style="fp_frame_bordered_stretch"}
    local table_choices = frame_choices.add{type="table", column_count=2}
    table_choices.style.horizontal_spacing = 20
    table_choices.style.vertical_spacing = 16
    table_choices.style.top_margin = 4

    add_choices_row(player, "machine", table_choices)
    add_choices_row(player, "fuel", table_choices)

    -- Limit
    add_limit_frame(content_frame, modal_elements)
    refresh_limit_elements(player)
end

function machine_dialog.close(player, _)
    local ui_state = data_util.get("ui_state", player)

    if ui_state.modal_data.refresh then
        calculation.update(player, ui_state.context.subfactory)
        main_dialog.refresh(player, "production")
    end
end


-- ** EVENTS **
machine_dialog.gui_events = {
    on_gui_click = {
        {
            name = "choose_machine",
            handler = handle_machine_choice
        },
        {
            name = "choose_fuel",
            handler = handle_fuel_choice
        }
    },
    on_gui_text_changed = {
        {
            name = "machine_limit",
            handler = machine_limit
        }
    },
    on_gui_switch_state_changed = {
        {
            name = "machine_force_limit",
            handler = machine_force_limit
        }
    }
}
