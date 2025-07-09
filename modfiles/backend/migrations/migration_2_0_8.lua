---@diagnostic disable

local DistrictItemSet = require("backend.data.DistrictItemSet")

local migration = {}

function migration.player_table(player_table)
    for district in player_table.realm:iterator() do
        district.product_set = nil
        district.ingredient_set = nil
        district.item_set = DistrictItemSet.init()
    end
end

return migration
