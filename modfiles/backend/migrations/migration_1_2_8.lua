---@diagnostic disable

local migration = {}

function migration.global()
    storage.tutorial_factory = nil
    storage.productivity_recipes = nil
end

return migration
