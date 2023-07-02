---@diagnostic disable

local migration = {}

function migration.player_table(player_table)
    player_table.factory.valid = nil
    player_table.archive.valid = nil
end

function migration.subfactory(subfactory)
    if not subfactory.valid then
        subfactory.parent.Subfactory.count = subfactory.parent.Subfactory.count - 1
        subfactory.parent.Subfactory.datasets[subfactory.id] = nil
        return
    end

    for _, item in pairs(subfactory.Ingredient.datasets) do item.type = nil end
    for _, item in pairs(subfactory.Product.datasets) do item.type = nil end
    for _, item in pairs(subfactory.Byproduct.datasets) do item.type = nil end

    for _, floor in pairs(subfactory.Floor.datasets) do
        for _, line in pairs(floor.Line.datasets) do
            line.machine.parent = line

            local module_count = 0
            for _, module in pairs(line.Module.datasets) do
                module_count = module_count + module.amount
                module.category = nil
                module.parent = line.machine
            end

            line.machine.category = nil
            line.machine.Module = line.Module
            line.Module = nil

            line.machine.module_count = module_count
            line.machine.total_effects = {consumption = 0, speed = 0, productivity = 0, pollution = 0}

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
