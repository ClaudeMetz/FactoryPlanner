---@diagnostic disable

local Realm = require("backend.data.Realm")
local SimpleItems = require("backend.data.SimpleItems")

local migration = {}

function migration.player_table(player_table)
    for factory in player_table.district:iterator() do
        for product in factory:iterator() do
            product.required_amount = product.required_amount / factory.timescale
        end
    end

    player_table.district.name = "Nauvis"
    player_table.district.location_proto = prototyper.util.find_prototype("locations", "nauvis")
    player_table.district.products = SimpleItems.init()
    player_table.district.byproducts = SimpleItems.init()
    player_table.district.ingredients = SimpleItems.init()

    player_table.realm = Realm.init()
    player_table.realm:remove(player_table.realm.first)  -- remove default district
    player_table.realm:insert(player_table.district)
    player_table.district = nil

    util.context.init(player_table)  -- resets context
end

function migration.packed_factory(packed_factory)
    for _, product in pairs(packed_factory.products) do
        product.required_amount = product.required_amount / packed_factory.timescale
    end
end

return migration
