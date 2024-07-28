require("ui.elements.module_configurator")

-- ** LOCAL UTIL **
local function refresh_machine_frame(player)
    local modal_data = util.globals.modal_data(player)  --[[@as table]]

    local table_machine = modal_data.modal_elements.machine_table
    table_machine.clear()

    local current_proto = modal_data.object.proto
    for _, machine_proto in pairs(PROTOTYPE_MAPS.machines[current_proto.category].members) do
        if modal_data.line:is_machine_applicable(machine_proto) then
            local attributes = prototyper.util.get_attributes(machine_proto)
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
    local modal_data = util.globals.modal_data(player)  --[[@as table]]
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
        local category = PROTOTYPE_MAPS.fuels[category_name]
        if category ~= nil then
            for _, fuel_proto in pairs(category.members) do
                local attributes = prototyper.util.get_attributes(fuel_proto)
                local tooltip = {"", {"fp.tt_title", fuel_proto.localised_name}, "\n", attributes}

                local selected = (current_proto.category == fuel_proto.category and current_proto.id == fuel_proto.id)
                local button_style = (selected) and "flib_slot_button_green" or "flib_slot_button_default"

                modal_elements.fuel_table.add{type="sprite-button", sprite=fuel_proto.sprite,
                    tags={mod="fp", on_gui_click="choose_fuel", proto_id=(category.id .. "_" .. fuel_proto.id)},
                    tooltip=tooltip, style=button_style, mouse_button_filter={"left"}}
            end
        end
    end
end

local function refresh_limit_elements(player)
    local modal_data = util.globals.modal_data(player)  --[[@as table]]
    local textfield = modal_data.modal_elements.limit_textfield
    local switch = modal_data.modal_elements.force_limit_switch

    local machine = modal_data.object
    textfield.text = tostring(machine.limit or "")
    switch.switch_state = util.gui.switch.convert_to_state(machine.force_limit)
    switch.enabled = (machine.limit ~= nil)
end


local function add_choices_frame(parent_frame, modal_elements, type)
    local frame_choices = parent_frame.add{type="frame", direction="vertical", style="fp_frame_bordered_stretch"}
    frame_choices.style.width = MAGIC_NUMBERS.module_dialog_element_width

    local flow_choices = frame_choices.add{type="flow", direction="horizontal"}
    flow_choices.style.padding = {0, 0, -4, 0}
    flow_choices.style.vertical_align = "center"

    flow_choices.add{type="label", caption={"fp.pu_" .. type, 1}, style="semibold_label"}

    if type == "fuel" then
        local label_info = flow_choices.add{type="label", caption={"fp.machine_does_not_use_fuel"}}
        label_info.style.padding = {9, 0, 9, 24}  -- make sure spacing stays the same when no fuel button is shown
        modal_elements["fuel_info_label"] = label_info
    end

    flow_choices.add{type="empty-widget", style="flib_horizontal_pusher"}

    local flow = flow_choices.add{type="flow", direction="horizontal"}
    flow.style.left_margin = 12
    local frame = flow.add{type="frame", direction="horizontal", style="fp_frame_light_slots"}
    local table = frame.add{type="table", column_count=8, style="filter_slot_table"}
    modal_elements[type .. "_table"] = table

end

local function add_limit_frame(parent_frame, modal_elements)
    local frame_limit = parent_frame.add{type="frame", direction="horizontal", style="fp_frame_module"}

    frame_limit.add{type="label", caption={"fp.info_label", {"fp.machine_limit"}},
        tooltip={"fp.machine_limit_tt"}, style="semibold_label"}
    local textfield_limit = frame_limit.add{type="textfield", tags={mod="fp", on_gui_text_changed="machine_limit"}}
    textfield_limit.style.width = 45
    textfield_limit.style.right_margin = 12
    util.gui.setup_numeric_textfield(textfield_limit, true, false)
    modal_elements["limit_textfield"] = textfield_limit

    frame_limit.add{type="label", caption={"fp.info_label", {"fp.machine_force_limit"}},
        tooltip={"fp.machine_force_limit_tt"}, style="semibold_label"}
    local switch_force_limit = util.gui.switch.add_on_off(frame_limit, "machine_force_limit", {}, "left")
    modal_elements["force_limit_switch"] = switch_force_limit
end


local function handle_machine_choice(player, tags, _)
    local machine = util.globals.modal_data(player).object

    local machine_category_id = PROTOTYPE_MAPS.machines[machine.proto.category].id
    local machine_proto = global.prototypes.machines[machine_category_id].members[tags.proto_id]

    -- This can't use Line:change_machine_to_proto() as that modifies the line, which we can't do
    machine.proto = machine_proto
    machine:normalize_fuel(player)
    machine.module_set:normalize({compatibility=true, trim=true, effects=true})

    -- Make sure the line's beacon is removed if this machine no longer supports it
    if not machine:uses_effects() then machine.parent:set_beacon(nil) end

    refresh_machine_frame(player)
    refresh_fuel_frame(player)
    module_configurator.refresh_modules_flow(player, false)
end

local function handle_fuel_choice(player, tags, _)
    local machine = util.globals.modal_data(player).object

    local split_id = util.split_string(tags.proto_id, "_")
    machine.fuel.proto = global.prototypes.fuels[split_id[1]].members[split_id[2]]

    refresh_fuel_frame(player)
end

local function change_machine_limit(player, _, event)
    local machine = util.globals.modal_data(player).object

    machine.limit = tonumber(event.element.text)
    if machine.limit == nil then machine.force_limit = true end

    refresh_limit_elements(player)
end

local function change_machine_force_limit(player, _, event)
    local machine = util.globals.modal_data(player).object

    local switch_state = util.gui.switch.convert_to_boolean(event.element.switch_state)
    machine.force_limit = switch_state

    refresh_limit_elements(player)
end


local function open_machine_dialog(player, modal_data)
    modal_data.object = OBJECT_INDEX[modal_data.machine_id]
    modal_data.line = modal_data.object.parent

    local modal_elements = modal_data.modal_elements
    local content_frame = modal_elements.content_frame

    modal_data.machine_backup = modal_data.object:clone()
    modal_data.beacon_backup = modal_data.line.beacon and modal_data.line.beacon:clone()
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

local function close_machine_dialog(player, action)
    local modal_data = util.globals.modal_data(player)  --[[@as table]]
    local machine, line = modal_data.object, modal_data.line

    if action == "submit" then
        machine.module_set:normalize({sort=true})

        solver.update(player)
        util.raise.refresh(player, "factory")

    else  -- action == "cancel"
        line.machine = modal_data.machine_backup
        line.machine.module_set:normalize({effects=true})
        line:set_beacon(modal_data.beacon_backup)
    end
end


-- ** EVENTS **
local listeners = {}

listeners.gui = {
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

listeners.dialog = {
    dialog = "machine",
    metadata = (function(modal_data)
        local machine = OBJECT_INDEX[modal_data.machine_id]
        local recipe_name = machine.parent.recipe_proto.localised_name
        return {
            caption = {"", {"fp.edit"}, " ", {"fp.pl_machine", 1}},
            subheader_text = {"fp.machine_dialog_description", recipe_name},
            create_content_frame = true,
            show_submit_button = true
        }
    end),
    open = open_machine_dialog,
    close = close_machine_dialog
}

return { listeners }
