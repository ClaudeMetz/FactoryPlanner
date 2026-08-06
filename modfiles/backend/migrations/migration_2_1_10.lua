---@diagnostic disable

local migration = {}

-- Sorry about this piece of crap, but the changes really do make a difference to users

local function get_migration_map()
    local migration_map = {}

    local boiler_filter = {{filter="type", type="boiler"}, {filter="hidden", invert=true, mode="and"}}
    for _, proto in pairs(prototypes.get_entity_filtered(boiler_filter)) do
        local target = proto.target_temperature
        if target == 0 then goto next_boiler end

        local input, output
        for _, fluid_box in pairs(proto.fluidbox_prototypes) do
            if fluid_box.production_type == "input-output" or fluid_box.production_type == "input" then
                input = fluid_box
            elseif fluid_box.production_type == "output" then
                output = fluid_box
            end
        end
        if input == nil then goto next_boiler end

        local category = "boiler-target-" .. target
        if output ~= nil and output.filter ~= nil then
            category = category .. "-output-" .. output.filter.name
        end
        if input.filter ~= nil then
            category = category .. "-filter-" .. input.filter.name
        end

        for _, fluid in pairs((input.filter) and {input.filter} or prototypes.fluid) do
            local output_fluid = (output ~= nil and output.filter) or fluid
            local new_name = table.concat({"impostor-boil", fluid.name,
                math.max(input.minimum_temperature or -math.huge, fluid.default_temperature),
                math.min(input.maximum_temperature or math.huge, fluid.max_temperature, target),
                output_fluid.name, target}, "-")

            migration_map["impostor-" .. category .. "-fluid-" .. fluid.name] = new_name
        end

        ::next_boiler::
    end

    local pump_filter = {{filter="type", type="offshore-pump"}, {filter="hidden", invert=true, mode="and"}}
    for _, proto in pairs(prototypes.get_entity_filtered(pump_filter)) do
        local fluid_box = proto.fluidbox_prototypes[1]
        local fluid = fluid_box and fluid_box.filter

        if fluid ~= nil then
            migration_map["impostor-" .. fluid.name .. "-" .. proto.name] =
                "impostor-" .. fluid.name .. "-pumped"
        end
    end

    return migration_map
end

local function get_temperature_map()
    local temperature_map = {}

    for base_name, protos in pairs(TEMPERATURE_MAP) do
        for _, proto in pairs(protos) do
            temperature_map[base_name .. "-" .. proto.temperature] =
                base_name .. "|" .. proto.temperature
        end
    end

    return temperature_map
end

local function migrated_item_name(proto, temperature_map)
    if proto.simplified then return temperature_map[proto.name] end
    if proto.type ~= "fluid" or proto.temperature == nil then return nil end
    return proto.base_name .. "|" .. proto.temperature
end

local function migrated_item_proto(proto, temperature_map)
    local fluid_name = migrated_item_name(proto, temperature_map)
    if fluid_name == nil then return proto end
    return {name = fluid_name, category = "fluid", data_type = "items", simplified = true}
end

local function migrate_recipe(recipe, migration_map, temperature_map)
    local name = migration_map[recipe.proto.name]
    if name then recipe.proto = {name=name, data_type="recipes", simplified=true} end

    recipe.priority_item = recipe.priority_product
    recipe.priority_product = nil

    if recipe.priority_item then
        recipe.priority_item = migrated_item_proto(recipe.priority_item, temperature_map)
    end
end


function migration.player_table(player_table)
    local migration_map = get_migration_map()
    local temperature_map = get_temperature_map()

    local function iterate_floor(floor)
        for line_object in floor:iterator() do
            if line_object.class == "Floor" then
                iterate_floor(line_object)
            else
                migrate_recipe(line_object.recipe, migration_map, temperature_map)
            end
        end
    end

    for district in player_table.realm:iterator() do
        for factory in district:iterator() do
            iterate_floor(factory.top_floor)

            for _, product in pairs(factory:as_list()) do
                product.proto = migrated_item_proto(product.proto, temperature_map)
            end

            for index, item_proto in pairs(factory.matrix_free_items) do
                factory.matrix_free_items[index] = migrated_item_proto(item_proto, temperature_map)
            end
        end
    end
end

function migration.packed_factory(packed_factory)
    local migration_map = get_migration_map()
    local temperature_map = get_temperature_map()

    local function iterate_floor(floor)
        for _, line_object in pairs(floor.lines) do
            if line_object.class == "Floor" then
                iterate_floor(line_object)
            else
                migrate_recipe(line_object.recipe, migration_map, temperature_map)
            end
        end
    end

    iterate_floor(packed_factory.top_floor)

    for _, product in pairs(packed_factory.products) do
        product.proto = migrated_item_proto(product.proto, temperature_map)
    end

    for index, item_proto in pairs(packed_factory.matrix_free_items) do
        packed_factory.matrix_free_items[index] = migrated_item_proto(item_proto, temperature_map)
    end
end

return migration
