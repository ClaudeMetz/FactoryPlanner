---@diagnostic disable

local migration = {}

function migration.packed_subfactory(packed_subfactory)
    if packed_subfactory.icon and packed_subfactory.icon.type == "virtual-signal" then
        packed_subfactory.icon.type = "virtual"
    end
end

return migration
