local _actions = {}

---@alias ActionList table<string, string>
---@alias GUIActionFlags table<string, boolean?>
---@alias GUIActionCondition fun(flags: GUIActionFlags): boolean?
---@alias GUIActionEnableCondition fun(flags: GUIActionFlags): boolean?, LocalisedString?


---@param action GUIAction
---@param flags GUIActionFlags?
---@return boolean?
function _actions.is_visible(action, flags)
    return action.show == nil or action.show(flags or {})
end

---@param action GUIAction
---@param flags GUIActionFlags?
---@return boolean
---@return LocalisedString? warning
function _actions.is_enabled(action, flags)
    if action.enable == nil then return true end
    local enabled, warning = action.enable(flags or {})
    if enabled then return true end
    return false, warning
end


-- Shared availability checks; cursor and factoriopedia flags describe whether the action has a target.
---@param flags GUIActionFlags
---@return boolean
---@return LocalisedString? warning
function _actions.can_edit_factory(flags)
    if flags.archived then return false, {"fp.factory_archived_edit"} end
    return true
end

---@param flags GUIActionFlags
---@return boolean
---@return LocalisedString? warning
function _actions.can_put_into_cursor(flags)
    if not flags.cursor then return false, {"fp.put_into_cursor_unavailable"} end
    return true
end

---@param flags GUIActionFlags
---@return boolean
---@return LocalisedString? warning
function _actions.can_open_factoriopedia(flags)
    if not flags.factoriopedia then return false, {"fp.no_factoriopedia_entry"} end
    return true
end

---@param flags GUIActionFlags
---@return boolean
---@return LocalisedString? warning
function _actions.can_edit_temperature(flags)
    if flags.archived then return false, {"fp.factory_archived_edit"} end
    if not flags.multiple_temperatures then return false, {"fp.only_one_available_option"} end
    return true
end

---@param flags GUIActionFlags
---@return boolean
---@return LocalisedString? warning
function _actions.can_add_recipe(flags)
    if flags.archived then return false, {"fp.factory_archived_edit"} end
    if flags.wrong_floor then return false, {"fp.item_recipe_wrong_floor"} end
    if flags.ingredient_only and not flags.byproduct then return false, {"fp.item_has_no_recipes"} end
    return true
end


-- Returns whether rate limiting is active for the given action, stopping it from proceeding
-- This is essentially to prevent duplicate commands in quick succession, enabled by lag
---@param player LuaPlayer
---@param tick MapTick
---@param action_name string | defines.events
---@param timeout MapTick?
---@return boolean
function _actions.rate_limited(player, tick, action_name, timeout)
    local ui_state = lib.globals.ui_state(player)

    -- If this action has no timeout, reset the last action and allow it
    if timeout == nil or game.tick_paused then
        ui_state.last_action = nil
        return false
    end

    local last_action = ui_state.last_action
    -- Only disallow action under these specific circumstances
    if last_action and last_action.action_name == action_name and (tick - last_action.tick) < timeout then
        return true

    else  -- set the last action if this action will actually be carried out
        ui_state.last_action = {
            action_name = action_name,
            tick = tick
        }
        return false
    end
end


---@param shortcut string?
---@return LocalisedString?
function _actions.shortcut_string(shortcut)
    if not shortcut then return nil end
    local split_modifiers, modifier_string = lib.split_string(shortcut, "-"), {""}
    for _, modifier in pairs(lib.flib.slice(split_modifiers, 1, -1)) do
        table.insert(modifier_string, {"", {"fp.action_" .. modifier}, " + "})
    end
    table.insert(modifier_string, {"fp.action_" .. split_modifiers[#split_modifiers]})
    return {"fp.action_click", modifier_string}
end

---@param actions GUIAction[]
---@param flags GUIActionFlags?
---@return LocalisedString
function _actions.generate_tooltip(actions, flags)
    local tooltip, show_context_hint = {""}, false
    for _, action in pairs(actions) do
        if lib.actions.is_visible(action, flags) then
            if action.core and lib.actions.is_enabled(action, flags) then
                table.insert(tooltip, {"fp.action_line", action.binding_string, {"fp.action_" .. action.name}})
            else
                show_context_hint = true
            end
        end
    end

    if show_context_hint then table.insert(tooltip, {"fp.action_all"}) end

    return tooltip
end

return _actions
