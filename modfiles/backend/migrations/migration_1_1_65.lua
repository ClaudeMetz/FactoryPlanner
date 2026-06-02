---@diagnostic disable

local migration = {}

function migration.packed_factory(packed_subfactory)
    packed_subfactory.blueprints = {}
end

return migration
