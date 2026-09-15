local Beacon = require("backend.data.Beacon")

---@class BeaconDialogModalData: ModuleConfiguratorModalData
---@field line_id ObjectID
---@field object Beacon
---@field beacon_backup Beacon

-- ** LOCAL UTIL **
---@param player LuaPlayer
local function refresh_defaults_buttons(player)
    local modal_data = lib.globals.modal_data(player)  ---@as BeaconDialogModalData
    local modal_elements = modal_data.modal_elements
    local beacon = modal_data.object  ---@as Beacon

    local beacon_tooltip = defaults.generate_tooltip(player, "beacons", nil)
    local beacon_default = defaults.get(player, "beacons", nil)
    local equals_beacon = defaults.equals_default(player, "beacons", beacon, nil)
    local equals_amount = (beacon_default.beacon_amount == beacon.amount)

    modal_elements.beacon.tooltip = {"", {"fp.save_as_default_beacon"}, "\n\n", beacon_tooltip}
    modal_elements.beacon.enabled = not equals_beacon
    modal_elements.amount.enabled = not equals_amount
end

---@class SetBeaconDefaultTags
---@field action "beacon" | "amount"

---@param player LuaPlayer
---@param tags SetBeaconDefaultTags
local function set_defaults(player, tags, _)
    local modal_data = lib.globals.modal_data(player)  ---@as BeaconDialogModalData
    local beacon = modal_data.object

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

    refresh_defaults_buttons(player)
end


---@param parent_flow LuaGuiElement
---@param modal_data BeaconDialogModalData
local function add_beacon_frame(parent_flow, modal_data)
    local modal_elements = modal_data.modal_elements
    local beacon = modal_data.object

    local frame_beacon = parent_flow.add{type="frame", style="fp_frame_module", direction="horizontal"}
    frame_beacon.style.width = MAGIC_NUMBERS.module_dialog_element_width

    local flow_beacon = frame_beacon.add{type="flow", direction="horizontal"}
    flow_beacon.style.horizontal_spacing = 4
    flow_beacon.style.vertical_align = "center"

    local button_beacon = flow_beacon.add{type="choose-elem-button", elem_type="entity-with-quality",
        tags={mod="fp", on_gui_elem_changed="select_beacon"}, elem_filters=lib.gui.compile_elem_filter("beacons"),
        style="fp_sprite-button_inset"}
    button_beacon.style.size = 40
    modal_elements["beacon_button"] = button_beacon

    local beacon_tags = {mod="fp", on_gui_click="set_beacon_default", action="beacon"}
    modal_elements["beacon"] = flow_beacon.add{type="sprite-button", tags=beacon_tags,
        sprite="fp_default", style="tool_button"}

    local amount_tags = {mod="fp", on_gui_click="set_beacon_default", action="amount"}
    modal_elements["amount"] = flow_beacon.add{type="sprite-button", tags=amount_tags, sprite="fp_amount",
        tooltip={"fp.save_beacon_amount"}, style="tool_button"}

    frame_beacon.add{type="empty-widget", style="fflib_horizontal_pusher"}
    local flow_amount = frame_beacon.add{type="flow", direction="horizontal"}
    flow_amount.style.horizontal_spacing = 8
    flow_amount.style.vertical_align = "center"
    flow_amount.add{type="label", caption={"fp.info_label", {"fp.beacon_amount"}},
        tooltip={"fp.beacon_amount_tt"}, style="semibold_label"}

    local textfield_amount = flow_amount.add{type="textfield",
        tags={mod="fp", on_gui_text_changed="beacon_amount", on_gui_confirmed="confirm_beacon",
        width=36}, tooltip={"fp.expression_textfield"}}
    textfield_amount.style.width = 36
    modal_elements["beacon_amount"] = textfield_amount

    local label_effectivity = flow_amount.add{type="label"}
    label_effectivity.style.width = 52
    modal_elements["effectivity_label"] = label_effectivity

    frame_beacon.add{type="empty-widget", style="fflib_horizontal_pusher"}
    local flow_ratio = frame_beacon.add{type="flow", direction="horizontal"}
    flow_ratio.style.horizontal_spacing = 8
    flow_ratio.style.vertical_align = "center"
    flow_ratio.add{type="label", caption={"fp.info_label", {"fp.beacon_per_machine"}},
        tooltip={"fp.beacon_per_machine_tt"}, style="semibold_label"}
    local textfield_ratio = flow_ratio.add{type="textfield", text=tostring(beacon.amount_per_machine or ""),
        tags={mod="fp", on_gui_text_changed="beacon_per_machine", on_gui_confirmed="confirm_beacon",
        width=36}, tooltip={"fp.expression_textfield"}}
    textfield_ratio.style.width = 36
    modal_elements["beacon_per_machine"] = textfield_ratio
end


---@param modal_data BeaconDialogModalData
local function update_effectivity_label(modal_data)
    local beacon = modal_data.object
    local proto = beacon.proto  ---@as FPBeaconPrototype
    local quality_level = beacon.quality_proto--[[@as FPQualityPrototype]].level
    local distribution_effectivity = (proto.effectivity
        + proto.distribution_effectivity_bonus_per_quality_level * quality_level) * 100
    local effectivity = ("%.2f"):format(beacon:overall_effectivity() * 100):gsub("%.?0+$", "")
    local label = modal_data.modal_elements.effectivity_label
    label.caption = effectivity .. "%"
    label.tooltip = {"fp.beacon_effectivity_tt", beacon.amount, beacon:profile_multiplier(),
        ("%.2f"):format(distribution_effectivity):gsub("%.?0+$", ""), effectivity}
end

---@param modal_data BeaconDialogModalData
local function refresh_beacon_controls(modal_data)
    local beacon = modal_data.object
    local is_mono_beacon = beacon:is_mono_beacon()
    if is_mono_beacon and beacon.amount ~= 1 then
        beacon.amount = 1
        beacon:summarize_effects()
    end

    local modal_elements = modal_data.modal_elements
    modal_elements.beacon_button.elem_value = beacon:elem_value()
    local textfield = modal_elements.beacon_amount
    textfield.enabled = not is_mono_beacon
    textfield.text = (beacon.amount ~= 0) and tostring(beacon.amount) or ""
    lib.gui.update_expression_field(textfield, beacon.amount > 0)
    update_effectivity_label(modal_data)
end

---@param modal_data BeaconDialogModalData
local function update_dialog_submit_button(modal_data)
    local beacon_amount = modal_data.object.amount

    local message  ---@type LocalisedString
    if not beacon_amount or beacon_amount == 0 then
        message = {"fp.beacon_issue_set_amount"}
    elseif modal_data.module_set.module_count == 0 then
        message = {"fp.beacon_issue_no_modules"}
    elseif modal_data.modal_elements.beacon_per_machine.text ~= ""
        and modal_data.object.amount_per_machine == nil then
        message = {"fp.beacon_issue_per_machine"}
    end
    modal_dialog.set_submit_button_state(modal_data.modal_elements, (message == nil), message)
end


---@param player LuaPlayer
local function reset_beacon(player)
    local modal_data = lib.globals.modal_data(player)  ---@as BeaconDialogModalData
    local beacon = modal_data.object
    beacon:reset(player)

    refresh_beacon_controls(modal_data)
    module_configurator.refresh_modules_flow(player, false)
end


---@param player LuaPlayer
local function handle_beacon_change(player, _, _)
    local modal_data = lib.globals.modal_data(player)  ---@as BeaconDialogModalData
    local beacon = modal_data.object
    local beacon_button = modal_data.modal_elements.beacon_button
    local elem_value = beacon_button.elem_value

    if not elem_value then
        beacon_button.elem_value = beacon:elem_value()  -- reset the beacon so it can't be nil
        lib.cursor.create_flying_text(player, {"fp.no_removal", {"fp.pu_beacon", 1}})
        return  -- nothing changed
    end

    -- Change the beacon to the new type
    beacon.proto = prototyper.util.find("beacons", elem_value.name, nil)
    beacon.quality_proto = prototyper.util.find("qualities", elem_value.quality, nil)
    beacon.module_set:normalize({compatibility=true, trim=true, effects=true})

    refresh_beacon_controls(modal_data)
    module_configurator.refresh_modules_flow(player, false)
end

---@param player LuaPlayer
local function handle_amount_change(player, _, _)
    local modal_data = lib.globals.modal_data(player)  ---@as BeaconDialogModalData
    local textfield = modal_data.modal_elements.beacon_amount

    local amount = lib.gui.parse_expression_field(textfield, true)
    local valid = (amount ~= nil and amount % 1 == 0)  ---@cast amount integer
    lib.gui.update_expression_field(textfield, valid)

    modal_data.object.amount = (valid) and amount or 0
    modal_data.module_set:normalize({effects=true})

    update_effectivity_label(modal_data)
    module_configurator.refresh_modules_flow(player, false)
end

---@param player LuaPlayer
---@param modal_data BeaconDialogModalData
local function open_beacon_dialog(player, modal_data)
    local line = OBJECT_INDEX[modal_data.line_id]  ---@as Line
    modal_data.line = line

    if line.beacon ~= nil then
        modal_data.beacon_backup = line.beacon:clone(player)
        modal_data.object = line.beacon
    else
        local default_beacon = defaults.get(player, "beacons")
        modal_data.object = Beacon.init(line, default_beacon.proto--[[@as FPBeaconPrototype]])
        modal_data.object.quality_proto = default_beacon.quality
        modal_data.object.amount = default_beacon.beacon_amount or 0
        if modal_data.object:is_mono_beacon() then modal_data.object.amount = 1 end
        modal_data.object.module_set:ingest_default(default_beacon.modules--[[@cast -nil]])
        line:set_beacon(modal_data.object)
    end
    modal_data.module_set = modal_data.object.module_set

    local content_frame = modal_data.modal_elements.content_frame

    -- Beacon
    add_beacon_frame(content_frame, modal_data)
    refresh_beacon_controls(modal_data)
    local textfield_amount = modal_data.modal_elements.beacon_amount
    if textfield_amount.enabled then lib.gui.select_all(textfield_amount) end

    -- Modules
    modal_data.submit_checker = "beacon_submit_checker"
    modal_data.defaults_refresher = "beacon_defaults_refresher"
    module_configurator.add_modules_flow(content_frame, modal_data)
    module_configurator.refresh_modules_flow(player, false)
end

---@param player LuaPlayer
---@param action GUICloseAction
local function close_beacon_dialog(player, action)
    local modal_data = lib.globals.modal_data(player)  ---@as BeaconDialogModalData

    if action == "submit" then
        solver.update(player)
        lib.gui.run_refresh(player, "production")

    elseif action == "delete" then
        modal_data.line:set_beacon(nil)
        solver.update(player)
        lib.gui.run_refresh(player, "production")

    else -- action == "cancel"
        modal_data.line:set_beacon(modal_data.beacon_backup)  -- could be nil
        -- Need to refresh so the buttons have the 'new' backup beacon for further actions
        lib.gui.run_refresh(player, "production")
    end
end


-- ** EVENTS **
local listeners = {}  ---@type ListenerDefinitions

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
            name = "beacon_per_machine",
            handler = function(player, _, event)
                ---@cast event EventData.on_gui_text_changed
                local ratio = lib.gui.parse_expression_field(event.element, true)
                lib.gui.update_expression_field(event.element, ratio ~= nil or event.element.text == "")

                local modal_data = lib.globals.modal_data(player)  ---@as BeaconDialogModalData
                modal_data.object.amount_per_machine = ratio
                update_dialog_submit_button(modal_data)
            end
        }
    },
    on_gui_confirmed = {
        {
            name = "confirm_beacon",
            handler = function(player, _, event)
                ---@cast event EventData.on_gui_confirmed
                local element = event.element  ---@as LuaGuiElement
                local ratio_field = lib.globals.modal_elements(player).beacon_per_machine
                local confirmed = (element == ratio_field and element.text == "")
                    or lib.gui.confirm_expression_field(element, true)
                if confirmed then lib.gui.close_dialog(player, "submit") end
            end
        }
    },
    on_gui_click = {
        {
            name = "set_beacon_default",
            handler = set_defaults
        }
    }
}  ---@as GUIListenerDefinition

listeners.dialog = {
    dialog = "beacon",
    metadata = function(modal_data)
        ---@cast modal_data BeaconDialogModalData
        local line = OBJECT_INDEX[modal_data.line_id]  ---@as Line
        local machine_name = line.machine.proto.localised_name
        return {
            caption = {"", {"fp." .. "edit"}, " ", {"fp.pl_beacon", 1}},
            subheader_text = {"fp.beacon_dialog_description", machine_name},
            show_submit_button = true,
            show_delete_button = (line.beacon ~= nil),
            reset_handler_name = "reset_beacon"
        }  ---@as ModalDialogSettings
    end,
    open = open_beacon_dialog,
    close = close_beacon_dialog
}

listeners.global = {
    beacon_defaults_refresher = refresh_defaults_buttons,
    beacon_submit_checker = update_dialog_submit_button,
    reset_beacon = reset_beacon
}

return { listeners }
