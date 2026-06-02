---@diagnostic disable

local migration = {}

function migration.packed_factory(packed_subfactory)
    for _, product in pairs(packed_subfactory.Product.objects) do
        product.proto = {name=product.proto.name, category=product.proto.type, data_type="items", simplified=true}
        if product.required_amount.belt_proto then
            local belt_proto = product.required_amount.belt_proto
            product.required_amount.belt_proto = {name=belt_proto.name, data_type="belts", simplified=true}
        end
    end

    if packed_subfactory.matrix_free_items then
        for index, proto in pairs(packed_subfactory.matrix_free_items) do
            packed_subfactory.matrix_free_items[index] =
                {name=proto.name, category=proto.type, data_type="items", simplified=true}
        end
    end

    local function update_lines(floor)
        for _, packed_line in ipairs(floor.Line.objects) do
            if packed_line.subfloor then
                update_lines(packed_line.subfloor)
            else
                local recipe_proto = packed_line.recipe.proto
                packed_line.recipe.proto = {name=recipe_proto.name, data_type="recipes", simplified=true}
                local machine_proto = packed_line.machine.proto
                packed_line.machine.proto =
                    {name=machine_proto.name, category=machine_proto.category, data_type="machines", simplified=true}
                local module_set = packed_line.machine.module_set
                for _, module in pairs(module_set.modules.objects) do
                    module.proto =
                        {name=module.proto.name, category=module.proto.category, data_type="modules", simplified=true}
                end
                if packed_line.machine.fuel then
                    local fuel_proto = packed_line.machine.fuel.proto
                    packed_line.machine.fuel.proto =
                        {name=fuel_proto.name, category=fuel_proto.category, data_type="fuels", simplified=true}
                end
                if packed_line.beacon then
                    local beacon_proto = packed_line.beacon.proto
                    packed_line.beacon.proto = {name=beacon_proto.name, data_type="beacons", simplified=true}
                    local module_set = packed_line.beacon.module_set
                    for _, module in pairs(module_set.modules.objects) do
                        module.proto = {name=module.proto.name, category=module.proto.category,
                            data_type="modules", simplified=true}
                    end
                end
                if packed_line.priority_product_proto then
                    local priority_product_proto = packed_line.priority_product_proto
                    packed_line.priority_product_proto = {name=priority_product_proto.name,
                        category=priority_product_proto.type, data_type="items", simplified=true}
                end
                for _, product in pairs(packed_line.Product.objects) do
                    product.proto =
                        {name=product.proto.name, category=product.proto.type, data_type="items", simplified=true}
                end
            end
        end
    end
    update_lines(packed_subfactory.top_floor)
end

return migration
