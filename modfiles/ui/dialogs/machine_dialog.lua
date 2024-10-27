-- ** LOCAL UTIL **
local function add_defaults_section(modal_elements, identifier, info_caption)
    local label_info = modal_elements.defaults_flow.add{type="label", caption=info_caption, style="semibold_label"}
    label_info.style.margin = {0, 8, 0, 24}
    modal_elements[identifier .. "_title"] = label_info

    local button = modal_elements.defaults_flow.add{type="sprite-button", sprite="fp_default",
        tags={mod="fp", on_gui_click="set_machine_default", action=identifier},
        tooltip={"fp.save_as_default_" .. identifier}, style="tool_button"}
    modal_elements[identifier] = button

    local button_all = modal_elements.defaults_flow.add{type="sprite-button", sprite="fp_default_all",
        tags={mod="fp", on_gui_click="set_machine_default", action=(identifier .. "_all")},
        tooltip={"fp.save_for_all_" .. identifier}, style="tool_button"}
    modal_elements[identifier .. "_all"] = button_all
end

local function refresh_defaults_frame(player)
    local modal_data = util.globals.modal_data(player)  --[[@as table]]
    local modal_elements = modal_data.modal_elements
    local machine = modal_data.object  --[[@as Machine]]

    -- Machine
    local machine_tooltip = defaults.generate_tooltip(player, "machines", machine.proto.category)
    local equals_machine = defaults.equals_default(player, "machines", machine, machine.proto.category)
    local equals_all_machines = defaults.equals_all_defaults(player, "machines", machine)

    modal_elements.machine_title.tooltip = machine_tooltip
    modal_elements.machine.enabled = not equals_machine
    modal_elements.machine_all.enabled = not equals_all_machines

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

    modal_elements.fuel_title.tooltip = fuel_tooltip
    modal_elements.fuel.enabled = fuel_required and not equals_fuel
    modal_elements.fuel_all.enabled = fuel_required and not equals_all_fuels
end

local function add_defaults_frame(parent_frame, player)
    local modal_elements = util.globals.modal_elements(player)

    local frame_defaults = parent_frame.add{type="frame", direction="horizontal", style="fp_frame_bordered_stretch"}
    frame_defaults.style.top_padding = 7
    local flow_defaults = frame_defaults.add{type="flow", direction="horizontal"}
    flow_defaults.style.vertical_align = "center"
    modal_elements["defaults_flow"] = flow_defaults

    flow_defaults.add{type="label", caption={"fp.defaults"}, style="semibold_label"}

    local machine_info = {"fp.info_label", {"", {"fp.pu_machine", 1}, " & ", {"fp.pu_module", 2}}}
    add_defaults_section(modal_elements, "machine", machine_info)

    local fuel_info = {"fp.info_label", {"fp.pu_fuel", 1}}
    add_defaults_section(modal_elements, "fuel", fuel_info)

    refresh_defaults_frame(player)
end

local function set_defaults(player, tags, _)
    local machine = util.globals.modal_data(player).object

    local machine_data = {
        prototype = machine.proto.name,
        quality = machine.quality_proto.name,
        modules = machine.module_set:compile_default()
    }

    if tags.action == "machine_all" then
        defaults.set_all(player, "machines", machine_data)
    elseif tags.action == "machine" then
        defaults.set(player, "machines", machine_data, machine.proto.category)

    elseif tags.action == "fuel_all" then
        defaults.set_all(player, "fuels", {prototype=machine.fuel.proto.name})
    elseif tags.action == "fuel" then
        local category = machine.proto.burner.combined_category
        defaults.set(player, "fuels", {prototype=machine.fuel.proto.name}, category)
    end

    refresh_defaults_frame(player)
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

    local limit_switch = modal_elements.force_limit_switch
    if limit_switch ~= nil then
        modal_elements["limit_textfield"].text = machine.limit or ""
        limit_switch.switch_state = util.gui.switch.convert_to_state(machine.force_limit)
    end

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

local function add_fuel_frame(parent_frame, player, line)
    local modal_elements = util.globals.modal_data(player).modal_elements
    local flow_choices = create_choice_frame(parent_frame, {"fp.pu_fuel", 1})

    local label_fuel = flow_choices.add{type="label", caption={"fp.machine_no_fuel_required"}}
    label_fuel.style.padding = {6, 4}
    modal_elements["fuel_label"] = label_fuel

    local burner = line.machine.proto.burner
    local elem_type = (burner and burner.categories["fluid-fuel"]) and "fluid" or "item"
    local button_fuel = flow_choices.add{type="choose-elem-button", elem_type=elem_type,
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
    refresh_defaults_frame(player)
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

    refresh_defaults_frame(player)
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
    add_fuel_frame(flow_machine, player, modal_data.line)

    -- Limit
    local factory = util.context.get(player, "Factory")
    -- Unavailable with matrix solver or special recipes
    if factory.matrix_free_items == nil and modal_data.line.recipe_proto.energy > 0 then
        add_limit_frame(content_frame, player)
    end

    -- Modules
    module_configurator.add_modules_flow(content_frame, modal_data)
    module_configurator.refresh_modules_flow(player, false)

    -- Defaults
    modal_data.defaults_refresher = "machine_defaults_refresher"
    add_defaults_frame(content_frame, player)
end

local function close_machine_dialog(player, action)
    local modal_data = util.globals.modal_data(player)  --[[@as table]]
    local machine, line = modal_data.object, modal_data.line

    if action == "submit" then
        machine.module_set:normalize({sort=true})

        local limit_switch = modal_data.modal_elements.force_limit_switch
        if limit_switch ~= nil then
            machine.limit = util.gui.parse_expression_field(modal_data.modal_elements.limit_textfield)
            machine.force_limit = util.gui.switch.convert_to_boolean(limit_switch.switch_state)
        end

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
            name = "set_machine_default",
            handler = set_defaults
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
        local recipe_name = machine.parent.recipe_proto.localised_name
        return {
            caption = {"", {"fp.edit"}, " ", {"fp.pl_machine", 1}},
            subheader_text = {"fp.machine_dialog_description", recipe_name},
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
