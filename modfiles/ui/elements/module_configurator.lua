local Module = require("backend.data.Module")

-- Contains the UI and event handling for machine/beacon modules
module_configurator = {}

-- ** LOCAL UTIL**
local function determine_slider_config(module, empty_slots)
    local slider_value = (module) and module.amount or empty_slots
    local maximum_value = (module) and (module.amount + empty_slots) or empty_slots
    local minimum_value = (maximum_value == 1) and 0 or 1  -- to make sure that the slider can be created
    return slider_value, maximum_value, minimum_value
end

local function add_module_frame(parent_flow, module, module_filters, empty_slots)
    local module_id = module and module.id or nil

    local frame_module = parent_flow.add{type="frame", style="fp_frame_module", direction="horizontal",
        tags={module_id=module_id}}
    frame_module.add{type="label", caption={"fp.pu_module", 1}, style="semibold_label"}

    local button_module = frame_module.add{type="choose-elem-button", name="fp_chooser_module",
        tags={mod="fp", on_gui_elem_changed="select_module", module_id=module_id},
        elem_type="item-with-quality", elem_filters=module_filters, style="fp_sprite-button_inset"}
    button_module.elem_value = (module) and module:elem_value() or nil

    local label_amount = frame_module.add{type="label", caption={"fp.amount"}, style="semibold_label"}
    label_amount.style.left_margin = 8

    local slider_value, maximum_value, minimum_value = determine_slider_config(module, empty_slots)
    local numeric_enabled = (maximum_value ~= 1 and module ~= nil)

    local slider = frame_module.add{type="slider", name="fp_slider_module_amount",
        tags={mod="fp", on_gui_value_changed="module_amount", module_id=module_id},
        minimum_value=minimum_value, maximum_value=maximum_value, value=slider_value, value_step=0.1}
    slider.style.minimal_width = 0
    slider.style.horizontally_stretchable = true
    slider.style.margin = {0, 6}
    -- Fix for the slider value step "not bug" (see https://forums.factorio.com/viewtopic.php?p=516440#p516440)
    -- Fixed by setting step to something other than 1 first, then setting it to 1
    slider.set_slider_value_step(1)
    slider.enabled = numeric_enabled  -- needs to be set here because sliders are buggy as fuck

    local textfield = frame_module.add{type="textfield", name="fp_textfield_module_amount", enabled=numeric_enabled,
        text=tostring(slider_value), tags={mod="fp", on_gui_text_changed="module_amount", module_id=module_id}}
    util.gui.setup_numeric_textfield(textfield, false, false)
    textfield.style.width = 40
end

local function add_effects_section(parent_flow, object, modal_elements)
    local frame_effects = parent_flow.add{type="frame", direction="vertical", style="fp_frame_bordered_stretch"}
    frame_effects.style.vertically_stretchable = true
    frame_effects.style.width = (MAGIC_NUMBERS.module_dialog_element_width / 2) - 2

    local class_lower = object.class:lower()
    local caption, tooltip = {"", {"fp.pu_" .. class_lower, 1}, " ", {"fp.effects"}}, {""}
    if class_lower == "machine" then caption, tooltip = {"fp.info_label", caption}, {"fp.machine_effects_tt"} end
    frame_effects.add{type="label", caption=caption, tooltip=tooltip, style="semibold_label"}

    local label_effects = frame_effects.add{type="label", caption=object.effects_tooltip}
    label_effects.style.single_line = false
    modal_elements[class_lower .. "_effects_label"] = label_effects
end


local function handle_module_selection(player, tags, event)
    local module_set = util.globals.modal_data(player).module_set
    local new_module = event.element.elem_value

    if tags.module_id then  -- editing an existing module
        local module = OBJECT_INDEX[tags.module_id]  --[[@as Module]]
        if new_module then  -- changed to another module
            module.proto = MODULE_NAME_MAP[new_module.name]
            module.quality_proto = prototyper.util.find("qualities", new_module.quality, nil)
            module:summarize_effects()
        else  -- removed module
            module_set:remove(module)
        end
    elseif new_module then -- choosing a new module on an empty line
        local slider = event.element.parent["fp_slider_module_amount"]
        local module_proto = MODULE_NAME_MAP[new_module.name]
        local module = Module.init(module_proto, slider.slider_value)
        module.quality_proto = prototyper.util.find("qualities", new_module.quality, nil)
        module_set:insert(module)
    end

    module_set:normalize({effects=true})
    module_configurator.refresh_modules_flow(player, false)
end

local function handle_module_slider_change(player, tags, event)
    local module_set = util.globals.modal_data(player).module_set
    local new_slider_value = event.element.slider_value

    local module = OBJECT_INDEX[tags.module_id]  --[[@as Module]]
    module:set_amount(new_slider_value)
    module_set:normalize({effects=true})
    module_configurator.refresh_modules_flow(player, true)
end

local function handle_module_textfield_change(player, tags, event)
    local module_set = util.globals.modal_data(player).module_set
    local new_textfield_value = tonumber(event.element.text)
    local module_slider = event.element.parent["fp_slider_module_amount"]

    local slider_maximum = module_slider.get_slider_maximum()
    local normalized_amount = math.max(1, (new_textfield_value or 1))
    local new_amount = math.min(normalized_amount, slider_maximum)

    local module = OBJECT_INDEX[tags.module_id]  --[[@as Module]]
    module:set_amount(new_amount)
    module_set:normalize({effects=true})
    module_configurator.refresh_modules_flow(player, true)
end


-- ** TOP LEVEL **
function module_configurator.add_modules_flow(parent, modal_data)
    local flow_modules = parent.add{type="flow", direction="vertical"}
    modal_data.modal_elements["modules_flow"] = flow_modules
end

function module_configurator.refresh_effects_flow(modal_data)
    local lower_class = modal_data.object.class:lower()
    local object_label = modal_data.modal_elements[lower_class .. "_effects_label"]
    if not object_label or not object_label.valid then return end

    local line_effects = modal_data.line.effects_tooltip
    local any_line_effects = (#line_effects > 1)

    object_label.parent.parent.visible = any_line_effects
    if any_line_effects then
        object_label.caption = modal_data.object.effects_tooltip
        modal_data.modal_elements["line_effects_label"].caption = line_effects
    end
end

function module_configurator.refresh_modules_flow(player, update_only)
    local modal_data = util.globals.modal_data(player)  --[[@as table]]
    local modules_flow = modal_data.modal_elements.modules_flow

    local module_filters = modal_data.module_set:compile_filter()
    local empty_slots = modal_data.module_set.empty_slots

    if update_only then
        module_configurator.refresh_effects_flow(modal_data)

        -- Update the UI instead of rebuilding it so the slider can be dragged properly
        for _, frame in pairs(modules_flow.children) do
            if frame.name == "flow_effects" then goto skip end

            local module_id = frame.tags.module_id
            if module_id == nil then
                frame.destroy()  -- destroy empty frame as it'll be re-added below
            else
                local module = modal_data.module_set:find({id=module_id})
                if module == nil then
                    frame.destroy()
                else
                    local slider_value, maximum_value, minimum_value = determine_slider_config(module, empty_slots)

                    frame["fp_chooser_module"].elem_value = module:elem_value()

                    local textfield = frame["fp_textfield_module_amount"]
                    textfield.text = tostring(module.amount)
                    textfield.enabled = (maximum_value ~= 1)

                    local slider = frame["fp_slider_module_amount"]
                    slider.set_slider_value_step(0.1)  -- bug workaround
                    slider.set_slider_minimum_maximum(minimum_value, maximum_value)
                    slider.slider_value = slider_value
                    slider.set_slider_value_step(1)  -- bug workaround
                    slider.enabled = (maximum_value ~= 1)
                end
            end
            ::skip::
        end
    else
        modules_flow.clear()

        if #modal_data.line.effects_tooltip > 1 then
            local effects_flow = modules_flow.add{type="flow", direction="horizontal", name="flow_effects"}
            add_effects_section(effects_flow, modal_data.object, modal_data.modal_elements)
            add_effects_section(effects_flow, modal_data.line, modal_data.modal_elements)
        end

        for module in modal_data.module_set:iterator() do
            add_module_frame(modules_flow, module, module_filters, empty_slots)
        end
    end

    if empty_slots > 0 then add_module_frame(modules_flow, nil, module_filters, empty_slots) end
    if modal_data.submit_checker then GLOBAL_HANDLERS[modal_data.submit_checker](modal_data) end

    modules_flow.visible = (#modules_flow.children > 0)
end


-- ** EVENTS **
local listeners = {}

listeners.gui = {
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

return { listeners }
