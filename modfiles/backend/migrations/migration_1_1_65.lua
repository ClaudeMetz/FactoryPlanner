---@diagnostic disable

local migration = {}

function migration.subfactory(subfactory)
    subfactory.blueprints = {}
end

function migration.packed_subfactory(packed_subfactory)
    packed_subfactory.blueprints = {}
end

return migration
