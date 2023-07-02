---@diagnostic disable

local migration = {}

function migration.global()
    global.tutorial_subfactory_validity = nil

    local data_types = {"machines", "recipes", "items", "fuels", "belts", "wagons", "modules", "beacons"}
    for _, data_type in pairs(data_types) do global["all_" .. data_type] = nil end
end

function migration.player_table(player_table)
    local default_prototypes = player_table.preferences.default_prototypes
    default_prototypes["machines"] = default_prototypes["machines"].prototypes
    default_prototypes["fuels"] = default_prototypes["fuels"].prototypes
    default_prototypes["belts"] = default_prototypes["belts"].prototype
    default_prototypes["wagons"] = default_prototypes["wagons"].prototypes
    default_prototypes["beacons"] = default_prototypes["beacons"].prototype
end

function migration.subfactory(subfactory)
    for _, product in pairs(subfactory.Product.datasets) do
        if product.proto.simplified then
            product.proto = {name=product.proto.name, category=product.proto.type, data_type="items", simplified=true}
        else
            product.proto.data_type = "items"
        end
        local belt_proto = product.required_amount.belt_proto
        if belt_proto then
            if belt_proto.simplified then
                product.required_amount.belt_proto = {name=belt_proto.name, data_type="belts", simplified=true}
            else
                product.required_amount.belt_proto.data_type = "belts"
            end
        end
    end

    for index, _ in pairs(subfactory.matrix_free_items or {}) do
        local item_proto = subfactory.matrix_free_items[index]
        if item_proto.simplified then
            subfactory.matrix_free_items[index] =
                {name=item_proto.name, category=item_proto.type, data_type="items", simplified=true}
        else
            item_proto.data_type = "items"
        end
    end

    for _, floor in pairs(subfactory.Floor.datasets) do
        for _, line in pairs(floor.Line.datasets) do
            if line.subfloor then goto skip end
            local recipe_proto = line.recipe.proto
            if recipe_proto.simplified then
                line.recipe.proto = {name=recipe_proto.name, data_type="recipes", simplified=true}
            else
                recipe_proto.data_type = "recipes"
            end
            local machine_proto = line.machine.proto
            if machine_proto.simplified then
                line.machine.proto =
                    {name=machine_proto.name, category=machine_proto.category, data_type="machines", simplified=true}
            else
                machine_proto.data_type = "machines"
            end
            local machine_module_set = line.machine.module_set
            for _, module in pairs(machine_module_set.modules.datasets) do
                if module.proto.simplified then
                    module.proto = {name=module.proto.name, category=module.proto.category,
                        data_type="modules", simplified=true}
                else
                    module.proto.data_type = "modules"
                end
            end
            if line.machine.fuel then
                local fuel_proto = line.machine.fuel.proto
                if fuel_proto.simplified then
                    line.machine.fuel.proto =
                        {name=fuel_proto.name, category=fuel_proto.category, data_type="fuels", simplified=true}
                else
                    fuel_proto.data_type = "fuels"
                end
            end
            if line.beacon then
                local beacon_proto = line.beacon.proto
                if beacon_proto.simplified then
                    line.beacon.proto = {name=beacon_proto.name, data_type="beacons", simplified=true}
                else
                    beacon_proto.data_type = "beacons"
                end
                local beacon_module_set = line.beacon.module_set
                for _, module in pairs(beacon_module_set.modules.datasets) do
                    if module.proto.simplified then
                        module.proto = {name=module.proto.name, category=module.proto.category,
                            data_type="modules", simplified=true}
                    else
                        module.proto.data_type = "modules"
                    end
                end
            end
            if line.priority_product_proto then
                local priority_product_proto = line.priority_product_proto
                if priority_product_proto.simplified then
                    line.priority_product_proto = {name=priority_product_proto.name,
                        category=priority_product_proto.type, data_type="items", simplified=true}
                else
                    priority_product_proto.data_type = "items"
                end
            end
            for _, product in pairs(line.Product.datasets) do
                if product.proto.simplified then
                    product.proto =
                        {name=product.proto.name, category=product.proto.type, data_type="items", simplified=true}
                else
                    product.proto.data_type = "items"
                end
            end
            ::skip::
        end
    end
end

function migration.packed_subfactory(packed_subfactory)
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
