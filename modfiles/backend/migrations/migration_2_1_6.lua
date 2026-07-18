---@diagnostic disable

local migration = {}

function migration.player_table(player_table)
    for district in player_table.realm:iterator() do
        for factory in district:iterator() do
            factory.blueprints_inventory = game.create_inventory(12)
            for index, blueprint in pairs(factory.blueprints) do
                factory.blueprints_inventory[index].import_stack(blueprint)
            end
            factory.blueprints = nil
        end
    end
end

function migration.packed_factory(packed_factory)
    packed_factory.blueprint_strings = packed_factory.blueprints
    packed_factory.blueprints = nil
end

return migration
