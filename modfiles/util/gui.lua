local _gui = {}

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
function _gui.setup_textfield(textfield)
    textfield.lose_focus_on_confirm = true
    textfield.clear_and_focus_on_right_click = true
end

---@param textfield LuaGuiElement
---@param decimal boolean
---@param negative boolean
function _gui.setup_numeric_textfield(textfield, decimal, negative)
    textfield.lose_focus_on_confirm = true
    textfield.clear_and_focus_on_right_click = true
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
    util.mod_gui.destroy(player)  -- mod_gui button

    for _, gui_element in pairs(player.gui.screen.children) do  -- all mod frames
        if gui_element.valid and gui_element.get_mod() == "factoryplanner" then
            gui_element.destroy()
        end
    end
end

-- Formats the given effects for use in a tooltip
---@param effects ModuleEffects
---@param limit_effects boolean
---@return LocalisedString
function _gui.format_module_effects(effects, limit_effects)
    local tooltip_lines, effect_applies = {"", "\n"}, false
    local lower_bound, upper_bound = MAGIC_NUMBERS.effects_lower_bound, MAGIC_NUMBERS.effects_upper_bound

    for effect_name, effect_value in pairs(effects) do
        if effect_value ~= 0 then
            effect_applies = true
            local capped_indication = ""  ---@type LocalisedString

            if limit_effects then
                if effect_name == "productivity" and effect_value < 0 then
                    effect_value, capped_indication = 0, {"fp.effect_maxed"}
                elseif effect_value < lower_bound then
                    effect_value, capped_indication = lower_bound, {"fp.effect_maxed"}
                elseif effect_value > upper_bound then
                    effect_value, capped_indication = upper_bound, {"fp.effect_maxed"}
                end
            end

            -- Force display of either a '+' or '-', also round the result
            local display_value = ("%+d"):format(math.floor((effect_value * 100) + 0.5))
            table.insert(tooltip_lines, {"fp.effect_line", {"fp." .. effect_name}, display_value, capped_indication})
        end
    end

    return (effect_applies) and tooltip_lines or ""
end

return _gui
