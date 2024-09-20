---@diagnostic disable

local migration = {}

function migration.global()
    storage.tutorial_factory = nil
    storage.productivity_recipes = nil
end

function migration.player_table(player_table)
end

function migration.packed_factory(packed_factory)
end

return migration
