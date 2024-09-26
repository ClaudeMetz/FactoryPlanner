-- ** LOCAL UTIL **
local function add_checkbox(modal_elements, caption, tooltip, identifier, event_name)
    local tags = (event_name) and {mod="fp", on_gui_checked_state_changed=event_name} or nil
    local checkbox = modal_elements.defaults_flow.add{type="checkbox", state=false,
        caption=caption, tooltip=tooltip, tags=tags}
    modal_elements[identifier] = checkbox
end

local function refresh_defaults_frame(player, reset_all)
    local modal_data = util.globals.modal_data(player)  --[[@as table]]
    local modal_elements = modal_data.modal_elements
    local machine = modal_data.object  --[[@as Machine]]

    if reset_all == true then
        modal_elements.machine_all.state = false
        modal_elements.fuel_all.state = false
    end

    -- Machine
    local machine_tooltip = defaults.generate_tooltip(player, "machines", machine.proto.category)
    local equals_machine = defaults.equals_default(player, "machines", machine, machine.proto.category)
    local equals_all_machines = defaults.equals_all_defaults(player, "machines", machine)
    local all_machines = modal_elements.machine_all.state or equals_all_machines

    modal_elements.machine_title.tooltip = machine_tooltip
    modal_elements.machine.enabled = not equals_machine and not all_machines
    modal_elements.machine.state = equals_machine or all_machines
    modal_elements.machine_all.enabled = not equals_all_machines
    modal_elements.machine_all.state = all_machines

    -- Fuel
    local fuel_required = (machine.proto.burner ~= nil)
    local fuel_tooltip = {"fp.machine_no_fuel_required"}  ---@type LocalisedString
    local equals_fuel, equals_all_fuels = false, false
    if fuel_required then
        local category = machine.proto.burner.combined_category
        fuel_tooltip = defaults.generate_tooltip(player, "fuels", category)
        equals_fuel = defaults.equals_default(player, "fuels", machine.fuel, category)
        equals_all_fuels = defaults.equals_all_defaults(player, "fuels", machine.fuel)
    end
    local all_fuels = modal_elements.fuel_all.state or equals_all_fuels

    modal_elements.fuel_title.tooltip = fuel_tooltip
    modal_elements.fuel.enabled = fuel_required and (not equals_fuel and not all_fuels)
    modal_elements.fuel.state = fuel_required and (equals_fuel or all_fuels)
    modal_elements.fuel_all.enabled = fuel_required and not equals_all_fuels
    modal_elements.fuel_all.state = fuel_required and all_fuels
end

local function add_defaults_panel(parent_frame, player)
    local modal_elements = util.globals.modal_elements(player)

    local flow_default = parent_frame.add{type="flow", direction="vertical"}
    flow_default.style.vertical_spacing = 4
    flow_default.style.right_padding = 12
    modal_elements["defaults_flow"] = flow_default

    local machine_caption = {"fp.info_label", {"", {"fp.pu_machine", 1}, " & ", {"fp.pu_module", 2}}}
    local label_machine = flow_default.add{type="label", caption=machine_caption, style="caption_label"}
    modal_elements["machine_title"] = label_machine

    add_checkbox(modal_elements, {"fp.save_as_default"}, {"fp.save_as_default_machine_tt"}, "machine", nil)
    add_checkbox(modal_elements, {"fp.save_for_all"}, {"fp.save_for_all_machine_tt"}, "machine_all",
        "machine_checkbox_all")

    local fuel_caption = {"fp.info_label", {"fp.pu_fuel", 1}}
    local fuel_label = flow_default.add{type="label", caption=fuel_caption, style="caption_label"}
    fuel_label.style.top_margin = 8
    modal_elements["fuel_title"] = fuel_label

    add_checkbox(modal_elements, {"fp.save_as_default"}, {"fp.save_as_default_fuel_tt"}, "fuel")
    add_checkbox(modal_elements, {"fp.save_for_all"}, {"fp.save_for_all_fuel_tt"}, "fuel_all", "machine_checkbox_all")

    local flow_submit = parent_frame.add{type="flow", direction="horizontal"}
    flow_submit.style.top_margin = 12
    flow_submit.add{type="empty-widget", style="flib_horizontal_pusher"}
    local button_submit = flow_submit.add{type="button", caption={"fp.set_defaults"}, style="fp_button_green",
        tags={mod="fp", on_gui_click="save_machine_defaults"}, mouse_button_filter={"left"}}
    button_submit.style.minimal_width = 0

    refresh_defaults_frame(player)
end

local function save_defaults(player)
    local modal_elements = util.globals.modal_elements(player)
    local machine = util.globals.modal_data(player).object

    local machine_data = {
        prototype = machine.proto.name,
        quality = machine.quality_proto.name,
        modules = machine.module_set:compile_default()
    }
    if modal_elements.machine_all.state then
        defaults.set_all(player, "machines", machine_data)
    elseif modal_elements.machine.state then
        defaults.set(player, "machines", machine_data, machine.proto.category)
    end

    if modal_elements.fuel_all.state then
        defaults.set_all(player, "fuels", {prototype=machine.fuel.proto.name})
    elseif modal_elements.fuel.state then
        local category = machine.proto.burner.combined_category
        defaults.set(player, "fuels", {prototype=machine.fuel.proto.name}, category)
    end

    refresh_defaults_frame(player)
    modal_dialog.toggle_foldout_panel(player)
end


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


local function reset_machine(player)
    local machine = util.globals.modal_data(player).object  --[[@as Machine]]
    machine.parent:change_machine_to_default(player)
    machine:reset(player)

    -- Some manual refreshing which don't have their own method
    local modal_elements = util.globals.modal_elements(player)  --[[@as table]]
    modal_elements["machine_button"].elem_value = machine:elem_value()
    modal_elements["limit_textfield"].text = machine.limit or ""
    modal_elements["force_limit_switch"].switch_state = util.gui.switch.convert_to_state(machine.force_limit)

    refresh_fuel_frame(player)
    module_configurator.refresh_modules_flow(player, false)
    refresh_defaults_frame(player)
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
        on_gui_confirmed="confirm_machine", width=textfield_width}, tooltip={"fp.expression_textfield"},
        text=machine.limit}
    textfield_limit.style.width = textfield_width
    modal_data.modal_elements["limit_textfield"] = textfield_limit

    local label_force = frame_limit.add{type="label", caption={"fp.info_label", {"fp.machine_force_limit"}},
        tooltip={"fp.machine_force_limit_tt"}, style="semibold_label"}
    label_force.style.left_margin = 12

    local state = util.gui.switch.convert_to_state(machine.force_limit)
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
    machine.parent.surface_compatibility = nil  -- reset since the machine changed
    machine:normalize_fuel(player)
    machine.module_set:normalize({compatibility=true, trim=true, effects=true})

    -- Make sure the line's beacon is removed if this machine no longer supports it
    if not machine:uses_effects() then machine.parent:set_beacon(nil) end

    refresh_fuel_frame(player)
    module_configurator.refresh_modules_flow(player, false)
    refresh_defaults_frame(player, true)
end

local function handle_fuel_choice(player, _, event)
    local machine = util.globals.modal_data(player).object
    local elem_value = event.element.elem_value

    if not elem_value then
        event.element.elem_value = machine.fuel.proto.name  -- reset the fuel so it can't be nil
        util.cursor.create_flying_text(player, {"fp.no_removal", {"fp.pu_fuel", 1}})
        return  -- nothing changed
    end

    local combined_category = machine.proto.burner.combined_category
    machine.fuel.proto = prototyper.util.find("fuels", elem_value, combined_category)

    refresh_defaults_frame(player, true)
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


    -- Defaults
    local secondary_frame = modal_data.modal_elements.secondary_frame
    modal_data.defaults_refresher = "machine_defaults_refresher"
    add_defaults_panel(secondary_frame, player)
end

local function close_machine_dialog(player, action)
    local modal_data = util.globals.modal_data(player)  --[[@as table]]
    local machine, line = modal_data.object, modal_data.line

    if action == "submit" then
        machine.module_set:normalize({sort=true})
        machine.limit = util.gui.parse_expression_field(modal_data.modal_elements.limit_textfield)
        local switch_state = modal_data.modal_elements.force_limit_switch.switch_state
        machine.force_limit = util.gui.switch.convert_to_boolean(switch_state)

        solver.update(player)
        util.raise.refresh(player, "factory")

    else  -- action == "cancel"
        line.machine = modal_data.machine_backup
        line.machine.module_set:normalize({effects=true})
        line:set_beacon(modal_data.beacon_backup)
        -- Need to refresh so the buttons have the 'new' backup machine for further actions
        util.raise.refresh(player, "production_detail")
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
            name = "confirm_machine",
            handler = (function(player, _, event)
                local confirmed = util.gui.confirm_expression_field(event.element)
                if confirmed then util.raise.close_dialog(player, "submit") end
            end)
        }
    },
    on_gui_click = {
        {
            name = "save_machine_defaults",
            handler = save_defaults
        }
    },
    on_gui_checked_state_changed = {
        {
            name = "machine_checkbox_all",
            handler = refresh_defaults_frame
        }
    }
}

listeners.dialog = {
    dialog = "machine",
    metadata = (function(modal_data)
        local machine = OBJECT_INDEX[modal_data.machine_id]  --[[@as Machine]]
        local recipe_name = machine.parent.recipe_proto.name
        return {
            caption = {"", {"fp.edit"}, " ", {"fp.pl_machine", 1}},
            subheader_text = {"fp.machine_dialog_description", recipe_name},
            foldout_title = {"fp.defaults"},
            show_submit_button = true,
            reset_handler_name = "reset_machine"
        }
    end),
    open = open_machine_dialog,
    close = close_machine_dialog
}

listeners.global = {
    machine_defaults_refresher = refresh_defaults_frame,
    reset_machine = reset_machine
}

return { listeners }
