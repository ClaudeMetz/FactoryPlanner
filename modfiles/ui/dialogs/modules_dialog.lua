module_dialog = {}
beacon_dialog = {}
modules_dialog = {}  -- table containing functionality shared between both dialogs

-- ** LOCAL UTIL **
local function add_bordered_frame(element)
    return element.add{type = "frame", style = "fp_frame_module", direction = "horizontal"}
end

local function add_error_no_modules(parent_flow)
    local flow_module = add_bordered_frame(parent_flow)
    flow_module.add{type="label", caption={"fp.pu_module", 1}}
    flow_module.add{type="label", style="fp_label_module_error",
      caption={"fp.error_message", {"fp.module_issue_none_compatible"}}}
end

local function add_module_line(parent_flow, module, empty_slots, module_filter)
    local flow_module = add_bordered_frame(parent_flow)

    flow_module.add{type="label", caption={"fp.pu_module", 1}}

    local controls = {parent = flow_module}
    local module_id = module and module.id

    local module_name = (module) and module.proto.name or nil
    local button_module = flow_module.add{type="choose-elem-button", tags={mod="fp", on_gui_elem_changed="select_module", id=module_id},
      elem_type="item", item=module_name, elem_filters=module_filter, style="fp_sprite-button_inset_tiny"}
    button_module.style.right_margin = 12
    controls.button = button_module

    flow_module.add{type="label", caption={"fp.amount"}}

    local slider_value = (module) and module.amount or empty_slots
    local maximum_value = (module) and (module.amount + empty_slots) or empty_slots
    local minimum_value = maximum_value == 1 and 0 or 1 -- to make sure that the slider can be created
    local slider = flow_module.add{type="slider", tags={mod="fp", on_gui_value_changed="module_amount", id=module_id},
      minimum_value=minimum_value, maximum_value=maximum_value, value=slider_value, value_step=0.1, style="fp_slider_module"}
    -- this is the fix for the slider value step "not bug"
    -- you set it to something other than 1 after setting min/max, then set it to 1
    -- details: https://forums.factorio.com/viewtopic.php?p=516440#p516440
    slider.set_slider_value_step(1)
    controls.slider = slider

    local textfield_slider = flow_module.add{type="textfield", text=tostring(slider_value),
      tags={mod="fp", on_gui_text_changed="module_amount", id=module_id}}
    ui_util.setup_numeric_textfield(textfield_slider, false, false)
    textfield_slider.style.width = 40
    controls.input = textfield_slider

    if maximum_value == 1 then
        slider.enabled = false
        slider.style = "fp_slider_module_none"
        textfield_slider.enabled = false
    end

    return controls
end

local function add_beacon_line(parent_flow, beacon)
    local flow_beacon = add_bordered_frame(parent_flow)

    flow_beacon.add{type="label", caption={"fp.pu_beacon", 1}}

    local controls = {parent = parent_flow}

    local beacon_filter = {{filter="type", type="beacon"}, {filter="flag", flag="hidden", invert=true, mode="and"}}
    local button_beacon = flow_beacon.add{type="choose-elem-button", tags={mod="fp", on_gui_elem_changed="select_beacon"},
      elem_type="entity", entity=beacon.proto.name, elem_filters=beacon_filter, style="fp_sprite-button_inset_tiny"}
    button_beacon.style.right_margin = 12
    controls.button = button_beacon

    flow_beacon.add{type="label", caption={"fp.info_label", {"fp.amount"}}, tooltip={"fp.beacon_amount_tt"}}

    local beacon_amount = (beacon.amount ~= 0) and tostring(beacon.amount) or ""
    local textfield_amount = flow_beacon.add{type="textfield", text=beacon_amount,
      tags={mod="fp", on_gui_text_changed="beacon_amount"}}
    ui_util.setup_numeric_textfield(textfield_amount, true, false)
    ui_util.select_all(textfield_amount)
    textfield_amount.style.width = 40
    textfield_amount.style.right_margin = 12
    controls.input = textfield_amount

    flow_beacon.add{type="label", caption={"fp.info_label", {"fp.beacon_total"}}, tooltip={"fp.beacon_total_tt"}}

    local textfield_total = flow_beacon.add{type="textfield", name="fp_textfield_beacon_total_amount",
      text=tostring(beacon.total_amount or "")}
    ui_util.setup_numeric_textfield(textfield_total, true, false)
    textfield_total.style.width = 40
    controls.input_total = textfield_total

    local button_total = flow_beacon.add{type="sprite-button", tags={mod="fp", on_gui_click="use_beacon_selector"},
      tooltip={"fp.beacon_selector_tt"}, sprite="fp_zone_selection", style="button", mouse_button_filter={"left"}}
    button_total.style.padding = 2
    button_total.style.size = 26
    button_total.style.top_margin = 1

    return controls
end

local function prepare_module_filters(entity)
    local class = _G[entity.class]
    local filters = class.compile_module_filter(entity)
    if filters and not next(filters[1].name) then
        -- filter for nothing, just return nothing
        return nil, nil
    end
    if not filters then
        filters = {}
    end
    -- filters don't care about indices, so let's make this easier
    -- needs to have at least one element, else the filters break
    local other_modules = {["fp-module-that-does-not-exist"] = "fp-module-that-does-not-exist"}
    for _, module in pairs(class.get_all(entity, "Module")) do
        local name = module.proto.name
        other_modules[name] = name
    end
    table.insert(filters, {filter = "name", mode = "and", invert = true, name = other_modules})

    return filters, other_modules
end

local function populate_dialog(content_frame, modal_data, entity)
    modal_data.entity = entity
    modal_data.errors = {}
    local elements, module_controls = modal_data.modal_elements, {}
    elements.module_controls = module_controls

    local class = _G[entity.class]

    if entity.class == "Beacon" then
        elements.beacon_controls = add_beacon_line(content_frame, entity)
        modal_data.errors.zero_beacons = (entity.amount <= 0)
    end

    local empty_slots = class.empty_slot_count(entity)
    local filters, other_modules = prepare_module_filters(entity)
    if not filters then
        add_error_no_modules(content_frame)
        modal_data.errors.no_compatible_modules = true
        return
    end

    local modules = class.get_in_order(entity, "Module")
    modal_data.errors.no_module_selected = not next(modules)
    for _, module in ipairs(modules) do
        local name = module.proto.name
        other_modules[name] = nil -- remove this module from the filter for this button
        module_controls[module.id] = add_module_line(content_frame, module, empty_slots, filters)
        other_modules[name] = name -- now put it back
    end
    if empty_slots > 0 then
        elements.empty_module_controls = add_module_line(content_frame, nil, empty_slots, filters)
    else
        elements.empty_module_controls = nil
    end
end

local function update_dialog_submit_button(modal_data)
    local errors, message = modal_data.errors, nil
    if errors.no_compatible_modules then
        message = {"fp.module_issue_none_compatible"}
    elseif errors.zero_beacons then
        message = {"fp.beacon_issue_set_amount"}
    elseif errors.no_module_selected then
        message = {"fp.module_issue_select_module"}
    end
    modal_dialog.set_submit_button_state(modal_data.modal_elements, (message == nil), message)
end

local function update_module_line(controls, amount, maximum, filters)
    -- (amount <= maximum) is assumed
    local slider, input = controls.slider, controls.input

    local input_enabled = (maximum > 1)
    slider.set_slider_minimum_maximum(input_enabled and 1 or 0, maximum)
    -- this is the fix for the slider value step "not bug"
    -- you set it to something other than 1 after setting min/max, then set it to 1
    -- details: https://forums.factorio.com/viewtopic.php?p=516440#p516440
    slider.set_slider_value_step(0.1)
    slider.set_slider_value_step(1)
    slider.enabled = input_enabled
    slider.style = input_enabled and "fp_slider_module" or "fp_slider_module_none"
    input.enabled = input_enabled

    slider.slider_value = amount
    input.text = tostring(amount)
    controls.button.elem_filters = filters
end

local function update_module_controls(modal_elements, entity)
    -- recalculate all slider and textfield values, and update filters
    local class = _G[entity.class]
    local empty_slots = class.empty_slot_count(entity)
    local filters, other_modules = prepare_module_filters(entity)
    for id, controls in pairs(modal_elements.module_controls) do
        local module = class.get(entity, "Module", id)
        local amount, name = module.amount, module.proto.name
        other_modules[name] = nil
        update_module_line(controls, amount, amount + empty_slots, filters)
        other_modules[name] = name
    end
    -- manage empty line
    local controls = modal_elements.empty_module_controls
    if empty_slots > 0 then
        if controls then
            local amount = controls.slider.slider_value
            if amount > empty_slots then
                amount = empty_slots
            end
            update_module_line(controls, amount, empty_slots, filters)
        else
            modal_elements.empty_module_controls =
                add_module_line(modal_elements.content_frame, nil, empty_slots, filters)
        end
    elseif controls then
        controls.parent.destroy()
        modal_elements.empty_module_controls = nil
    end
end

local function handle_beacon_change(player, tags, metadata)
    local modal_data = data_util.get("modal_data", player)
    local beacon = modal_data.entity
    local controls = modal_data.modal_elements.beacon_controls
    local name = controls.button.elem_value

    -- The beacon can't be set to nil, so reset it to the current one if necessary
    if not name then
        controls.button.elem_value = beacon.proto.name
        return -- 'nothing changed' in this case
    end
    if name == beacon.proto.name then
        return -- 'nothing changed' if it was reselected either
    end

    -- save the total amount so it is not lost, because it's not synced otherwise
    local total_amount = tonumber(controls.input_total.text) or 0
    beacon.total_amount = (total_amount > 0) and total_amount or nil

    -- Change the beacon to the new type
    local beacon_id = global.all_beacons.map[name]
    beacon.proto = global.all_beacons.beacons[beacon_id]
    Beacon.trim_modules(beacon)

    -- Recreate the dialog contents
    local content_frame = modal_data.modal_elements.content_frame
    content_frame.clear()
    populate_dialog(content_frame, modal_data, beacon)

    update_dialog_submit_button(modal_data)
end

local function handle_beacon_selection(player, entities)
    local modal_elements = data_util.get("modal_elements", player)
    modal_elements.beacon_controls.input_total.text = tostring(table_size(entities))
    modal_elements.beacon_controls.input_total.focus()

    modal_dialog.leave_selection_mode(player)
end

local function handle_module_selection(player, tags, metadata)
    local modal_data = data_util.get("modal_data", player)
    local entity, elements = modal_data.entity, modal_data.modal_elements
    local id, class, new_name = tags.id, _G[entity.class], metadata.elem_value
    if id then -- existing module changed
        local module = class.get(entity, "Module", id)
        if new_name then
            -- changed to another module
            module.proto = MODULE_NAME_MAP[new_name]
        else
            -- removed
            elements.module_controls[id].parent.destroy()
            elements.module_controls[id] = nil
            class.remove(entity, module)
            modal_data.errors.no_module_selected = not next(elements.module_controls)
        end
    elseif new_name then -- it can be nil when an empty button is reset
        local amount = elements.empty_module_controls.slider.slider_value
        local module = Module.init_by_proto(MODULE_NAME_MAP[new_name], amount)
        class.add(entity, module)
        -- just destroy the old elements instead of attempting to reuse them
        -- as they would contain wrong information, like tags
        elements.empty_module_controls.parent.destroy()
        elements.empty_module_controls = nil
        -- filters don't matter because they will be reset correctly in update_module_controls anyway
        elements.module_controls[module.id] = add_module_line(elements.content_frame, module, 0, nil)
        modal_data.errors.no_module_selected = false
    end

    update_module_controls(elements, entity)
    update_dialog_submit_button(modal_data)
end

local function handle_module_slider_change(player, tags, metadata)
    local modal_data = data_util.get("modal_data", player)
    local entity, elements = modal_data.entity, modal_data.modal_elements
    local id, class = tags.id, _G[entity.class]
    if id then
        -- existing module changed
        Module.change_amount(class.get(entity, "Module", id), metadata.slider_value)
        update_module_controls(elements, entity)
    else
        -- empty module changed, which doesn't impact anything else
        elements.empty_module_controls.input.text = tostring(metadata.slider_value)
    end

    update_dialog_submit_button(modal_data)
end

local function handle_module_textfield_change(player, tags, metadata)
    local modal_data = data_util.get("modal_data", player)
    local id, elements = tags.id, modal_data.modal_elements
    local controls = id and elements.module_controls[id] or elements.empty_module_controls
    local slider = controls.slider
    local set_text, amount, maximum = true, tonumber(metadata.text), slider.get_slider_maximum()
    if not amount then
        amount = slider.slider_value
    elseif amount < 1 then
        amount = 1
    elseif amount > maximum then
        amount = maximum
    else
        set_text = false
    end
    if set_text then
        controls.input.text = tostring(amount)
    end
    -- amount still could have changed even if the value was wrong
    -- but only update if it has actually changed
    if amount ~= slider.slider_value then
        if id then
            local entity = modal_data.entity
            local class = _G[entity.class]
            Module.change_amount(class.get(entity, "Module", id), amount)
            update_module_controls(elements, entity)
        else
            -- empty module changed, which doesn't impact anything else
            slider.slider_value = amount
        end
    end

    update_dialog_submit_button(modal_data)
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

function module_dialog.open(player, modal_data)
    local machine = Machine.clone(modal_data.machine)
    populate_dialog(modal_data.modal_elements.content_frame, modal_data, machine)
    update_dialog_submit_button(modal_data)
end

function module_dialog.close(player, action)
    local modal_data = data_util.get("modal_data", player)

    if action == "submit" then
        local real = modal_data.machine
        local copy = modal_data.entity
        -- Line.set_machine - no such thing
        -- so re-add them all into the actual machine instead
        Machine.clear(real, "Module")
        for _, module in pairs(Machine.get_all(copy, "Module")) do
            Machine.add(real, module)
        end
        Machine.clear(copy, "Module") -- so they aren't referred to in both, just in case
        Machine.normalize_modules(real, true, false)
    elseif action == "delete" then
        Machine.clear(modal_data.machine, "Module")
    end

    if action ~= "cancel" then
        local subfactory = data_util.get("context", player).subfactory
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
    if beacon then
        beacon = Beacon.clone(beacon)
    else
        -- Create blank beacon as a stand-in
        local beacon_proto = prototyper.defaults.get(player, "beacons")
        local beacon_count = data_util.get("preferences", player).mb_defaults.beacon_count
        beacon = Beacon.init(beacon_proto, beacon_count, nil, line)
    end
    populate_dialog(modal_data.modal_elements.content_frame, modal_data, beacon)
    update_dialog_submit_button(modal_data)
end

function beacon_dialog.close(player, action)
    local modal_data = data_util.get("modal_data", player)

    if action == "submit" then
        local beacon = modal_data.entity
        -- total amount is not tracked as it changes because it doesn't impact anything
        -- (also because of the beacon selector)
        -- so save it now
        local amount = tonumber(modal_data.modal_elements.beacon_controls.input_total.text) or 0
        beacon.total_amount = (amount > 0) and amount or nil
        Line.set_beacon(modal_data.line, beacon)
    elseif action == "delete" then
        Line.set_beacon(modal_data.line, nil)
    end

    if action ~= "cancel" then
        local subfactory = data_util.get("context", player).subfactory
        calculation.update(player, subfactory)
        main_dialog.refresh(player, "subfactory")
    end
end

beacon_dialog.gui_events = {
    on_gui_elem_changed = {
        {
            name = "select_beacon",
            handler = handle_beacon_change
        }
    },
    on_gui_text_changed = {
        {
            name = "beacon_amount",
            handler = (function(player, tags, metadata)
                local modal_data = data_util.get("modal_data", player)
                local amount = tonumber(metadata.text) or 0
                modal_data.entity.amount = amount
                modal_data.errors.zero_beacons = (amount <= 0)
                update_dialog_submit_button(modal_data)
            end)
        }
    },
    on_gui_click = {
        {
            name = "use_beacon_selector",
            timeout = 20,
            handler = (function(player, tags, metadata)
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
            name = "select_module",
            handler = handle_module_selection
        }
    },
    on_gui_value_changed = {
        {
            name = "module_amount",
            handler = handle_module_slider_change
        }
    },
    on_gui_text_changed = {
        {
            name = "module_amount",
            handler = handle_module_textfield_change
        }
    }
}
