require("ui.elements.module_configurator")
local Beacon = require("backend.data.Beacon")

-- ** LOCAL UTIL **
local function refresh_defaults_frame(player)
    local modal_data = util.globals.modal_data(player)  --[[@as table]]
    local modal_elements = modal_data.modal_elements
    local beacon = modal_data.object  --[[@as Beacon]]

    local beacon_tooltip = prototyper.defaults.generate_tooltip(player, "beacons", nil)
    local beacon_default = prototyper.defaults.get(player, "beacons", nil)
    local equals_beacon = prototyper.defaults.equals_default(player, "beacons", beacon, nil)
    local equals_amount = (beacon_default.beacon_amount == beacon.amount)

    modal_elements.beacon_title.tooltip = beacon_tooltip
    modal_elements.beacon_default.enabled = not equals_beacon
    modal_elements.beacon_default.state = equals_beacon
    modal_elements.beacon_default_amount.enabled = not equals_amount
    modal_elements.beacon_default_amount.state = equals_amount
end

local function add_defaults_panel(parent_frame, player)
    local modal_elements = util.globals.modal_elements(player)

    local flow_default = parent_frame.add{type="flow", direction="vertical"}
    flow_default.style.vertical_spacing = 4
    flow_default.style.right_padding = 12

    local caption = {"fp.info_label", {"", {"fp.pu_beacon", 1}, " & ", {"fp.pu_module", 2}}}
    local label_beacon = flow_default.add{type="label", caption=caption, style="caption_label"}
    modal_elements["beacon_title"] = label_beacon

    local checkbox_beacon = flow_default.add{type="checkbox", state=false,
        caption={"fp.save_as_default"}, tooltip={"fp.save_as_default_beacon_tt"}}
    modal_elements["beacon_default"] = checkbox_beacon

    local checkbox_amount = flow_default.add{type="checkbox", state=false,
        caption={"fp.save_beacon_amount"}, tooltip={"fp.save_beacon_amount_tt"}}
    modal_elements["beacon_default_amount"] = checkbox_amount

    local flow_submit = parent_frame.add{type="flow", direction="horizontal"}
    flow_submit.style.top_margin = 12
    flow_submit.add{type="empty-widget", style="flib_horizontal_pusher"}
    local button_submit = flow_submit.add{type="button", caption={"fp.set_defaults"}, style="fp_button_green",
        tags={mod="fp", on_gui_click="save_beacon_defaults"}, mouse_button_filter={"left"}}
    button_submit.style.minimal_width = 0

    refresh_defaults_frame(player)
end

local function toggle_defaults_panel(player)
    local modal_elements = util.globals.modal_elements(player)  --[[@as table]]
    local defaults_frame = modal_elements.defaults_box
    defaults_frame.visible = not defaults_frame.visible
    modal_elements.defaults_button.caption = (defaults_frame.visible)
        and {"fp.defaults_close"} or {"fp.defaults_open"}
end

local function save_defaults(player)
    local modal_elements = util.globals.modal_elements(player)
    local beacon = util.globals.modal_data(player).object  --[[@as Beacon]]

    local data = {
        prototype = modal_elements.beacon_default.state and beacon.proto.name or nil,
        quality = modal_elements.beacon_default.state and beacon.quality_proto.name or nil,
        modules = modal_elements.beacon_default.state and beacon.module_set:compile_default() or nil,
        beacon_amount = modal_elements.beacon_default_amount.state and beacon.amount or nil
    }
    prototyper.defaults.set(player, "beacons", data, nil)

    refresh_defaults_frame(player)
    toggle_defaults_panel(player)
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
        tags={mod="fp", on_gui_text_changed="beacon_amount", on_gui_confirmed="beacon_amount",
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
        tags={mod="fp", on_gui_text_changed="beacon_total_amount", on_gui_confirmed="beacon_amount",
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
    local beacon_amount = util.gui.parse_expression_field(modal_data.modal_elements.beacon_amount)

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

local function handle_amount_change(player, _, event)
    local modal_data = util.globals.modal_data(player)  --[[@as table]]
    modal_data.object.amount = util.gui.parse_expression_field(modal_data.modal_elements.beacon_amount) or 0
    modal_data.module_set:normalize({effects=true})

    util.gui.update_expression_field(event.element)
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
    local line = OBJECT_INDEX[modal_data.line_id]
    modal_data.line = line

    if line.beacon ~= nil then
        modal_data.backup_beacon = line.beacon:clone()
        modal_data.object = line.beacon
    else
        local default_beacon = prototyper.defaults.get(player, "beacons")
        modal_data.object = Beacon.init(default_beacon.proto, line)
        modal_data.object.quality_proto = default_beacon.quality
        modal_data.object.amount = default_beacon.beacon_amount or 0
        modal_data.object.module_set:ingest_default(default_beacon.modules)
        line:set_beacon(modal_data.object)
    end
    modal_data.module_set = modal_data.object.module_set


    local flow_content = modal_data.modal_elements.dialog_flow.add{type="flow", direction="horizontal"}
    flow_content.style.horizontal_spacing = 12

    local left_frame = flow_content.add{type="frame", direction="vertical", style="inside_shallow_frame"}
    left_frame.style.vertically_stretchable = true

    local subheader_caption = {("fp.beacon_dialog_description"), line.machine.proto.localised_name}
    local subheader = util.gui.add_modal_subheader(left_frame, subheader_caption, nil)

    subheader.add{type="empty-widget", style="flib_horizontal_pusher"}
    local button_defaults = subheader.add{type="button", caption={"fp.defaults_open"}, style="fp_button_transparent",
        tags={mod="fp", on_gui_click="toggle_beacon_defaults_panel"}}
    modal_data.modal_elements["defaults_button"] = button_defaults

    local left_flow = left_frame.add{type="flow", direction="vertical"}
    left_flow.style.padding = 12

    -- Beacon
    add_beacon_frame(left_flow, modal_data)
    update_profile_label(modal_data)
    update_dialog_submit_button(modal_data)

    -- Modules
    modal_data.submit_checker = "beacon_submit_checker"
    module_configurator.add_modules_flow(left_flow, modal_data)
    module_configurator.refresh_modules_flow(player, false)


    local right_frame = flow_content.add{type="frame", direction="vertical", visible=false, style="inside_shallow_frame"}
    right_frame.style.padding = 12
    right_frame.style.vertically_stretchable = true
    modal_data.modal_elements["defaults_box"] = right_frame

    -- Defaults
    modal_data.defaults_refresher = "beacon_defaults_refresher"
    add_defaults_panel(right_frame, player)
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
            name = "beacon_amount",
            handler = (function(player, _, event)
                local confirmed = util.gui.confirm_expression_field(event.element)
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
            name = "toggle_beacon_defaults_panel",
            handler = toggle_defaults_panel
        },
        {
            name = "save_beacon_defaults",
            handler = save_defaults
        }
    }
}

listeners.dialog = {
    dialog = "beacon",
    metadata = (function(modal_data)
        local line = OBJECT_INDEX[modal_data.line_id]
        return {
            caption = {"", {"fp." .. "edit"}, " ", {"fp.pl_beacon", 1}},
            create_content_frame = false,
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
