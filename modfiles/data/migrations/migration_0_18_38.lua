local migration = {}

function migration.player_table(player_table)
    player_table.factory.valid = nil
    player_table.archive.valid = nil
end

function migration.subfactory(subfactory)
    if not subfactory.valid then
        Factory.remove(subfactory.parent, subfactory)
        return "removed"
    end

    for _, item in pairs(Subfactory.get_in_order(subfactory, "Ingredient")) do item.type = nil end
    for _, item in pairs(Subfactory.get_in_order(subfactory, "Product")) do item.type = nil end
    for _, item in pairs(Subfactory.get_in_order(subfactory, "Byproduct")) do item.type = nil end

    for _, floor in pairs(Subfactory.get_all_floors(subfactory)) do
        for _, line in pairs(Floor.get_in_order(floor, "Line")) do
            line.machine.parent = line

            local module_count = 0
            for _, module in pairs(Line.get_in_order(line, "Module")) do
                module_count = module_count + module.amount
                module.category = nil
                module.parent = line.machine
            end

            line.machine.category = nil
            line.machine.Module = line.Module
            line.Module = nil

            line.machine.module_count = module_count
            Machine.summarize_effects(line.machine)

            if line.beacon then
                line.beacon.module.category = nil
            end

            if line.fuel then
                line.fuel.category = nil
                line.fuel.parent = line.machine
                line.machine.fuel = line.fuel
                line.fuel = nil
            end

            if line.subfloor then
                line.machine = nil
                line.beacon = nil
                line.priority_product_proto = nil
                line.production_ratio = nil
                line.uncapped_production_ratio = nil
            end
        end
    end
end

return migration