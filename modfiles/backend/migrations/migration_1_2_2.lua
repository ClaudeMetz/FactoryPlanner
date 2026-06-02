---@diagnostic disable

local migration = {}

function migration.packed_factory(packed_factory)
    for _, product in pairs(packed_factory.products) do
        product.required_amount = product.required_amount / packed_factory.timescale
    end
end

return migration
