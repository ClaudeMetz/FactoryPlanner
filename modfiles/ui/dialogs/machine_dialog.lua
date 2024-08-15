require("ui.elements.module_configurator")

-- ** LOCAL UTIL **
local function refresh_fuel_frame(player)
    local modal_data = util.globals.modal_data(player)  --[[@as table]]
    local modal_elements = modal_data.modal_elements
    local machine = modal_data.object

    local machine_burner = machine.proto.burner
    modal_elements.fuel_label.visible = (machine_burner == nil)
    modal_elements.fuel_button.visible = (machine_burner ~= nil)

    if machine_burner == nil then return end
    local fuel_proto = machine.fuel.proto

    modal_elements.fuel_button.elem_value = fuel_proto.name
    modal_elements.fuel_button.elem_filters = machine:compile_fuel_filter()
end


local function create_choice_frame(parent_frame, label_caption)
    local frame_choices = parent_frame.add{type="frame", direction="horizontal", style="fp_frame_bordered_stretch"}
    frame_choices.style.width = (MAGIC_NUMBERS.module_dialog_element_width / 2) - 2

    local flow_choices = frame_choices.add{type="flow", direction="horizontal"}
    flow_choices.style.vertical_align = "center"

    flow_choices.add{type="label", caption=label_caption, style="semibold_label"}
    flow_choices.add{type="empty-widget", style="flib_horizontal_pusher"}

    return flow_choices
end

local function add_machine_frame(parent_frame, player, line)
    local modal_elements = util.globals.modal_data(player).modal_elements
    local flow_choices = create_choice_frame(parent_frame, {"fp.pu_machine", 1})

    local button_machine = flow_choices.add{type="choose-elem-button", elem_type="entity-with-quality",
        tags={mod="fp", on_gui_elem_changed="choose_machine"}, style="fp_sprite-button_inset",
        elem_filters=line:compile_machine_filter()}
    button_machine.elem_value = line.machine:elem_value()
    modal_elements["machine_button"] = button_machine
end

local function add_fuel_frame(parent_frame, player)
    local modal_elements = util.globals.modal_data(player).modal_elements
    local flow_choices = create_choice_frame(parent_frame, {"fp.pu_fuel", 1})

    local label_fuel = flow_choices.add{type="label", caption={"fp.machine_no_fuel_required"}}
    label_fuel.style.padding = {6, 4}
    modal_elements["fuel_label"] = label_fuel

    local button_fuel = flow_choices.add{type="choose-elem-button", elem_type="item",
        tags={mod="fp", on_gui_elem_changed="choose_fuel"}, style="fp_sprite-button_inset"}
    -- Need to set elem filters dynamically depending on the machine
    modal_elements["fuel_button"] = button_fuel

    refresh_fuel_frame(player)
end


local function add_limit_frame(parent_frame, player)
    local modal_data = util.globals.modal_data(player)  --[[@as table]]
    local machine = modal_data.object

    local frame_limit = parent_frame.add{type="frame", direction="horizontal", style="fp_frame_module"}
    frame_limit.add{type="label", caption={"fp.info_label", {"fp.machine_limit"}},
        tooltip={"fp.machine_limit_tt"}, style="semibold_label"}

    local textfield_width = 45
    local textfield_limit = frame_limit.add{type="textfield", tags={mod="fp", on_gui_text_changed="machine_limit",
        on_gui_confirmed="machine_limit", width=textfield_width}, tooltip={"fp.expression_textfield"},
        text=machine.limit}
    textfield_limit.lose_focus_on_confirm = true
    textfield_limit.style.width = textfield_width
    modal_data.modal_elements["limit_textfield"] = textfield_limit

    local label_force = frame_limit.add{type="label", caption={"fp.info_label", {"fp.machine_force_limit"}},
        tooltip={"fp.machine_force_limit_tt"}, style="semibold_label"}
    label_force.style.left_margin = 12

    local state =  util.gui.switch.convert_to_state(machine.force_limit)
    local switch_force_limit = util.gui.switch.add_on_off(frame_limit, nil, {}, state)
    modal_data.modal_elements["force_limit_switch"] = switch_force_limit
end


local function handle_machine_choice(player, _, event)
    local machine = util.globals.modal_data(player).object  --[[@as Machine]]
    local elem_value = event.element.elem_value

    if not elem_value then
        event.element.elem_value = machine:elem_value()  -- reset the machine so it can't be nil
        util.cursor.create_flying_text(player, {"fp.no_removal", {"fp.pu_machine", 1}})
        return  -- nothing changed
    end

    local new_machine_proto = prototyper.util.find("machines", elem_value.name, machine.proto.category)
    local new_quality_proto = prototyper.util.find("qualities", elem_value.quality, nil)

    -- Can't use Line:change_machine_to_proto() as that modifies the line, which we can't do
    machine.proto = new_machine_proto
    machine.quality_proto = new_quality_proto
    machine:normalize_fuel(player)
    machine.module_set:normalize({compatibility=true, trim=true, effects=true})

    -- Make sure the line's beacon is removed if this machine no longer supports it
    if not machine:uses_effects() then machine.parent:set_beacon(nil) end

    refresh_fuel_frame(player)
    module_configurator.refresh_modules_flow(player, false)
end

local function handle_fuel_choice(player, _, event)
    local machine = util.globals.modal_data(player).object
    local elem_value = event.element.elem_value

    if not elem_value then
        event.element.elem_value = machine.fuel.proto.name  -- reset the fuel so it can't be nil
        util.cursor.create_flying_text(player, {"fp.no_removal", {"fp.pu_fuel", 1}})
        return  -- nothing changed
    end

    for category_name, _ in pairs(machine.proto.burner.categories) do
        local new_proto = prototyper.util.find("fuels", elem_value, category_name)
        if new_proto then machine.fuel.proto = new_proto; break end
    end
end


local function open_machine_dialog(player, modal_data)
    modal_data.object = OBJECT_INDEX[modal_data.machine_id]  --[[@as Machine]]
    modal_data.line = modal_data.object.parent  --[[@as Line]]

    modal_data.machine_backup = modal_data.object:clone()
    modal_data.beacon_backup = modal_data.line.beacon and modal_data.line.beacon:clone()
    modal_data.module_set = modal_data.object.module_set

    local content_frame = modal_data.modal_elements.content_frame

    -- Machine & Fuel
    local flow_machine = content_frame.add{type="flow", direction="horizontal"}
    add_machine_frame(flow_machine, player, modal_data.line)
    add_fuel_frame(flow_machine, player)

    -- Limit
    if modal_data.line.parent.parent.matrix_free_items == nil then
        add_limit_frame(content_frame, player)
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
        machine.limit = util.gui.parse_expression_field(modal_data.modal_elements.limit_textfield)
        machine.force_limit = util.gui.switch.convert_to_state(modal_data.modal_elements.force_limit_switch)

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
    on_gui_elem_changed = {
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
            handler = (function(_, _, event)
                util.gui.update_expression_field(event.element)
            end)
        }
    },
    on_gui_confirmed = {
        {
            name = "machine_limit",
            handler = (function(_, _, event)
                util.gui.confirm_expression_field(event.element)
            end)
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
