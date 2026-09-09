local _actions = {}

---@alias ActionList table<string, string>
---@alias GUIActionFlags table<string, boolean?>
---@alias GUIActionCondition fun(flags: GUIActionFlags): boolean?

-- Predicates inspect button identity only; absent flags are falsy.
---@param action GUIAction
---@param flags GUIActionFlags?
---@return boolean?
function _actions.is_visible(action, flags)
    return action.show == nil or action.show(flags or {})
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
    local tooltip, any_non_core = {""}, false
    for _, action in pairs(actions) do
        if lib.actions.is_visible(action, flags) then
            if action.core then
                table.insert(tooltip, {"fp.action_line", action.shortcut_string, {"fp.action_" .. action.name}})
            else
                any_non_core = true
            end
        end
    end

    if any_non_core then table.insert(tooltip, {"fp.action_all"}) end

    return tooltip
end

return _actions
