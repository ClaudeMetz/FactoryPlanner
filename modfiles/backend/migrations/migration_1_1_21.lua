---@diagnostic disable

local migration = {}

function migration.player_table(player_table)
    local Subfactory = player_table.archive.Subfactory
    Subfactory.count = table_size(Subfactory.datasets)
end

return migration
