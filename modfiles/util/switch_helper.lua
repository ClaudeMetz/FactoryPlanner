local _switch_helper = {}

-- Adds an on/off-switch including a label with tooltip to the given flow
-- Automatically converts boolean state to the appropriate switch_state
---@param parent_flow LuaGuiElement
---@param action string
---@param additional_tags Tags
---@param state SwitchState
---@param caption LocalisedString?
---@param tooltip LocalisedString?
---@param label_first boolean?
---@return LuaGuiElement created_switch
function _switch_helper.add_on_off(parent_flow, action, additional_tags, state, caption, tooltip, label_first)
    if type(state) == "boolean" then state = util.switch_helper.convert_to_state(state) end

    local flow = parent_flow.add{type="flow", direction="horizontal"}
    flow.style.vertical_align = "center"
    local switch, label  ---@type LuaGuiElement, LuaGuiElement

    local function add_switch()
        additional_tags.mod = "fp"; additional_tags.on_gui_switch_state_changed = action
        switch = flow.add{type="switch", tags=additional_tags, switch_state=state,
            left_label_caption={"fp.on"}, right_label_caption={"fp.off"}}
    end

    local function add_label()
        caption = (tooltip ~= nil) and {"", caption, " [img=info]"} or caption
        label = flow.add{type="label", caption=caption, tooltip=tooltip}
        label.style.font = "default-semibold"
    end

    if label_first then add_label(); add_switch(); label.style.right_margin = 8
    else add_switch(); add_label(); label.style.left_margin = 8 end

    return switch
end

---@param state SwitchState
---@return boolean converted_state
function _switch_helper.convert_to_boolean(state)
    return (state == "left") and true or false
end

---@param boolean boolean
---@return SwitchState converted_state
function _switch_helper.convert_to_state(boolean)
    return boolean and "left" or "right"
end

return _switch_helper
