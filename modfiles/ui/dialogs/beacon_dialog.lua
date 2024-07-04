require("ui.elements.module_configurator")
local Beacon = require("backend.data.Beacon")

-- ** LOCAL UTIL **
local function add_beacon_frame(parent_flow, modal_data)
    local modal_elements = modal_data.modal_elements
    local beacon = modal_data.object

    local flow_beacon = parent_flow.add{type="frame", style="fp_frame_module", direction="horizontal"}

    flow_beacon.add{type="label", caption={"fp.pu_beacon", 1}, style="semibold_label"}

    local beacon_filter = {{filter="type", type="beacon"}, {filter="hidden", invert=true, mode="and"}}
    local button_beacon = flow_beacon.add{type="choose-elem-button", elem_type="entity", entity=beacon.proto.name,
        tags={mod="fp", on_gui_elem_changed="select_beacon"}, elem_filters=beacon_filter,
        style="fp_sprite-button_inset_tiny"}
    button_beacon.style.right_margin = 12
    modal_elements["beacon_button"] = button_beacon

    flow_beacon.add{type="label", caption={"fp.info_label", {"fp.amount"}}, tooltip={"fp.beacon_amount_tt"},
        style="semibold_label"}

    local beacon_amount = (beacon.amount ~= 0) and tostring(beacon.amount) or ""
    local textfield_amount = flow_beacon.add{type="textfield", text=beacon_amount, enabled=(not BEACON_OVERLOAD_ACTIVE),
        tags={mod="fp", on_gui_text_changed="beacon_amount"}}
    util.gui.setup_numeric_textfield(textfield_amount, true, false)
    if not BEACON_OVERLOAD_ACTIVE then util.gui.select_all(textfield_amount) end
    textfield_amount.style.width = 40
    textfield_amount.style.right_margin = 12
    modal_elements["beacon_amount"] = textfield_amount

    flow_beacon.add{type="label", caption={"fp.info_label", {"fp.beacon_total"}}, tooltip={"fp.beacon_total_tt"},
        style="semibold_label"}

    local textfield_total = flow_beacon.add{type="textfield", name="fp_textfield_beacon_total_amount",
        text=tostring(beacon.total_amount or "")}
    util.gui.setup_numeric_textfield(textfield_total, true, false)
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
    if not beacon_amount or beacon_amount == 0 then
        message = {"fp.beacon_issue_set_amount"}
    elseif modal_data.module_set.module_count == 0 then
        message = {"fp.beacon_issue_no_modules"}
    end
    modal_dialog.set_submit_button_state(modal_data.modal_elements, (message == nil), message)
end

local function handle_beacon_change(player, _, _)
    local modal_data = util.globals.modal_data(player)  --[[@as table]]
    local beacon_button = modal_data.modal_elements.beacon_button
    local beacon = modal_data.object

    local previous_beacon_name = beacon.proto.name
    if not beacon_button.elem_value then
        beacon_button.elem_value = previous_beacon_name  -- reset the beacon so it can't be nil
        return  -- nothing changed
    elseif beacon_button.elem_value == previous_beacon_name then
        return  -- nothing changed
    end

    -- Change the beacon to the new type
    beacon.proto = prototyper.util.find_prototype("beacons", beacon_button.elem_value, nil)
    beacon.module_set:normalize({compatibility=true, trim=true, effects=true})

    module_configurator.refresh_modules_flow(player, false)
end

local function handle_beacon_selection(player, entities)
    local modal_elements = util.globals.modal_elements(player)
    modal_elements.beacon_total.text = tostring(table_size(entities))
    modal_elements.beacon_total.focus()

    modal_dialog.leave_selection_mode(player)
end


local function open_beacon_dialog(player, modal_data)
    local line = OBJECT_INDEX[modal_data.line_id]
    modal_data.line = line

    if line.beacon ~= nil then
        modal_data.backup_beacon = line.beacon:clone()
        modal_data.object = line.beacon
    else
        local beacon_proto = prototyper.defaults.get(player, "beacons")
        modal_data.object = Beacon.init(beacon_proto, line)
        modal_data.object.amount = util.globals.preferences(player).mb_defaults.beacon_count or 0
        line:set_beacon(modal_data.object)
    end

    if BEACON_OVERLOAD_ACTIVE then modal_data.object.amount = 1 end
    modal_data.module_set = modal_data.object.module_set

    local content_frame = modal_data.modal_elements.content_frame
    content_frame.style.minimal_width = 460

    -- Beacon
    add_beacon_frame(content_frame, modal_data)
    update_dialog_submit_button(modal_data)

    -- Modules
    modal_data.submit_checker = update_dialog_submit_button
    module_configurator.add_modules_flow(content_frame, modal_data)
    module_configurator.refresh_modules_flow(player, false)
end

local function close_beacon_dialog(player, action)
    local modal_data = util.globals.modal_data(player)  --[[@as table]]
    local factory = util.context.get(player, "Factory")

    if action == "submit" then
        local beacon = modal_data.object
        local total_amount = tonumber(modal_data.modal_elements.beacon_total.text) or 0
        beacon.total_amount = (total_amount > 0) and total_amount or nil

        solver.update(player, factory)
        util.raise.refresh(player, "factory", nil)

    elseif action == "delete" then
        modal_data.line:set_beacon(nil)
        solver.update(player, factory)
        util.raise.refresh(player, "factory", nil)

    else -- action == "cancel"
        modal_data.line:set_beacon(modal_data.backup_beacon)  -- could be nil
    end
end


-- ** EVENTS **
local listeners = {}

listeners.gui = {
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
                local modal_data = util.globals.modal_data(player)  --[[@as table]]
                modal_data.object.amount = tonumber(modal_data.modal_elements.beacon_amount.text) or 0
                modal_data.module_set:normalize({effects=true})
                module_configurator.refresh_effects_flow(modal_data)
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

listeners.dialog = {
    dialog = "beacon",
    metadata = (function(modal_data)
        local line = OBJECT_INDEX[modal_data.line_id]
        local machine_name = line.machine.proto.localised_name
        local edit = (line.beacon ~= nil)
        local action = (edit) and "edit" or "add"
        return {
            caption = {"", {"fp." .. action}, " ", {"fp.pl_beacon", 1}},
            subheader_text = {("fp.beacon_dialog_description_" .. action), machine_name},
            create_content_frame = true,
            show_submit_button = true,
            show_delete_button = (edit == true)
        }
    end),
    open = open_beacon_dialog,
    close = close_beacon_dialog
}

listeners.misc = {
    on_player_cursor_stack_changed = (function(player, _)
        -- If the cursor stack is not valid_for_read, it's empty, thus the selector has been put away
        if util.globals.ui_state(player).selection_mode and not player.cursor_stack.valid_for_read then
            modal_dialog.leave_selection_mode(player)
        end
    end),
    on_player_selected_area = (function(player, event)
        if event.item == "fp_beacon_selector" and util.globals.ui_state(player).selection_mode then
            handle_beacon_selection(player, event.entities)
        end
    end)
}

return { listeners }
