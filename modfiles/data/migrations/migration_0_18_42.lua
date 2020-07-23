local migration = {}

local function migrate_collection(collection, object_class)
    collection.class = collection.type
    collection.type = nil
    collection.object_class = object_class
end

function migration.player_table(player_table)
    migrate_collection(player_table.factory.Subfactory, "Subfactory")
    migrate_collection(player_table.archive.Subfactory, "Subfactory")
end

function migration.subfactory(subfactory)
    migrate_collection(subfactory.Product, "Item")
    migrate_collection(subfactory.Byproduct, "Item")
    migrate_collection(subfactory.Ingredient, "Item")
    migrate_collection(subfactory.Floor, "Floor")

    for _, floor in pairs(Subfactory.get_all_floors(subfactory)) do
        migrate_collection(floor.Line, "Line")

        for _, line in pairs(Floor.get_in_order(floor, "Line")) do
            if line.subfloor then
                line.recipe = nil
                line.percentage = nil
                line.production_ratio = nil
                line.uncapped_production_ratio = nil
            else
                migrate_collection(line.machine.Module, "Module")
            end

            migrate_collection(line.Product, "Item")
            migrate_collection(line.Byproduct, "Item")
            migrate_collection(line.Ingredient, "Item")
        end
    end
end

return migration