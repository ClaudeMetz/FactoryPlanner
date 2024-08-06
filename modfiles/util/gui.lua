local mod_gui = require("mod-gui")

local _gui = { switch = {}, mod = {} }


-- Adds an on/off-switch including a label with tooltip to the given flow
-- Automatically converts boolean state to the appropriate switch_state
---@param parent_flow LuaGuiElement
---@param action string
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
---@field limit boolean?
---@field max_prod number?
---@field machine_effects ModuleEffects?
---@field recipe_effects ModuleEffects?

-- Formats the given effects for use in a tooltip
---@param module_effects ModuleEffects
---@param options FormatModuleEffectsOptions?
---@return LocalisedString
function _gui.format_module_effects(module_effects, options)
    options = options or {}
    options.limit = options.limit or false
    options.max_prod = options.max_prod or nil
    options.machine_effects = options.machine_effects or {}
    options.recipe_effects = options.recipe_effects or {}

    local positive_only_effects = {productivity=true, quality=true}
    local lower_bound = MAGIC_NUMBERS.effects_lower_bound
    local upper_bound = MAGIC_NUMBERS.effects_upper_bound

    local function limit_effect(value, name)
        if options.limit == true then
            if positive_only_effects[name] and value < 0 then
                return 0, {"fp.effect_limit"}
            elseif name == "productivity" and value > options.max_prod then
                return options.max_prod, {"fp.effect_max"}
            elseif value < lower_bound then
                return lower_bound, {"fp.effect_limit"}
            elseif value > upper_bound then
                return upper_bound, {"fp.effect_max"}
            end
        end
        return value, ""  -- return value if nothing above hits
    end

    local function format_effect(name, value, color)
        if value == nil or (value == 0 and not positive_only_effects[name]) then return "" end
        -- Force display of either a '+' or '-', also round the result
        local display_value = ("%+d"):format(math.floor((value * 100) + 0.5))
        return {"fp.effect_value", color, display_value}
    end

    local tooltip_lines = {""}
    for effect_name, _ in pairs(BLANK_EFFECTS) do
        local module_effect = module_effects[effect_name]
        local machine_effect = options.machine_effects[effect_name]
        local recipe_effect = options.recipe_effects[effect_name]

        if module_effect ~= 0 or (machine_effect ~= nil and machine_effect ~= 0)
                or (recipe_effect ~= nil and recipe_effect ~= 0) then
            -- Limiting only for module effects, which is only used without any other effect types
            local limited_module_effect, indication = limit_effect(module_effect, effect_name)

            local module_percentage = format_effect(effect_name, limited_module_effect, "#FFE6C0")
            local machine_percentage = format_effect(effect_name, machine_effect, "#7CFF01")
            local recipe_percentage = format_effect(effect_name, recipe_effect, "#01FFF4")

            if #tooltip_lines > 1 then table.insert(tooltip_lines, "\n") end
            table.insert(tooltip_lines, {"fp.effect_line", {"fp." .. effect_name}, module_percentage,
                machine_percentage, recipe_percentage, indication})
        end
    end

    return tooltip_lines
end


---@param emissions Emissions
---@return LocalisedString emissions_list
function _gui.format_emissions(emissions)
    local emissions_list = {""}
    for type, value in pairs(emissions) do
        if value > 0 then
            if #emissions_list > 1 then table.insert(emissions_list, "\n") end
            local pollutant = {"airborne-pollutant-name." .. type}
            local emission = util.format.SI_value(value, "E/m", 3)
            table.insert(emissions_list, {"fp.emissions_line", pollutant, emission})
        end
    end
    if #emissions_list == 1 then table.insert(emissions_list, {"fp.emissions_none"}) end
    return emissions_list
end


return _gui
