require("ui.elements.module_configurator")

beacon_dialog = {}

-- ** LOCAL UTIL **
local function add_beacon_frame(parent_flow, modal_data)
    local modal_elements = modal_data.modal_elements
    local beacon = modal_data.dialog_beacon

    local flow_beacon = parent_flow.add{type="frame", style="fp_frame_module", direction="horizontal"}

    flow_beacon.add{type="label", caption={"fp.pu_beacon", 1}}

    local beacon_filter = {{filter="type", type="beacon"}, {filter="flag", flag="hidden", invert=true, mode="and"}}
    local button_beacon = flow_beacon.add{type="choose-elem-button", elem_type="entity", entity=beacon.proto.name,
      tags={mod="fp", on_gui_elem_changed="select_beacon"}, elem_filters=beacon_filter,
      style="fp_sprite-button_inset_tiny"}
    button_beacon.style.right_margin = 12
    modal_elements["beacon_button"] = button_beacon

    flow_beacon.add{type="label", caption={"fp.info_label", {"fp.amount"}}, tooltip={"fp.beacon_amount_tt"}}

    local beacon_amount = (beacon.amount ~= 0) and tostring(beacon.amount) or ""
    local textfield_amount = flow_beacon.add{type="textfield", text=beacon_amount,
      tags={mod="fp", on_gui_text_changed="beacon_amount"}}
    ui_util.setup_numeric_textfield(textfield_amount, true, false)
    ui_util.select_all(textfield_amount)
    textfield_amount.style.width = 40
    textfield_amount.style.right_margin = 12
    modal_elements["beacon_amount"] = textfield_amount

    flow_beacon.add{type="label", caption={"fp.info_label", {"fp.beacon_total"}}, tooltip={"fp.beacon_total_tt"}}

    local textfield_total = flow_beacon.add{type="textfield", name="fp_textfield_beacon_total_amount",
      text=tostring(beacon.total_amount or "")}
    ui_util.setup_numeric_textfield(textfield_total, true, false)
    textfield_total.style.width = 40
    modal_elements["beacon_total"] = textfield_total

    local button_total = flow_beacon.add{type="sprite-button", tags={mod="fp", on_gui_click="use_beacon_selector"},
      tooltip={"fp.beacon_selector_tt"}, sprite="fp_zone_selection", style="button", mouse_button_filter={"left"}}
    button_total.style.padding = 2
    button_total.style.size = 26
    button_total.style.top_margin = 1
end

local function update_dialog_submit_button(modal_data)
    local beacon_amount = tonumber(modal_data.modal_elements.beacon_amount.text)

    local message = nil
    if not beacon_amount or beacon_amount < 1 then
        message = {"fp.beacon_issue_set_amount"}
    elseif modal_data.module_set.module_count == 0 then
        message = {"fp.beacon_issue_no_modules"}
    end
    modal_dialog.set_submit_button_state(modal_data.modal_elements, (message == nil), message)
end

local function handle_beacon_change(player, _, _)
    local modal_data = data_util.get("modal_data", player)
    local beacon_button = modal_data.modal_elements.beacon_button

    local previous_beacon_name = modal_data.dialog_beacon.proto.name
    if not beacon_button.elem_value then
        beacon_button.elem_value = previous_beacon_name  -- reset the beacon so it can't be nil
        return  -- nothing changed
    elseif beacon_button.elem_value == previous_beacon_name then
        return  -- nothing changed
    end

    -- Change the beacon to the new type
    local beacon_id = global.all_beacons.map[beacon_button.elem_value]
    modal_data.dialog_beacon.proto = global.all_beacons.beacons[beacon_id]
    ModuleSet.normalize(modal_data.dialog_beacon.module_set, {compatibility=true, trim=true})

    module_configurator.refresh_modules_flow(player, false)
end

local function handle_beacon_selection(player, entities)
    local modal_elements = data_util.get("modal_elements", player)
    modal_elements.beacon_total.text = tostring(table_size(entities))
    modal_elements.beacon_total.focus()

    modal_dialog.leave_selection_mode(player)
end


-- ** TOP LEVEL **
beacon_dialog.dialog_settings = (function(modal_data)
    local action = (modal_data.object) and "edit" or "add"
    local machine_name = modal_data.line.machine.proto.localised_name
    return {
        caption = {"", {"fp." .. action}, " ", {"fp.pl_beacon", 1}},
        subheader_text = {("fp.beacon_dialog_description_" .. action), machine_name},
        create_content_frame = true,
        show_submit_button = true,
        show_delete_button = (modal_data.object ~= nil)
    }
end)

function beacon_dialog.open(player, modal_data)
    if modal_data.object ~= nil then
       modal_data.dialog_beacon = Beacon.clone(modal_data.object)
    else
        local beacon_proto = prototyper.defaults.get(player, "beacons")
        local beacon_count = data_util.get("preferences", player).mb_defaults.beacon_count
        modal_data.dialog_beacon = Beacon.init(beacon_proto, beacon_count, nil, modal_data.line)
    end

    modal_data.module_set = modal_data.dialog_beacon.module_set
    local content_frame = modal_data.modal_elements.content_frame
    content_frame.style.minimal_width = 400

    -- Beacon
    add_beacon_frame(content_frame, modal_data)
    update_dialog_submit_button(modal_data)

    -- Modules
    modal_data.submit_checker = update_dialog_submit_button
    module_configurator.add_modules_flow(content_frame, modal_data)
    module_configurator.refresh_modules_flow(player, false)
end

function beacon_dialog.close(player, action)
    local modal_data = data_util.get("modal_data", player)
    local subfactory = data_util.get("context", player).subfactory

    if action == "submit" then
        local dialog_beacon = modal_data.dialog_beacon
        dialog_beacon.amount = tonumber(modal_data.modal_elements.beacon_amount.text)
        local total_amount = tonumber(modal_data.modal_elements.beacon_total.text) or 0
        dialog_beacon.total_amount = (total_amount > 0) and total_amount or nil

        Line.set_beacon(modal_data.line, dialog_beacon)

        calculation.update(player, subfactory)
        main_dialog.refresh(player, "subfactory")

    elseif action == "delete" then
        Line.set_beacon(modal_data.line, nil)
        calculation.update(player, subfactory)
        main_dialog.refresh(player, "subfactory")
    end
end


-- ** EVENTS **
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
            handler = (function(player, _, _)
                local modal_data = data_util.get("modal_data", player)
                update_dialog_submit_button(modal_data)
            end)
        }
    },
    on_gui_click = {
        {
            name = "use_beacon_selector",
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
