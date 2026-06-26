---@diagnostic disable

local migration = {}

function migration.packed_factory(packed_factory)
    packed_factory.productivity_boni = {}
end

return migration
