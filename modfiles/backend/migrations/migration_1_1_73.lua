---@diagnostic disable

local migration = {}

function migration.packed_factory(packed_subfactory)
    -- Most things just carry over as-is here, only the structure changes

    packed_subfactory.products = {}
    for _, product in pairs(packed_subfactory.Product.objects) do
        table.insert(packed_subfactory.products, {
            proto = product.proto,
            defined_by = product.required_amount.defined_by,
            required_amount = product.required_amount.amount,
            belt_proto = product.required_amount.belt_proto,
            class = "Product"
        })
    end

    local function convert_module_set(module_set)
        local modules = {}

        for _, module in pairs(module_set.modules.objects) do
            table.insert(modules, {
                proto = module.proto,
                amount = module.amount,
                class = "Module"
            })
        end

        return {
            modules = modules,
            class = "ModuleSet"
        }
    end

    local function convert_floor(packed_floor)
        local new_floor = {level = packed_floor.level, lines = {}, class = "Floor"}
        for _, line in pairs(packed_floor.Line.objects) do
            if line.subfloor then
                table.insert(new_floor.lines, convert_floor(line.subfloor))
            else
                table.insert(new_floor.lines, {
                    recipe_proto = line.recipe.proto,
                    production_type = line.recipe.production_type,
                    done = line.done,
                    active = line.active,
                    percentage = line.percentage,
                    machine = {
                        proto = line.machine.proto,
                        limit = line.machine.limit,
                        force_limit = line.machine.force_limit,
                        fuel = line.machine.fuel,
                        module_set = convert_module_set(line.machine.module_set),
                        class = "Machine"
                    },
                    beacon = line.beacon and {
                        proto = line.beacon.proto,
                        amount = line.beacon.amount,
                        total_amount = line.beacon.total_amount,
                        module_set = convert_module_set(line.beacon.module_set),
                        class = "Beacon"
                    },
                    priority_product = line.priority_product_proto,
                    comment = line.comment,
                    class = "Line"
                })
            end
        end
        return new_floor
    end
    packed_subfactory.top_floor = convert_floor(packed_subfactory.top_floor)
end

return migration
