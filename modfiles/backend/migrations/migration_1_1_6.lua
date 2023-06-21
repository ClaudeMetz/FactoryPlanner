---@diagnostic disable

local migration = {}

function migration.global()
    global.tutorial_subfactory = nil
end

function migration.subfactory(subfactory)
    subfactory.linearly_dependant = false
end

return migration
