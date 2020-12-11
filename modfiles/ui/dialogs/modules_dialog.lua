module_dialog = {}
beacon_dialog = {}
modules_dialog = {}  -- table containing functionality shared between both dialogs

-- ** LOCAL UTIL **
local function generate_module_object(modal_elements)
    local choice_button = modal_elements.module_choice_button
    if choice_button and choice_button.valid and choice_button.elem_value then
        local module_amount = tonumber(modal_elements.module_textfield.text)
        local module_proto = MODULE_NAME_MAP[choice_button.elem_value]
        return Module.init_by_proto(module_proto, module_amount)
    else
        return nil
    end
end


local function add_module_line(parent_flow, modal_elements, module, empty_slots, module_filter)
    local flow_module = parent_flow.add{type="flow", direction="horizontal"}
    flow_module.style.vertical_align = "center"
    flow_module.style.horizontal_spacing = 8

    flow_module.add{type="label", caption={"fp.pu_module", 1}}

    if module_filter and #module_filter[1].name == 0 then
        modal_elements.no_modules_label = flow_module.add{type="label", caption={"fp.error_message",
          {"fp.module_issue_none_compatible"}}}
        modal_elements.no_modules_label.style.font = "heading-2"
        modal_elements.no_modules_label.style.padding = 2
        return
    else
        modal_elements.no_modules_label = nil
    end

    local module_name = (module) and module.proto.name or nil
    local button_module = flow_module.add{type="choose-elem-button", name="fp_choose-elem-button_module_choice",
      elem_type="item", item=module_name, elem_filters=module_filter, style="fp_sprite-button_inset_tiny",
      mouse_button_filter={"left"}}
    button_module.style.right_margin = 12
    modal_elements["module_choice_button"] = button_module

    flow_module.add{type="label", caption={"fp.amount"}}

    local slider_value = (module) and module.amount or empty_slots
    local maximum_value = (module) and (module.amount + empty_slots) or empty_slots

    -- Sliders with max_value-min_value == 1 don't work correctly. This is the workaround:
    --if maximum_value == 2 then maximum_value = 2.0000001 end
    -- I'm not sure if I want sliders to start at 1 though, starting at 0 might be fine

    local slider = flow_module.add{type="slider", name="fp_slider_module_amount", minimum_value=0,
      maximum_value=maximum_value, value=slider_value, value_step=1, style="notched_slider"}
    slider.style.width = 130
    slider.style.margin = {0, 6}
    modal_elements["module_slider"] = slider

    local textfield_slider = flow_module.add{type="textfield", name="fp_textfield_module_amount",
      text=tostring(slider_value)}
    ui_util.setup_numeric_textfield(textfield_slider, false, false)
    textfield_slider.style.width = 40
    modal_elements["module_textfield"] = textfield_slider

    if maximum_value == 1 then
        slider.enabled = false
        slider.style = "slider"
        textfield_slider.enabled = false
    end
end


local function add_beacon_line(parent_flow, modal_elements, beacon)
    local flow_beacon = parent_flow.add{type="flow", direction="horizontal"}
    flow_beacon.style.vertical_align = "center"
    flow_beacon.style.horizontal_spacing = 8

    flow_beacon.add{type="label", caption={"fp.pu_beacon", 1}}

    local beacon_filter = {{filter="type", type="beacon"}, {filter="flag", flag="hidden", invert=true, mode="and"}}
    local button_beacon = flow_beacon.add{type="choose-elem-button", name="fp_choose-elem-button_beacon_choice",
      elem_type="entity", entity=beacon.proto.name, elem_filters=beacon_filter, style="fp_sprite-button_inset_tiny",
      mouse_button_filter={"left"}}
    button_beacon.style.right_margin = 12
    modal_elements["beacon_choice_button"] = button_beacon

    flow_beacon.add{type="label", caption={"fp.info_label", {"fp.amount"}}, tooltip={"fp.beacon_amount_tt"}}

    local beacon_amount = (beacon.amount ~= 0) and tostring(beacon.amount) or ""
    local textfield_amount = flow_beacon.add{type="textfield", name="fp_textfield_beacon_amount", text=beacon_amount}
    ui_util.setup_numeric_textfield(textfield_amount, true, false)
    ui_util.select_all(textfield_amount)
    textfield_amount.style.width = 40
    textfield_amount.style.right_margin = 12
    modal_elements["beacon_textfield"] = textfield_amount

    flow_beacon.add{type="label", caption={"fp.info_label", {"fp.beacon_total"}}, tooltip={"fp.beacon_total_tt"}}

    local textfield_total = flow_beacon.add{type="textfield", name="fp_textfield_beacon_total_amount",
      text=tostring(beacon.total_amount or "")}
    ui_util.setup_numeric_textfield(textfield_total, true, false)
    textfield_total.style.width = 40
    modal_elements["beacon_total_textfield"] = textfield_total

    local button_total = flow_beacon.add{type="sprite-button", name="fp_sprite-button_beacon_total_amount",
      tooltip={"fp.beacon_selector_tt"}, sprite="fp_zone_selection", style="button", mouse_button_filter={"left"}}
    button_total.style.padding = 2
    button_total.style.size = 26
    button_total.style.top_margin = 1
end


local function update_dialog_submit_button(modal_elements)
    local module_none_compatible = modal_elements.no_modules_label
    local beacon_choice, beacon_amount = modal_elements.beacon_choice_button, modal_elements.beacon_textfield
    local module_choice, module_amount = modal_elements.module_choice_button, modal_elements.module_textfield

    local message = nil
    if module_none_compatible ~= nil then
        message = {"fp.module_issue_none_compatible"}
    elseif beacon_choice and beacon_choice.elem_value == nil then
        message = {"fp.beacon_issue_select_beacon"}
    elseif beacon_amount and (tonumber(beacon_amount.text) or 0) == 0 then
        message = {"fp.beacon_issue_set_amount"}
    elseif module_choice.elem_value == nil then
        message = {"fp.module_issue_select_module"}
    elseif tonumber(module_amount.text) == 0 then
        message = {"fp.module_issue_select_amount"}
    end

    modal_dialog.set_submit_button_state(modal_elements, (message == nil), message)
end

local function handle_module_textfield_change(player, element)
    local modal_elements = data_util.get("modal_elements", player)
    local module_slider = modal_elements.module_slider

    local slider_maximum = module_slider.get_slider_maximum()
    local new_number = math.min((tonumber(element.text) or 0), slider_maximum)

    element.text = tostring(new_number)
    module_slider.slider_value = new_number

    update_dialog_submit_button(modal_elements)
end

local function handle_beacon_change(player, element)
    local modal_data = data_util.get("modal_data", player)

    -- The beacon can't be set to nil, se re-set the current one if necessary
    if element.elem_value == nil then
        element.elem_value = modal_data.blank_beacon.proto.name
        return  -- nothing changed in this case
    end

    -- Update the blank beacon with the new beacon proto
    local blank_beacon = modal_data.blank_beacon
    local beacon_id = global.all_beacons.map[element.elem_value]
    blank_beacon.proto = global.all_beacons.beacons[beacon_id]

    -- Recreate the module flow, retaining as much info as possible
    local modal_elements = modal_data.modal_elements

    local module = generate_module_object(modal_elements)
    if module and not Beacon.check_module_compatibility(blank_beacon, module.proto) then module = nil end
    if module then module.amount = math.min(module.amount, blank_beacon.proto.module_limit) end

    local module_amount = (module) and module.amount or 0
    local empty_slots = blank_beacon.proto.module_limit - module_amount

    local module_frame = modal_elements.module_frame
    module_frame.clear()

    local module_filter = Beacon.compile_module_filter(blank_beacon)
    add_module_line(module_frame, modal_elements, module, empty_slots, module_filter)

    update_dialog_submit_button(modal_elements)
end

local function handle_beacon_selection(player, entities)
    local modal_elements = data_util.get("modal_elements", player)
    modal_elements.beacon_total_textfield.text = tostring(table_size(entities))
    modal_elements.beacon_total_textfield.focus()

    modal_dialog.leave_selection_mode(player)
end


-- ** MODULE **
module_dialog.dialog_settings = (function(modal_data)
    local action = (modal_data.object) and "edit" or "add"
    local machine_name = modal_data.machine.proto.localised_name
    return {
        caption = {"fp.two_word_title", {"fp." .. action}, {"fp.pl_module", 1}},
        subheader_text = {"fp.modules_instruction_" .. action, {"fp.pl_module", 1}, machine_name},
        create_content_frame = true,
        force_auto_center = true,
        show_submit_button = true,
        show_delete_button = (modal_data.object ~= nil)
    }
end)

function module_dialog.open(_, modal_data)
    local module, machine = modal_data.object, modal_data.machine

    local modal_elements = modal_data.modal_elements
    local empty_slots = Machine.empty_slot_count(machine)
    local module_filter = Machine.compile_module_filter(machine)
    add_module_line(modal_elements.content_frame, modal_elements, module, empty_slots, module_filter)

    update_dialog_submit_button(modal_elements)
end

function module_dialog.close(player, action)
    local modal_data = data_util.get("modal_data", player)
    local subfactory = data_util.get("context", player).subfactory
    local current_module = modal_data.object

    if action == "submit" then
        local new_module = generate_module_object(modal_data.modal_elements)

        if current_module ~= nil then
            Machine.replace(modal_data.machine, current_module, new_module)
        else
            Machine.add(modal_data.machine, new_module)
        end

    elseif action == "delete" then
        Machine.remove(modal_data.machine, current_module)
    end

    if action ~= "cancel" then
        calculation.update(player, subfactory)
        main_dialog.refresh(player, "subfactory")
    end
end


-- ** BEACON **
beacon_dialog.dialog_settings = (function(modal_data)
    local action = (modal_data.object) and "edit" or "add"
    local machine_name = modal_data.line.machine.proto.localised_name
    return {
        caption = {"fp.two_word_title", {"fp." .. action}, {"fp.pl_beacon", 1}},
        subheader_text = {("fp.modules_instruction_" .. action), {"fp.pl_beacon", 1}, machine_name},
        create_content_frame = true,
        force_auto_center = true,
        show_submit_button = true,
        show_delete_button = (modal_data.object ~= nil)
    }
end)

function beacon_dialog.open(player, modal_data)
    local beacon, line = modal_data.object, modal_data.line
    local modal_elements = modal_data.modal_elements

    -- Create blank beacon as a stand-in
    local beacon_proto = (beacon) and beacon.proto or prototyper.defaults.get(player, "beacons")
    local beacon_count = (beacon) and beacon.amount or data_util.get("preferences", player).mb_defaults.beacon_count
    local total_amount = (beacon) and beacon.total_amount or nil
    local blank_beacon = Beacon.init(beacon_proto, beacon_count, total_amount, line)
    modal_data.blank_beacon = blank_beacon
    local module = (beacon) and beacon.module or nil

    local function add_bordered_frame()
        local frame = modal_elements.content_frame.add{type="frame", style="fp_frame_bordered_stretch"}
        frame.style.padding = 8
        return frame
    end

    local beacon_frame = add_bordered_frame()
    add_beacon_line(beacon_frame, modal_elements, blank_beacon)

    local module_frame = add_bordered_frame()
    modal_elements.module_frame = module_frame

    local module_amount = (module) and module.amount or 0
    local empty_slots = blank_beacon.proto.module_limit - module_amount
    local module_filter = Beacon.compile_module_filter(blank_beacon)
    add_module_line(module_frame, modal_elements, module, empty_slots, module_filter)

    update_dialog_submit_button(modal_elements)
end

function beacon_dialog.close(player, action)
    local modal_data = data_util.get("modal_data", player)
    local subfactory = data_util.get("context", player).subfactory

    if action == "submit" then
        local modal_elements = modal_data.modal_elements
        local beacon = modal_data.blank_beacon
        -- The prototype is already updated on elem_changed

        beacon.amount = tonumber(modal_elements.beacon_textfield.text)
        local total_amount = tonumber(modal_elements.beacon_total_textfield.text)
        beacon.total_amount = (total_amount and total_amount > 0) and total_amount or nil

        local module = generate_module_object(modal_elements)
        Beacon.set_module(beacon, module)

        Line.set_beacon(modal_data.line, beacon)

    elseif action == "delete" then
        Line.set_beacon(modal_data.line, nil)
    end

    if action ~= "cancel" then
        calculation.update(player, subfactory)
        main_dialog.refresh(player, "subfactory")
    end
end

beacon_dialog.gui_events = {
    on_gui_elem_changed = {
        {
            name = "fp_choose-elem-button_beacon_choice",
            handler = handle_beacon_change
        }
    },
    on_gui_text_changed = {
        {
            name = "fp_textfield_beacon_amount",
            handler = (function(player, _)
                local modal_elements = data_util.get("modal_elements", player)
                update_dialog_submit_button(modal_elements)
            end)
        }
    },
    on_gui_click = {
        {
            name = "fp_sprite-button_beacon_total_amount",
            timeout = 20,
            handler = (function(player, _, _)
                modal_dialog.enter_selection_mode(player, "fp_beacon_selector")
            end)
        }
    }
}

beacon_dialog.misc_events = {
    on_player_cursor_stack_changed = (function(player, _)
        -- If the cursor stack is not valid_for_read, it's empty, thus the selector has been put away
        if data_util.get("flags", player).selection_mode and not player.cursor_stack.valid_for_read then
            modal_dialog.leave_selection_mode(player)
        end
    end),
    on_player_selected_area = (function(player, event)
        if event.item == "fp_beacon_selector" and data_util.get("flags", player).selection_mode then
            handle_beacon_selection(player, event.entities)
        end
    end)
}


-- ** SHARED **
modules_dialog.gui_events = {
    on_gui_elem_changed = {
        {
            name = "fp_choose-elem-button_module_choice",
            handler = (function(player, _)
                local modal_elements = data_util.get("modal_elements", player)
                update_dialog_submit_button(modal_elements)
            end)
        }
    },
    on_gui_value_changed = {
        {
            name = "fp_slider_module_amount",
            handler = (function(player, element)
                local modal_elements = data_util.get("modal_elements", player)
                modal_elements.module_textfield.text = tostring(element.slider_value)
                update_dialog_submit_button(modal_elements)
            end)
        }
    },
    on_gui_text_changed = {
        {
            name = "fp_textfield_module_amount",
            handler = handle_module_textfield_change
        }
    }
}
