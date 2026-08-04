---@diagnostic disable

local migration = {}

-- Products defined by lanes are now stored as belts, with lanes being a display unit only
local function migrate_product(product)
    if product.belt_proto then product.belt_stack = 1 end

    if product.defined_by == "lanes" then
        product.defined_by = "belts"
        product.required_amount = product.required_amount * 0.5
    end
end

local function get_migration_map()
    local migration_map = {}

    for _, proto in pairs(prototypes.tile) do
        if proto.fluid then
            local old_key = "impostor-" .. proto.fluid.name .. "-" .. proto.name
            local new_key = "impostor-" .. proto.fluid.name .. "-tile"
            migration_map[old_key] = new_key
        end
    end

    return migration_map
end

local function migrate_recipe(recipe, migration_map)
    local name = migration_map[recipe.proto.name]
    if name then recipe.proto = {name=name, data_type="recipes", simplified=true} end
end

function migration.player_table(player_table)
    local migration_map = get_migration_map()

    local function iterate_floor(floor)
        for line_object in floor:iterator() do
            if line_object.class == "Floor" then
                iterate_floor(line_object)
            else
                migrate_recipe(line_object.recipe, migration_map)
            end
        end
    end

    for district in player_table.realm:iterator() do
        for factory in district:iterator() do
            for _, product in pairs(factory:as_list()) do
                migrate_product(product)
            end
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
                migrate_recipe(line_object.recipe, migration_map)
            end
        end
    end

    for _, product in pairs(packed_factory.products) do
        migrate_product(product)
    end
    iterate_floor(packed_factory.top_floor)
end

return migration
