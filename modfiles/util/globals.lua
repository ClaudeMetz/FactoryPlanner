local _globals = {}

---@param player LuaPlayer
---@return PlayerTable
function _globals.player_table(player) return global.players[player.index] end

---@param player LuaPlayer
---@return SettingsTable
function _globals.settings(player) return global.players[player.index].settings end

---@param player LuaPlayer
---@return PreferencesTable
function _globals.preferences(player) return global.players[player.index].preferences end

---@param player LuaPlayer
---@return UIStateTable
function _globals.ui_state(player) return global.players[player.index].ui_state end

---@param player LuaPlayer
---@return Context
function _globals.context(player) return global.players[player.index].ui_state.context end

---@param player LuaPlayer
---@return UIStateFlags
function _globals.flags(player) return global.players[player.index].ui_state.flags end

---@param player LuaPlayer
---@return ModalData
function _globals.modal_globals(player) return global.players[player.index].ui_state.modal_globals end

---@param player LuaPlayer
---@return LuaGuiElement[]
function _globals.main_elements(player) return global.players[player.index].ui_state.main_elements end

---@param player LuaPlayer
---@return LuaGuiElement[]
function _globals.modal_elements(player) return global.players[player.index].ui_state.modal_globals.modal_elements end

return _globals
