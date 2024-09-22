local _actions = {}

---@alias ActionLimitations { archive_open: boolean?, matrix_active: boolean? }
---@alias ActiveLimitations { archive_open: boolean, matrix_active: boolean }
---@alias ActionList { [string]: string }

---@param player LuaPlayer
---@return ActiveLimitations
function _actions.current_limitations(player)
    local factory = util.context.get(player, "Factory")  --[[@as Factory?]]
    return {
        archive_open = (factory ~= nil) and factory.archived or false,
        matrix_active = (factory ~= nil) and (factory.matrix_free_items ~= nil) or false
    }
end

---@param action_limitations ActionLimitations[]
---@param active_limitations ActiveLimitations
---@return boolean
function _actions.allowed(action_limitations, active_limitations)
    -- If a particular limitation is nil, it indicates that the action is allowed regardless
    -- If it is non-nil, it needs to match the current state of the limitation exactly
    for limitation_name, limitation in pairs(action_limitations) do
        if active_limitations[limitation_name] ~= limitation then return false end
    end
    return true
end

-- Returns whether rate limiting is active for the given action, stopping it from proceeding
-- This is essentially to prevent duplicate commands in quick succession, enabled by lag
function _actions.rate_limited(player, tick, action_name, timeout)
    local ui_state = util.globals.ui_state(player)

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


---@param shortcut string
---@return LocalisedString?
function _actions.shortcut_string(shortcut)
    if not shortcut then return nil end
    local split_modifiers, modifier_string = util.split_string(shortcut, "-"), {""}
    for _, modifier in pairs(ftable.slice(split_modifiers, 1, -1)) do
        table.insert(modifier_string, {"", {"fp.action_" .. modifier}, " + "})
    end
    table.insert(modifier_string, {"fp.action_" .. split_modifiers[#split_modifiers]})
    return {"fp.action_click", modifier_string}
end

---@param actions ActionDetails[]
---@return LocalisedString
function _actions.generate_tooltip(actions)
    local tooltip, any_hidden = {""}, false
    for _, action in pairs(actions) do
        if action.show then
            table.insert(tooltip, {"fp.action_line", action.shortcut_string, {"fp.action_" .. action.name}})
        else
            any_hidden = true
        end
    end

    if any_hidden then table.insert(tooltip, {"fp.action_all"}) end

    return tooltip
end

return _actions
