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

            migration_map["impostor-" .. category .. "-fluid-" .. fluid.name] =
                prototyper.util.find("recipes", new_name, nil)
        end

        ::next_boiler::
    end

    local pump_filter = {{filter="type", type="offshore-pump"}, {filter="hidden", invert=true, mode="and"}}
    for _, proto in pairs(prototypes.get_entity_filtered(pump_filter)) do
        local fluid_box = proto.fluidbox_prototypes[1]
        local fluid = fluid_box and fluid_box.filter

        if fluid ~= nil then
            migration_map["impostor-" .. fluid.name .. "-" .. proto.name] =
                prototyper.util.find("recipes", "impostor-" .. fluid.name .. "-pumped", nil)
        end
    end

    return migration_map
end

function migration.player_table(player_table)
    local migration_map = get_migration_map()

    local function iterate_floor(floor)
        for line_object in floor:iterator() do
            if line_object.class == "Floor" then
                iterate_floor(line_object)
            else
                local recipe = line_object.recipe
                local proto = migration_map[recipe.proto.name]
                if proto then recipe.proto = proto end

                recipe.priority_item = recipe.priority_product
                recipe.priority_product = nil
            end
        end
    end

    for district in player_table.realm:iterator() do
        for factory in district:iterator() do
            iterate_floor(factory.top_floor)
        end
    end
end

function migration.packed_factory(packed_factory)
    local migration_map = get_migration_map()

    local function iterate_floor(floor)
        for _, line_object in pairs(floor.lines) do
            if line_object.class == "Floor" then
                iterate_floor(line_object)
            else
                local recipe = line_object.recipe
                local proto = migration_map[recipe.proto.name]
                if proto then recipe.proto = prototyper.util.simplify_prototype(proto, nil) end

                recipe.priority_item = recipe.priority_product
                recipe.priority_product = nil
            end
        end
    end

    iterate_floor(packed_factory.top_floor)
end

return migration
