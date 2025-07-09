local _globals = {}

---@param player LuaPlayer
---@return PlayerTable
function _globals.player_table(player) return storage.players[player.index] end

---@param player LuaPlayer
---@return PreferencesTable
function _globals.preferences(player) return storage.players[player.index].preferences end

---@param player LuaPlayer
---@return UIStateTable
function _globals.ui_state(player) return storage.players[player.index].ui_state end

---@param player LuaPlayer
---@return table?
function _globals.modal_data(player) return storage.players[player.index].ui_state.modal_data end

---@param player LuaPlayer
---@return table
function _globals.main_elements(player) return storage.players[player.index].ui_state.main_elements end

---@param player LuaPlayer
---@return table
function _globals.modal_elements(player) return storage.players[player.index].ui_state.modal_data.modal_elements end

return _globals
