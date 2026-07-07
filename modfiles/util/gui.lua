local mod_gui = require("mod-gui")

local _gui = { switch = {}, mod = {} }

-- Adds an on/off-switch including a label with tooltip to the given flow
-- Automatically converts boolean state to the appropriate switch_state
---@param parent_flow LuaGuiElement
---@param action string?
---@param additional_tags Tags
---@param state SwitchState | boolean
---@param caption LocalisedString?
---@param tooltip LocalisedString?
---@param label_first boolean?
---@return LuaGuiElement created_switch
function _gui.switch.add_on_off(parent_flow, action, additional_tags, state, caption, tooltip, label_first)
    if type(state) == "boolean" then state = lib.gui.switch.convert_to_state(state) end

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
    end

    if label_first then add_label(); add_switch(); label.style.right_margin = 8
    else add_switch(); add_label(); label.style.left_margin = 8 end

    return switch
end

---@param state SwitchState
---@return boolean converted_state
function _gui.switch.convert_to_boolean(state)
    return (state == "left") and true or false
end

---@param boolean boolean
---@return SwitchState converted_state
function _gui.switch.convert_to_state(boolean)
    return boolean and "left" or "right"
end


---@param player LuaPlayer
local function check_empty_flow(player)
    local button_flow = mod_gui.get_button_flow(player)
    -- parent.parent is to check that I'm not deleting a top level element. Now, I have no idea how that
    -- could ever be a top level element, but oh well, can't know everything now can we?
    if #button_flow.children_names == 0 and button_flow.parent and button_flow.parent.parent then
        button_flow.parent.destroy()
    end
end

-- Destroys the toggle-main-dialog-button if present
---@param player LuaPlayer
local function destroy_mod_gui(player)
    local button_flow = mod_gui.get_button_flow(player)
    local mod_gui_button = button_flow["fp_button_toggle_interface"]
    if mod_gui_button then mod_gui_button.destroy() end
end

-- Toggles the visibility of the toggle-main-dialog-button
---@param player LuaPlayer
function _gui.toggle_mod_gui(player)
    local enable = lib.globals.preferences(player).show_gui_button

    local frame_flow = mod_gui.get_button_flow(player)
    local mod_gui_button = frame_flow["fp_button_toggle_interface"]

    if enable and not mod_gui_button then
        local tooltip = {"", {"shortcut-name.fp_open_interface"}, " (", {"fp.toggle_interface"}, ")"}
        frame_flow.add{type="sprite-button", name="fp_button_toggle_interface", sprite="fp_mod_gui",
            tooltip=tooltip, tags={mod="fp", on_gui_click="mod_gui_toggle_interface"},
            style=mod_gui.button_style, mouse_button_filter={"left"}}
    elseif mod_gui_button then  -- use the destroy function for possible cleanup reasons
        destroy_mod_gui(player)
    end

    -- The simple fact of getting the button flow creates it, so make sure
    -- it doesn't stay around if it's empty
    check_empty_flow(player)
end


---@param player LuaPlayer
---@param metadata table
function _gui.open_dialog(player, metadata)
    GLOBAL_HANDLERS["open_modal_dialog"](player, metadata)
end

---@param player LuaPlayer
---@param action GUICloseAction
---@param skip_opened boolean?
function _gui.close_dialog(player, action, skip_opened)
    GLOBAL_HANDLERS["close_modal_dialog"](player, action, skip_opened)
end

---@class BuildGUIElementEventData
---@field name "build_gui_element"
---@field tick MapTick
---@field player_index PlayerIndex
---@field trigger BuildGUITrigger
---@field parent LuaGuiElement?

---@alias BuildGUITrigger "main_dialog" | "compact_factory"

---@param player LuaPlayer
---@param trigger BuildGUITrigger
---@param parent LuaGuiElement?
function _gui.run_build(player, trigger, parent)
    local event_data = {
        name = "build_gui_element",
        tick = game.tick,
        player_index = player.index,
        trigger = trigger,
        parent = parent
    }  ---@type BuildGUIElementEventData
    GLOBAL_HANDLERS["run_gui_build"](event_data)
end

---@class RefreshGUIElementEventData
---@field name "refresh_gui_element"
---@field tick MapTick
---@field player_index PlayerIndex
---@field trigger RefreshGUITrigger

---@alias RefreshGUITrigger "all" | "factory" | "production" | "title_bar" | "district_info" | "factory_list" | "districts_box" | "production_bar" | "item_boxes" | "production_box" | "production_table" | "compact_factory" | "paste_button"

--- "factory" includes districts_box, production_bar, item_boxes, production_box, production_table
--- "production" includes item_boxes, production_box, production_table
---@param player LuaPlayer
---@param trigger RefreshGUITrigger
function _gui.run_refresh(player, trigger)
    local event_data = {
        name = "refresh_gui_element",
        tick = game.tick,
        player_index = player.index,
        trigger = trigger
    }  ---@type RefreshGUIElementEventData
    GLOBAL_HANDLERS["run_gui_refresh"](event_data)
end


---@param player LuaPlayer
---@return DisplayResolution
function _gui.calculate_scaled_resolution(player)
    local resolution, scale = player.display_resolution, player.display_scale
    return {width=math.ceil(resolution.width / scale), height=math.ceil(resolution.height / scale)}
end

---@param textfield LuaGuiElement
---@param decimal boolean
---@param negative boolean
function _gui.setup_numeric_textfield(textfield, decimal, negative)
    textfield.lose_focus_on_confirm = true
    textfield.numeric = true
    textfield.allow_decimal = (decimal or false)
    textfield.allow_negative = (negative or false)
end

---@param textfield LuaGuiElement
function _gui.select_all(textfield)
    textfield.focus()
    textfield.select_all()
end

-- Destroys all GUIs so they are loaded anew the next time they are shown
---@param player LuaPlayer
function _gui.reset_player(player)
    destroy_mod_gui(player)  -- mod_gui button
    check_empty_flow(player)  -- make sure no empty flow is left behind

    for _, gui_element in pairs(player.gui.screen.children) do  -- all mod frames
        if gui_element.valid and gui_element.get_mod() == "factoryplanner" then
            gui_element.destroy()
        end
    end
end


---@param satisfied_amount number
---@param actual_amount number
---@return LocalisedString satisfaction_line
---@return string percentage_string
function _gui.calculate_satisfaction(satisfied_amount, actual_amount)
    local satisfied_percentage = (satisfied_amount / actual_amount) * 100
    local percentage_string = lib.format.number(satisfied_percentage, 3)
    local satisfaction_line = {"", "\n", {"fp.bold_label", (percentage_string .. "%")}, " ", {"fp.satisfied"}}
    return satisfaction_line, percentage_string
end


local expression_variables = {k=1000, K=1000, m=1000000, M=1000000, g=1000000000, G=1000000000}

---@param textfield LuaGuiElement
---@param positive boolean
---@return number? expression
function _gui.parse_expression_field(textfield, positive)
    local expression = nil
    pcall(function() expression = helpers.evaluate_expression(textfield.text, expression_variables) end)
    ---@cast expression double?

    if expression == nil then return nil
    elseif positive and expression <= 0 then return nil
    else return expression end
end

---@param textfield LuaGuiElement
---@param valid boolean
function _gui.update_expression_field(textfield, valid)
    textfield.style = (textfield.text ~= "" and not valid) and "invalid_value_textfield" or "textbox"
    -- This is stupid but styles work out that way
    textfield.style--[[@as LuaStyle]].width = textfield.tags.width  --[[@as int32]]
end

---@param textfield LuaGuiElement
---@param positive boolean
---@return boolean confirmed
function _gui.confirm_expression_field(textfield, positive)
    local expression = _gui.parse_expression_field(textfield, positive)

    if expression then
        local exp = tostring(expression)
        if exp == textfield.text then
            return true
        else
            textfield.text = exp
        end
    end
    return false
end


---@param data_type DataType
---@return PrototypeFilter elem_filter
function _gui.compile_elem_filter(data_type)
    local names = {}
    for _, proto in pairs(storage.prototypes[data_type]) do
        table.insert(names, proto.name)
    end
    return {{filter="name", name=names}}
end

return _gui
