---@diagnostic disable

local migration = {}

function migration.player_table(player_table)
    player_table.context.history = {
        stack = {},
        position = 0
    }
end

return migration
