---@diagnostic disable

local migration = {}

function migration.player_table(player_table)
    player_table.preferences.default_pumps.quality = "normal"
    player_table.preferences.default_wagons[1].quality = "normal"
    player_table.preferences.default_wagons[2].quality = "normal"
end

return migration
