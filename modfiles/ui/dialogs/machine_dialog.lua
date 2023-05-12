require("ui.elements.module_configurator")

machine_dialog = {}

-- ** LOCAL UTIL **
local function refresh_machine_frame(player)
    local modal_data = data_util.get("modal_data", player)

    local table_machine = modal_data.modal_elements.machine_table
    table_machine.clear()

    local current_proto = modal_data.object.proto
    local machine_category_id = global.all_machines.map[current_proto.category]
    local category_prototypes = global.all_machines.categories[machine_category_id].machines

    for _, machine_proto in ipairs(category_prototypes) do
        if Line.is_machine_applicable(modal_data.line, machine_proto) then
            local attributes = data_util.get_attributes("machines", machine_proto)
            local tooltip = {"", {"fp.tt_title", machine_proto.localised_name}, "\n", attributes}

            local selected = (machine_proto.id == current_proto.id)
            local button_style = (selected) and "flib_slot_button_green" or "flib_slot_button_default"

            table_machine.add{type="sprite-button", sprite=machine_proto.sprite, tooltip=tooltip,
                tags={mod="fp", on_gui_click="choose_machine", proto_id=machine_proto.id},
                style=button_style, mouse_button_filter={"left"}}
        end
    end
end

local function refresh_fuel_frame(player)
    local modal_data = data_util.get("modal_data", player)
    local machine = modal_data.object

    local modal_elements = modal_data.modal_elements
    modal_elements.fuel_table.clear()

    local machine_burner = machine.proto.burner
    modal_elements.fuel_table.visible = (machine_burner ~= nil)
    modal_elements.fuel_info_label.visible = (machine_burner == nil)

    if machine_burner == nil then return end
    local current_proto = machine.fuel.proto

    -- Applicable fuels come from all categories that this burner supports
    for category_name, _ in pairs(machine_burner.categories) do
        local category_id = global.all_fuels.map[category_name]
        if category_id ~= nil then
            for _, fuel_proto in pairs(global.all_fuels.categories[category_id].fuels) do
                local attributes = data_util.get_attributes("fuels", fuel_proto)
                local tooltip = {"", {"fp.tt_title", fuel_proto.localised_name}, "\n", attributes}

                local selected = (current_proto.category == fuel_proto.category and current_proto.id == fuel_proto.id)
                local button_style = (selected) and "flib_slot_button_green" or "flib_slot_button_default"

                modal_elements.fuel_table.add{type="sprite-button", sprite=fuel_proto.sprite,
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

    local machine = modal_data.object
    textfield.text = tostring(machine.limit or "")
    switch.switch_state = ui_util.switch.convert_to_state(machine.force_limit)
    switch.enabled = (machine.limit ~= nil)
end


local function add_choices_frame(parent_frame, modal_elements, type)
    local frame_choices = parent_frame.add{type="frame", direction="vertical", style="fp_frame_bordered_stretch"}
    local table_choices = frame_choices.add{type="table", column_count=3}
    table_choices.style.horizontal_spacing = 20
    table_choices.style.padding = {0, 0, -4, 0}

    table_choices.add{type="label", caption={"fp.pu_" .. type, 1}, style="heading_3_label"}

    local flow = table_choices.add{type="flow", direction="horizontal"}
    local frame = flow.add{type="frame", direction="horizontal", style="slot_button_deep_frame"}
    local table = frame.add{type="table", column_count=7, style="filter_slot_table"}
    modal_elements[type .. "_table"] = table

    if type == "fuel" then
        local label_info = flow.add{type="label", caption={"fp.machine_does_not_use_fuel"}}
        label_info.style.padding = {10, -8}  -- make sure spacing stays the same when no fuel button is shown
        modal_elements["fuel_info_label"] = label_info
    end
end

local function add_limit_frame(parent_frame, modal_elements)
    local frame_limit = parent_frame.add{type="frame", direction="horizontal", style="fp_frame_bordered_stretch"}
    local table_limit = frame_limit.add{type="table", column_count=2}
    table_limit.style.horizontal_spacing = 20
    table_limit.style.padding = {6, 0, 2, 0}
    local flow_limit = table_limit.add{type="flow", direction="horizontal", style="fp_flow_horizontal_centered"}

    flow_limit.add{type="label", caption={"fp.info_label", {"fp.machine_limit"}},
        tooltip={"fp.machine_limit_tt"}, style="heading_3_label"}
    local textfield_limit = flow_limit.add{type="textfield", tags={mod="fp", on_gui_text_changed="machine_limit"}}
    textfield_limit.style.width = 45
    ui_util.setup_numeric_textfield(textfield_limit, true, false)
    modal_elements["limit_textfield"] = textfield_limit

    local flow_force_limit = table_limit.add{type="flow", direction="horizontal", style="fp_flow_horizontal_centered"}
    flow_force_limit.add{type="label", caption={"fp.info_label", {"fp.machine_force_limit"}},
        tooltip={"fp.machine_force_limit_tt"}, style="heading_3_label"}
    local switch_force_limit = ui_util.switch.add_on_off(flow_force_limit, "machine_force_limit", {}, "left")
    modal_elements["force_limit_switch"] = switch_force_limit
end


local function handle_machine_choice(player, tags, _)
    local modal_data = data_util.get("modal_data", player)
    local machine = modal_data.object

    local machine_category_id = global.all_machines.map[machine.proto.category]
    local machine_proto = global.all_machines.categories[machine_category_id].machines[tags.proto_id]

    -- This can't use Line.change_machine_to_proto() as that modifies the line, which we can't do
    machine.proto = machine_proto
    Machine.normalize_fuel(machine, player)
    ModuleSet.normalize(machine.module_set, {compatibility=true, trim=true, effects=true})

    -- Make sure the line's beacon is removed if this machine no longer supports it
    if machine.proto.allowed_effects == nil then Line.set_beacon(machine.parent, nil) end

    refresh_machine_frame(player)
    refresh_fuel_frame(player)
    module_configurator.refresh_modules_flow(player, false)
end

local function handle_fuel_choice(player, tags, _)
    local modal_data = data_util.get("modal_data", player)

    local split_id = util.split(tags.proto_id, "_")
    local category_id, fuel_id = tonumber(split_id[1]), tonumber(split_id[2])
    local new_fuel_proto = global.all_fuels.categories[category_id].fuels[fuel_id]
    modal_data.object.fuel.proto = new_fuel_proto

    refresh_fuel_frame(player)
end

local function change_machine_limit(player, _, event)
    local modal_data = data_util.get("modal_data", player)
    local machine = modal_data.object

    machine.limit = tonumber(event.element.text)
    if machine.limit == nil then machine.force_limit = true end

    refresh_limit_elements(player)
end

local function change_machine_force_limit(player, _, event)
    local modal_data = data_util.get("modal_data", player)

    local switch_state = ui_util.switch.convert_to_boolean(event.element.switch_state)
    modal_data.object.force_limit = switch_state

    refresh_limit_elements(player)
end


-- ** TOP LEVEL **
machine_dialog.dialog_settings = (function(modal_data)
    local recipe_name = modal_data.line.recipe.proto.localised_name
    return {
        caption = {"", {"fp.edit"}, " ", {"fp.pl_machine", 1}},
        subheader_text = {"fp.machine_dialog_description", recipe_name},
        create_content_frame = true,
        show_submit_button = true
    }
end)

function machine_dialog.open(player, modal_data)
    local modal_elements = modal_data.modal_elements
    local content_frame = modal_elements.content_frame
    content_frame.style.minimal_width = MODULE_DIALOG_WIDTH

    modal_data.machine_backup = Machine.clone(modal_data.object)
    modal_data.beacon_backup = Beacon.clone(modal_data.line.beacon)
    modal_data.module_set = modal_data.object.module_set

    -- Choices
    add_choices_frame(content_frame, modal_elements, "machine")
    refresh_machine_frame(player)
    add_choices_frame(content_frame, modal_elements, "fuel")
    refresh_fuel_frame(player)

    -- Limit
    if modal_data.line.parent.parent.matrix_free_items == nil then
        add_limit_frame(content_frame, modal_elements)
        refresh_limit_elements(player)
    end

    -- Modules
    module_configurator.add_modules_flow(content_frame, modal_data)
    module_configurator.refresh_modules_flow(player, false)
end

function machine_dialog.close(player, action)
    local modal_data = data_util.get("modal_data", player)
    local machine, line = modal_data.object, modal_data.line

    if action == "submit" then
        ModuleSet.normalize(machine.module_set, {sort=true})

        local subfactory = data_util.get("context", player).subfactory
        solver.update(player, subfactory)
        main_dialog.refresh(player, "subfactory")

    else  -- action == "cancel"
        line.machine = modal_data.machine_backup
        ModuleSet.normalize(line.machine.module_set, {effects=true})
        Line.set_beacon(modal_data.line, modal_data.beacon_backup)
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
            handler = change_machine_limit
        }
    },
    on_gui_switch_state_changed = {
        {
            name = "machine_force_limit",
            handler = change_machine_force_limit
        }
    }
}
