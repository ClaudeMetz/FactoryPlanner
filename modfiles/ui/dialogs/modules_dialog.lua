module_dialog = {}
beacon_dialog = {}
modules_dialog = {}  -- table containing functionality shared between both dialogs

local function compile_module_filter(parent)
    local parent_class_object = _G[parent.class]
    local compatible_modules, existing_modules = {}, parent_class_object.existing_module_names(parent)

    for module_name, module_proto in pairs(module_name_map) do
        if parent_class_object.check_module_compatibility(parent, module_proto)
          and not existing_modules[module_name] then
            table.insert(compatible_modules, module_name)
        end
    end

    return {{filter="name", name=compatible_modules}}  -- hidden modules are already filtered out
end

local function add_module_line(parent_flow, ui_elements, module, empty_slots, parent)
    local flow_module = parent_flow.add{type="flow", direction="horizontal"}
    flow_module.style.vertical_align = "center"
    flow_module.style.horizontal_spacing = 8

    flow_module.add{type="label", caption={"fp.pu_module", 1}}

    local module_name = (module) and module.proto.name or nil
    local module_filter = compile_module_filter(parent)
    local button_module = flow_module.add{type="choose-elem-button", name="fp_choose-elem-button_module_choice",
      elem_type="item", item=module_name, elem_filters=module_filter, style="fp_sprite-button_inset_tiny",
      mouse_button_filter={"left"}}
    button_module.style.right_margin = 18
    ui_elements["module_choice_button"] = button_module

    local slider_value = (module) and module.amount or empty_slots
    local maximum_value = (module) and (module.amount + empty_slots) or empty_slots

    -- Sliders with max_value-min_value == 1 don't work correctly. This is the workaround:
    --if maximum_value == 2 then maximum_value = 2.0000001 end
    -- I'm not sure if I want sliders to start at 1 though, starting at 0 might be fine

    local slider = flow_module.add{type="slider", name="fp_slider_module_amount", minimum_value=0,
      maximum_value=maximum_value, value=slider_value, value_step=1, style="notched_slider"}
    slider.style.width = 130
    ui_elements["module_slider"] = slider

    local textfield_slider = flow_module.add{type="textfield", name="fp_textfield_module_amount", text=slider_value}
    ui_util.setup_numeric_textfield(textfield_slider, false, false)
    textfield_slider.style.width = 40
    textfield_slider.style.left_margin = 4
    ui_elements["module_textfield"] = textfield_slider

    if maximum_value == 1 then
        slider.enabled = false
        slider.style = "slider"
        textfield_slider.enabled = false
    end
end


local function add_beacon_line(parent_flow, ui_elements, beacon)
    local flow_beacon = parent_flow.add{type="flow", direction="horizontal"}
    flow_beacon.style.vertical_align = "center"
    flow_beacon.style.horizontal_spacing = 8

    flow_beacon.add{type="label", caption={"fp.pu_beacon", 1}}

    local beacon_filter = {{filter="type", type="beacon"}, {filter="flag", flag="hidden", invert=true, mode="and"}}
    local button_beacon = flow_beacon.add{type="choose-elem-button", name="fp_choose-elem-button_beacon_choice",
      elem_type="entity", entity=beacon.proto.name, elem_filters=beacon_filter, style="fp_sprite-button_inset_tiny",
      mouse_button_filter={"left"}}
    button_beacon.style.right_margin = 12
    ui_elements["beacon_choice_button"] = button_beacon

    flow_beacon.add{type="label", caption={"fp.info_label", {"fp.beacon_amount"}}, tooltip={"fp.beacon_amount_tt"}}

    local textfield_amount = flow_beacon.add{type="textfield", name="fp_textfield_beacon_amount", text=beacon.amount}
    ui_util.setup_numeric_textfield(textfield_amount, true, false)
    ui_util.select_all(textfield_amount)
    textfield_amount.style.width = 40
    ui_elements["beacon_textfield"] = textfield_amount
end


local function update_dialog_submit_button(ui_elements)
    local beacon_choice, beacon_amount = ui_elements.beacon_choice_button, ui_elements.beacon_textfield
    local module_choice, module_amount = ui_elements.module_choice_button, ui_elements.module_textfield

    local message = nil
    if beacon_choice and beacon_choice.elem_value == nil then
        message = {"fp.beacon_issue_select_beacon"}
    elseif beacon_amount and (tonumber(beacon_amount.text) or 0) == 0 then
        message = {"fp.beacon_issue_set_amount"}
    elseif module_choice.elem_value == nil then
        message = {"fp.module_issue_select_module"}
    elseif tonumber(module_amount.text) == 0 then
        message = {"fp.module_issue_select_amount"}
    end

    modal_dialog.set_submit_button_state(ui_elements, (message == nil), message)
end

local function handle_module_textfield_change(player, element)
    local ui_elements = data_util.get("ui_elements", player)
    local module_slider = ui_elements.module_slider

    local slider_maximum = module_slider.get_slider_maximum()
    local new_number = math.min((tonumber(element.text) or 0), slider_maximum)

    element.text = new_number
    module_slider.slider_value = new_number

    update_dialog_submit_button(ui_elements)
end


local function generate_module_object(ui_elements)
    local module_amount = tonumber(ui_elements.module_textfield.text)
    local module_choice = ui_elements.module_choice_button.elem_value
    local module_proto = module_name_map[module_choice]

    return Module.init_by_proto(module_proto, module_amount)
end


-- ** MODULE **
module_dialog.dialog_settings = (function(modal_data) return {
    caption = {"fp.two_word_title", ((modal_data.object) and {"fp.edit"} or {"fp.add"}), {"fp.pl_module", 1}},
    create_content_frame = true
} end)

function module_dialog.open(_, modal_data)
    local module, machine = modal_data.object, modal_data.machine

    local ui_elements = modal_data.ui_elements
    local empty_slots = Machine.empty_slot_count(machine)
    add_module_line(ui_elements.content_frame, ui_elements, module, empty_slots, machine)

    update_dialog_submit_button(ui_elements)
end

function module_dialog.close(player, action)
    local modal_data = data_util.get("modal_data", player)
    local subfactory = data_util.get("context", player).subfactory
    local current_module = modal_data.object

    if action == "submit" then
        local new_module = generate_module_object(modal_data.ui_elements)

        if current_module ~= nil then
            Machine.replace(modal_data.machine, current_module, new_module)
        else
            Machine.add(modal_data.machine, new_module)
        end

        calculation.update(player, subfactory, true)

    elseif action == "delete" then
        Machine.remove(modal_data.machine, current_module)
        calculation.update(player, subfactory, true)
    end
end


-- ** BEACON **
beacon_dialog.dialog_settings = (function(modal_data) return {
    caption = {"fp.two_word_title", ((modal_data.object) and {"fp.edit"} or {"fp.add"}), {"fp.pl_beacon", 1}},
    create_content_frame = true
} end)

beacon_dialog.events = {
    on_gui_elem_changed = {
        {
            name = "fp_choose-elem-button_beacon_choice",
            handler = (function(player, _)
                local ui_elements = data_util.get("ui_elements", player)
                update_dialog_submit_button(ui_elements)
            end)
        }
    },
    on_gui_text_changed = {
        {
            name = "fp_textfield_beacon_amount",
            handler = (function(player, _)
                local ui_elements = data_util.get("ui_elements", player)
                update_dialog_submit_button(ui_elements)
            end)
        }
    }
}

function beacon_dialog.open(player, modal_data)
    local beacon, line = modal_data.object, modal_data.line
    local ui_elements = modal_data.ui_elements

    if beacon == nil then
        -- Create blank beacon as a stand-in
        local beacon_proto = prototyper.defaults.get(player, "beacons")
        local mb_defaults = data_util.get("preferences", player).mb_defaults
        beacon = Beacon.blank_init(beacon_proto, mb_defaults.beacon_count, line)
        modal_data.object = beacon
    end

    local function add_bordered_frame()
        local frame = ui_elements.content_frame.add{type="frame", style="fp_frame_bordered_stretch"}
        frame.style.padding = 8
        return frame
    end

    local beacon_frame = add_bordered_frame()
    add_beacon_line(beacon_frame, ui_elements, beacon)

    local module_frame = add_bordered_frame()
    local module_amount = (beacon.module) and beacon.module.amount or 0
    local empty_slots = beacon.proto.module_limit - module_amount
    add_module_line(module_frame, ui_elements, beacon.module, empty_slots, beacon)

    update_dialog_submit_button(ui_elements)
end

function beacon_dialog.close(player, action)
    local modal_data = data_util.get("modal_data", player)
    local subfactory = data_util.get("context", player).subfactory

    if action == "submit" then
        local ui_elements = modal_data.ui_elements
        local beacon = modal_data.object

        local beacon_choice = ui_elements.beacon_choice_button.elem_value
        local beacon_id = global.all_beacons.map[beacon_choice]
        beacon.proto = global.all_beacons.beacons[beacon_id]
        beacon.amount = tonumber(ui_elements.beacon_textfield.text)

        local module = generate_module_object(ui_elements)
        Beacon.set_module(beacon, module)

        Line.set_beacon(modal_data.line, beacon)
        calculation.update(player, subfactory, true)

    elseif action == "delete" then
        Line.set_beacon(modal_data.line, nil)
        calculation.update(player, subfactory, true)
    end
end


-- ** SHARED **
modules_dialog.events = {
    on_gui_elem_changed = {
        {
            name = "fp_choose-elem-button_module_choice",
            handler = (function(player, _)
                local ui_elements = data_util.get("ui_elements", player)
                update_dialog_submit_button(ui_elements)
            end)
        }
    },
    on_gui_value_changed = {
        {
            name = "fp_slider_module_amount",
            handler = (function(player, element)
                local ui_elements = data_util.get("ui_elements", player)
                ui_elements.module_textfield.text = element.slider_value
                update_dialog_submit_button(ui_elements)
            end)
        }
    },
    on_gui_text_changed = {
        {
            name = "fp_textfield_module_amount",
            handler = (function(player, element)
                handle_module_textfield_change(player, element)
            end)
        }
    }
}