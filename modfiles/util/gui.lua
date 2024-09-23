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
    if type(state) == "boolean" then state = util.gui.switch.convert_to_state(state) end

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


local function check_empty_flow(player)
    local button_flow = mod_gui.get_button_flow(player)
    -- parent.parent is to check that I'm not deleting a top level element. Now, I have no idea how that
    -- could ever be a top level element, but oh well, can't know everything now can we?
    if #button_flow.children_names == 0 and button_flow.parent.parent then
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
    local enable = util.globals.preferences(player).show_gui_button

    local frame_flow = mod_gui.get_button_flow(player)
    local mod_gui_button = frame_flow["fp_button_toggle_interface"]

    if enable and not mod_gui_button then
        local tooltip = {"", {"shortcut-name.fp_open_interface"}, " (", {"fp.toggle_interface"}, ")"}
        local button = frame_flow.add{type="sprite-button", name="fp_button_toggle_interface",
            sprite="fp_mod_gui", tooltip=tooltip, tags={mod="fp", on_gui_click="mod_gui_toggle_interface"},
            style=mod_gui.button_style, mouse_button_filter={"left"}}
        button.style.padding = 6
    elseif mod_gui_button then  -- use the destroy function for possible cleanup reasons
        destroy_mod_gui(player)
    end

    -- The simple fact of getting the button flow creates it, so make sure
    -- it doesn't stay around if it's empty
    check_empty_flow(player)
end


-- Properly centers the given frame (need width/height parameters cause no API-read exists)
---@param player LuaPlayer
---@param frame LuaGuiElement
---@param dimensions DisplayResolution
function _gui.properly_center_frame(player, frame, dimensions)
    local resolution, scale = player.display_resolution, player.display_scale
    local x_offset = ((resolution.width - (dimensions.width * scale)) / 2)
    local y_offset = ((resolution.height - (dimensions.height * scale)) / 2)
    frame.location = {x_offset, y_offset}
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


---@class FormatModuleEffectsOptions
---@field indications { ModuleEffectName: string }?
---@field machine_effects ModuleEffects?
---@field recipe_effects ModuleEffects?

-- Formats the given effects for use in a tooltip
---@param module_effects ModuleEffects
---@param options FormatModuleEffectsOptions?
---@return LocalisedString
function _gui.format_module_effects(module_effects, options)
    options = options or {}
    options.indications = options.indications or {}
    options.machine_effects = options.machine_effects or {}
    options.recipe_effects = options.recipe_effects or {}

    local function format_effect(value, color)
        if value == nil then return "" end
        -- Force display of either a '+' or '-', also round the result
        local display_value = ("%+d"):format(math.floor((value * 100) + 0.5))
        return {"fp.effect_value", color, display_value}
    end

    local tooltip_lines = {""}
    for effect_name, _ in pairs(BLANK_EFFECTS) do
        local module_effect = module_effects[effect_name]
        local machine_effect = options.machine_effects[effect_name]
        local recipe_effect = options.recipe_effects[effect_name]

        if options.indications[effect_name] ~= nil or module_effect ~= 0
                or (machine_effect ~= nil and machine_effect ~= 0)
                or (recipe_effect ~= nil and recipe_effect ~= 0) then
            local module_percentage = format_effect(module_effect, "#FFE6C0")
            local machine_percentage = format_effect(machine_effect, "#7CFF01")
            local recipe_percentage = format_effect(recipe_effect, "#01FFF4")

            if #tooltip_lines > 1 then table.insert(tooltip_lines, "\n") end
            table.insert(tooltip_lines, {"fp.effect_line", {"fp." .. effect_name}, module_percentage,
                machine_percentage, recipe_percentage, options.indications[effect_name] or ""})
        end
    end

    return tooltip_lines
end


---@param emissions number
---@param district District
---@return LocalisedString tooltip
function _gui.format_emissions(emissions, district)
    if emissions == 0 then
        return {"fp.emissions_none"}
    else
        local pollutant = {"airborne-pollutant-name." .. district.location_proto.pollutant_type}
        local emission = util.format.SI_value(emissions, "E/m", 3)
        return {"fp.emissions_line", pollutant, emission}
    end
end


local expression_variables = {k=1000, K=1000, m=1000000, M=1000000, g=1000000000, G=1000000000}

---@param textfield LuaGuiElement
---@return number? expression
function _gui.parse_expression_field(textfield)
    local expression = nil
    pcall(function() expression = game.evaluate_expression(textfield.text, expression_variables) end)
    return expression
end

---@param textfield LuaGuiElement
function _gui.update_expression_field(textfield)
    local expression = _gui.parse_expression_field(textfield)

    textfield.style = (textfield.text ~= "" and expression == nil) and "invalid_value_textfield" or "textbox"
    textfield.style.width = textfield.tags.width  --[[@as number]]  -- this is stupid but styles work out that way
end

---@param textfield LuaGuiElement
---@return boolean confirmed
function _gui.confirm_expression_field(textfield)
    local expression = _gui.parse_expression_field(textfield)
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

return _gui
