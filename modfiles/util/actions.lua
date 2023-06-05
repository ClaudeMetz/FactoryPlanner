local _actions = {}

---@alias ActionLimitations { archive_open: boolean?, matrix_active: boolean?, recipebook: boolean? }
---@alias ActiveLimitations { archive_open: boolean, matrix_active: boolean, recipebook: boolean }
---@alias ActionList { [string]: string }

---@param player LuaPlayer
---@return ActiveLimitations
function _actions.current_limitations(player)
    local ui_state = util.globals.ui_state(player)
    return {
        archive_open = ui_state.flags.archive_open,
        matrix_active = (ui_state.context.subfactory.matrix_free_items ~= nil),
        recipebook = RECIPEBOOK_ACTIVE
    }
end

---@param action_limitations ActionLimitations
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

---@param action_name string
---@param active_limitations ActiveLimitations
---@param player LuaPlayer?
---@return LocalisedString
function _actions.tutorial_tooltip(action_name, active_limitations, player)
    active_limitations = active_limitations or util.actions.current_limitations(player)

    local tooltip = {"", "\n"}
    for _, action_line in pairs(TUTORIAL_TOOLTIPS[action_name]) do
        if util.actions.allowed(action_line.limitations, active_limitations) then
            table.insert(tooltip, action_line.string)
        end
    end

    return tooltip
end

---@param data table
---@param player LuaPlayer
---@param action_list ActionList
function _actions.tutorial_tooltip_list(data, player, action_list)
    local active_limitations = util.actions.current_limitations(player)  -- done here so it's 'cached'
    for reference_name, action_name in pairs(action_list) do
        data[reference_name] = util.actions.tutorial_tooltip(action_name, active_limitations, nil)
    end
end

function _actions.all_tutorial_tooltips(modifier_actions)
    local action_lines = {}

    for modifier_click, modifier_action in pairs(modifier_actions) do
        local split_modifiers = data_util.split_string(modifier_click, "-")

        local modifier_string = {""}
        for _, modifier in pairs(fancytable.slice(split_modifiers, 1, -1)) do
            table.insert(modifier_string, {"", {"fp.tut_" .. modifier}, " + "})
        end
        table.insert(modifier_string, {"fp.tut_" .. split_modifiers[#split_modifiers]})

        local action_string = {"fp.tut_action_line", modifier_string, {"fp.tut_" .. modifier_action.name}}
        table.insert(action_lines, {string=action_string, limitations=modifier_action.limitations})
    end

    return action_lines
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

function _actions.guard(handler, arguments)
    if DEV_ACTIVE and not DEBUGGER_ACTIVE then
        local status, result = xpcall(handler, debug.traceback, table.unpack(arguments))
        if status then
            return result
        else
            llog(result)
            game.print({"fp.error_message", "Error: " .. data_util.split_string(result, "\n")[1]})
            game.reload_mods()
        end
    else
        return handler(table.unpack(arguments))
    end
end

return _actions
