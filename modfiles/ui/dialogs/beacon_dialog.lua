local Beacon = require("backend.data.Beacon")

-- ** LOCAL UTIL **
local function refresh_defaults_frame(player)
    local modal_data = util.globals.modal_data(player)  --[[@as table]]
    local modal_elements = modal_data.modal_elements
    local beacon = modal_data.object  --[[@as Beacon]]

    local beacon_tooltip = defaults.generate_tooltip(player, "beacons", nil)
    local beacon_default = defaults.get(player, "beacons", nil)
    local equals_beacon = defaults.equals_default(player, "beacons", beacon, nil)
    local equals_amount = (beacon_default.beacon_amount == beacon.amount)

    modal_elements.beacon_title.tooltip = beacon_tooltip
    modal_elements.beacon.enabled = not equals_beacon
    modal_elements.amount.enabled = not equals_amount
end

local function add_defaults_frame(parent_frame, player)
    local modal_elements = util.globals.modal_elements(player)

    local frame_defaults = parent_frame.add{type="frame", direction="horizontal", style="fp_frame_bordered_stretch"}
    frame_defaults.style.top_padding = 7
    local flow_defaults = frame_defaults.add{type="flow", direction="horizontal"}
    flow_defaults.style.vertical_align = "center"
    modal_elements["defaults_flow"] = flow_defaults

    flow_defaults.add{type="label", caption={"fp.defaults"}, style="semibold_label"}

    local info_caption = {"fp.info_label", {"", {"fp.pu_beacon", 1}, " & ", {"fp.pu_module", 2}}}
    local label_info = modal_elements.defaults_flow.add{type="label", caption=info_caption, style="semibold_label"}
    label_info.style.margin = {0, 8, 0, 24}
    modal_elements["beacon_title"] = label_info

    local button_beacon = modal_elements.defaults_flow.add{type="sprite-button", sprite="fp_default",
        tags={mod="fp", on_gui_click="set_beacon_default", action="beacon"},
        tooltip={"fp.save_as_default_beacon"}, style="tool_button"}
    modal_elements["beacon"] = button_beacon

    local button_amount = modal_elements.defaults_flow.add{type="sprite-button", sprite="fp_amount",
        tags={mod="fp", on_gui_click="set_beacon_default", action="amount"},
        tooltip={"fp.save_beacon_amount"}, style="tool_button"}
    modal_elements["amount"] = button_amount

    refresh_defaults_frame(player)
end

local function set_defaults(player, tags, _)
    local beacon = util.globals.modal_data(player).object

    if tags.action == "beacon" then
        local data = {
            prototype = beacon.proto.name,
            quality = beacon.quality_proto.name,
            modules = beacon.module_set:compile_default(),
        }
        defaults.set(player, "beacons", data, nil)

    elseif tags.action == "amount" then
        local data = { beacon_amount = beacon.amount }
        defaults.set(player, "beacons", data, nil)
    end

    refresh_defaults_frame(player)
end


local function add_beacon_frame(parent_flow, modal_data)
    local modal_elements = modal_data.modal_elements
    local beacon = modal_data.object

    local flow_beacon = parent_flow.add{type="frame", style="fp_frame_module", direction="horizontal"}
    flow_beacon.style.width = MAGIC_NUMBERS.module_dialog_element_width

    flow_beacon.add{type="label", caption={"fp.pu_beacon", 1}, style="semibold_label"}
    local beacon_filter = {{filter="type", type="beacon"}, {filter="hidden", invert=true, mode="and"}}
    local button_beacon = flow_beacon.add{type="choose-elem-button", elem_type="entity-with-quality",
        tags={mod="fp", on_gui_elem_changed="select_beacon"}, elem_filters=beacon_filter,
        style="fp_sprite-button_inset"}
    button_beacon.elem_value = beacon:elem_value()
    button_beacon.style.right_margin = 12
    modal_elements["beacon_button"] = button_beacon

    flow_beacon.add{type="label", caption={"fp.info_label", {"fp.amount"}}, tooltip={"fp.beacon_amount_tt"},
        style="semibold_label"}
    local beacon_amount = (beacon.amount ~= 0) and tostring(beacon.amount) or ""
    local amount_width = 40
    local textfield_amount = flow_beacon.add{type="textfield", text=beacon_amount,
        tags={mod="fp", on_gui_text_changed="beacon_amount", on_gui_confirmed="confirm_beacon",
        width=amount_width}, tooltip={"fp.expression_textfield"}}
    textfield_amount.style.width = amount_width
    util.gui.select_all(textfield_amount)
    modal_elements["beacon_amount"] = textfield_amount

    local label_profile = flow_beacon.add{type="label", tooltip={"fp.beacon_profile_tt"}}
    label_profile.style.width = 64
    modal_elements["profile_label"] = label_profile

    flow_beacon.add{type="label", caption={"fp.info_label", {"fp.beacon_total"}}, tooltip={"fp.beacon_total_tt"},
        style="semibold_label"}
    local total_width = 40
    local textfield_total = flow_beacon.add{type="textfield", text=tostring(beacon.total_amount or ""),
        tags={mod="fp", on_gui_text_changed="beacon_total_amount", on_gui_confirmed="confirm_beacon",
        width=total_width}, tooltip={"fp.expression_textfield"}}
    textfield_total.style.width = total_width
    modal_elements["beacon_total"] = textfield_total

    local button_total = flow_beacon.add{type="sprite-button", tags={mod="fp", on_gui_click="use_beacon_selector"},
        tooltip={"fp.beacon_selector_tt"}, sprite="fp_zone_selection", style="button", mouse_button_filter={"left"}}
    button_total.style.padding = 2
    button_total.style.size = 26
    button_total.style.top_margin = 1
end


local function update_profile_label(modal_data)
    local profile_multiplier = modal_data.object:profile_multiplier()
    local label_profile = modal_data.modal_elements.profile_label
    label_profile.caption = (profile_multiplier > 0) and "x " .. profile_multiplier or "x ---"
end

local function update_dialog_submit_button(modal_data)
    local beacon_amount = modal_data.object.amount

    local message = nil
    if not beacon_amount or beacon_amount == 0 then
        message = {"fp.beacon_issue_set_amount"}
    elseif modal_data.module_set.module_count == 0 then
        message = {"fp.beacon_issue_no_modules"}
    end
    modal_dialog.set_submit_button_state(modal_data.modal_elements, (message == nil), message)
end


local function reset_beacon(player)
    local modal_data = util.globals.modal_data(player)  --[[@as table]]
    local beacon = modal_data.object  --[[@as Beacon]]
    beacon:reset(player)

    -- Some manual refreshing which don't have their own method
    modal_data.modal_elements["beacon_button"].elem_value = beacon:elem_value()
    modal_data.modal_elements["beacon_amount"].text = tostring(beacon.amount)

    module_configurator.refresh_modules_flow(player, false)
    refresh_defaults_frame(player)
    update_dialog_submit_button(modal_data)
end


local function handle_beacon_change(player, _, _)
    local modal_data = util.globals.modal_data(player)  --[[@as table]]
    local beacon = modal_data.object
    local beacon_button = modal_data.modal_elements.beacon_button
    local elem_value = beacon_button.elem_value

    if not elem_value then
        beacon_button.elem_value = beacon:elem_value()  -- reset the beacon so it can't be nil
        util.cursor.create_flying_text(player, {"fp.no_removal", {"fp.pu_beacon", 1}})
        return  -- nothing changed
    end

    -- Change the beacon to the new type
    beacon.proto = prototyper.util.find("beacons", elem_value.name, nil)
    beacon.quality_proto = prototyper.util.find("qualities", elem_value.quality, nil)
    beacon.module_set:normalize({compatibility=true, trim=true, effects=true})

    update_profile_label(modal_data)
    module_configurator.refresh_modules_flow(player, false)
    refresh_defaults_frame(player)
end

local function handle_amount_change(player, _, _)
    local modal_data = util.globals.modal_data(player)  --[[@as table]]
    local textfield = modal_data.modal_elements.beacon_amount

    local expression = util.gui.parse_expression_field(textfield)
    local invalid = (textfield.text ~= "" and (expression == nil or expression < 0 or expression % 1 ~= 0))

    textfield.style = (invalid) and "invalid_value_textfield" or "textbox"
    textfield.style.width = textfield.tags.width  --[[@as number]]  -- this is stupid but styles work out that way

    modal_data.object.amount = (invalid) and 0 or (expression or 0)
    modal_data.module_set:normalize({effects=true})

    update_profile_label(modal_data)
    module_configurator.refresh_modules_flow(player, false)
    refresh_defaults_frame(player)
    update_dialog_submit_button(modal_data)
end

local function handle_beacon_selection(player, entities)
    local modal_elements = util.globals.modal_elements(player)
    modal_elements.beacon_total.text = tostring(table_size(entities))
    modal_elements.beacon_total.focus()

    modal_dialog.leave_selection_mode(player)
end


local function open_beacon_dialog(player, modal_data)
    local line = OBJECT_INDEX[modal_data.line_id]  --[[@as Line]]
    modal_data.line = line

    if line.beacon ~= nil then
        modal_data.backup_beacon = line.beacon:clone()
        modal_data.object = line.beacon
    else
        local default_beacon = defaults.get(player, "beacons")
        modal_data.object = Beacon.init(default_beacon.proto --[[@as FPBeaconPrototype]], line)
        modal_data.object.quality_proto = default_beacon.quality
        modal_data.object.amount = default_beacon.beacon_amount or 0
        modal_data.object.module_set:ingest_default(default_beacon.modules)
        line:set_beacon(modal_data.object)
    end
    modal_data.module_set = modal_data.object.module_set

    local content_frame = modal_data.modal_elements.content_frame

    -- Beacon
    add_beacon_frame(content_frame, modal_data)
    update_profile_label(modal_data)
    update_dialog_submit_button(modal_data)

    -- Modules
    modal_data.submit_checker = "beacon_submit_checker"
    module_configurator.add_modules_flow(content_frame, modal_data)
    module_configurator.refresh_modules_flow(player, false)

    -- Defaults
    modal_data.defaults_refresher = "beacon_defaults_refresher"
    add_defaults_frame(content_frame, player)
end

local function close_beacon_dialog(player, action)
    local modal_data = util.globals.modal_data(player)  --[[@as table]]
    local factory = util.context.get(player, "Factory")

    if action == "submit" then
        local beacon = modal_data.object
        local total_amount = util.gui.parse_expression_field(modal_data.modal_elements.beacon_total) or 0
        beacon.total_amount = (total_amount > 0) and total_amount or nil

        solver.update(player, factory)
        util.raise.refresh(player, "factory")

    elseif action == "delete" then
        modal_data.line:set_beacon(nil)
        solver.update(player, factory)
        util.raise.refresh(player, "factory")

    else -- action == "cancel"
        modal_data.line:set_beacon(modal_data.backup_beacon)  -- could be nil
        -- Need to refresh so the buttons have the 'new' backup beacon for further actions
        util.raise.refresh(player, "production_detail")
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
            handler = handle_amount_change
        },
        {
            name = "beacon_total_amount",
            handler = (function(_, _, event)
                util.gui.update_expression_field(event.element)
            end)
        }
    },
    on_gui_confirmed = {
        {
            name = "confirm_beacon",
            handler = (function(player, _, event)
                local confirmed = util.gui.confirm_expression_field(event.element, true)
                if confirmed then util.raise.close_dialog(player, "submit") end
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
        },
        {
            name = "set_beacon_default",
            handler = set_defaults
        }
    }
}

listeners.dialog = {
    dialog = "beacon",
    metadata = (function(modal_data)
        local line = OBJECT_INDEX[modal_data.line_id]  --[[@as Line]]
        local machine_name = line.machine.proto.localised_name
        return {
            caption = {"", {"fp." .. "edit"}, " ", {"fp.pl_beacon", 1}},
            subheader_text = {"fp.beacon_dialog_description", machine_name},
            show_submit_button = true,
            show_delete_button = (line.beacon ~= nil),
            reset_handler_name = "reset_beacon"
        }
    end),
    open = open_beacon_dialog,
    close = close_beacon_dialog
}

listeners.global = {
    beacon_defaults_refresher = refresh_defaults_frame,
    beacon_submit_checker = update_dialog_submit_button,
    reset_beacon = reset_beacon
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
