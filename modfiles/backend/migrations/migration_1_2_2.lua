---@diagnostic disable

local Realm = require("backend.data.Realm")

local migration = {}

function migration.player_table(player_table)
    player_table.realm = Realm.init()
    player_table.realm:remove(player_table.realm.first)  -- remove default district
    player_table.realm:insert(player_table.district)
    player_table.district = nil

    util.context.init(player_table)  -- resets context
end

return migration
