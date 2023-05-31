local _messages = {}

---@alias MessageCategory "error" | "warning" | "hint"

---@class PlayerMessage
---@field category MessageCategory
---@field text LocalisedString
---@field lifetime integer

---@param player LuaPlayer
---@param category MessageCategory
---@param message LocalisedString
---@param lifetime integer
function _messages.raise(player, category, message, lifetime)
    local messages = util.globals.ui_state(player).messages
    table.insert(messages, {category=category, text=message, lifetime=lifetime})
end

---@param player LuaPlayer
function _messages.refresh(player)
    -- Only refresh messages if the user is actually looking at them
    if not main_dialog.is_in_focus(player) then return end

    local ui_state = util.globals.ui_state(player)
    local message_frame = ui_state.main_elements["messages_frame"]
    if not message_frame or not message_frame.valid then return end

    local messages = ui_state.messages
    message_frame.visible = (next(messages) ~= nil)
    message_frame.clear()

    for i=#messages, 1, -1 do
        local message = messages[i]  ---@type PlayerMessage
        local caption = {"", "[img=warning-white]  ", {"fp." .. message.category .. "_message", message.text}}
        message_frame.add{type="label", caption=caption, style="bold_label"}

        message.lifetime = message.lifetime - 1
        if message.lifetime == 0 then table.remove(messages, i) end
    end
end

return _messages
