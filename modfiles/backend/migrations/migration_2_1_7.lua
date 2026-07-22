local migration = {}

---@return table<string, FPRecipePrototype>
local function get_migration_map()
    local migration_map = {}

    for _, proto in pairs(prototypes.tile) do
        if proto.fluid then
            local old_key = "impostor-" .. proto.fluid.name .. "-" .. proto.name
            local new_key = "impostor-" .. proto.fluid.name .. "-tile"
            migration_map[old_key] = prototyper.util.find("recipes", new_key, nil)
        end
    end

    return migration_map
end

---@param player_table PlayerTable
function migration.player_table(player_table)
    local migration_map = get_migration_map()

    ---@param floor Floor
    local function iterate_floor(floor)
        for line_object in floor:iterator() do
            if line_object.class == "Floor" then iterate_floor(line_object)
            elseif line_object.class == "Line" then
                local proto = migration_map[line_object.recipe.proto.name]
                if proto then line_object.recipe.proto = proto end
            end
        end
    end

    for district in player_table.realm:iterator() do
        for factory in district:iterator() do
            iterate_floor(factory.top_floor)
        end
    end
end

---@param packed_factory PackedFactory
function migration.packed_factory(packed_factory)
    local migration_map = get_migration_map()

    ---@param floor PackedFloor
    local function iterate_floor(floor)
        for _, line_object in pairs(floor.lines) do
            if line_object.class == "Floor" then iterate_floor(line_object)
            elseif line_object.class == "Line" then
                local proto = migration_map[line_object.recipe.proto.name]
                if proto then line_object.recipe.proto = prototyper.util.simplify_prototype(proto, nil) end
            end
        end
    end

    iterate_floor(packed_factory.top_floor)
end

return migration
