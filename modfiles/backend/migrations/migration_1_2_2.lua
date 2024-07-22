---@diagnostic disable

local Realm = require("backend.data.Realm")

local migration = {}

function migration.player_table(player_table)
    player_table.realm = Realm.init()
    player_table.realm:insert(player_table.district)
    player_table.district = nil
end

return migration
