---@diagnostic disable

local migration = {}

function migration.player_table(player_table)
    for _, factory in pairs({"factory", "archive"}) do
        for _, subfactory in pairs(player_table[factory].Subfactory.datasets) do
            subfactory.blueprints = {}
        end
    end
end

function migration.packed_factory(packed_subfactory)
    packed_subfactory.blueprints = {}
end

return migration
