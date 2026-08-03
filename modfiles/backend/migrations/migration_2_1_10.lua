local migration = {}

-- Offshore pumps fixed to a fluid used to generate a recipe each, so several of them pumping
-- the same fluid produced that many identical recipes. There is one per fluid now, named after
-- it rather than after any one pump. Both schemes are spelled out here rather than taken from
-- the generator, so that this keeps producing the same mapping however that changes later on.
---@return table<string, FPRecipePrototype>
local function get_migration_map()
    local migration_map = {}

    local entity_filter = {{filter="type", type="offshore-pump"}, {filter="hidden", invert=true, mode="and"}}
    for _, proto in pairs(prototypes.get_entity_filtered(entity_filter)) do
        local fluid_box = proto.fluidbox_prototypes[1]
        local fluid = fluid_box and fluid_box.filter

        if fluid ~= nil then
            migration_map["impostor-" .. fluid.name .. "-" .. proto.name] =
                prototyper.util.find("recipes", "impostor-" .. fluid.name .. "-pumped", nil)
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
            if line_object.class == "Floor" then
                iterate_floor(line_object)
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
            if line_object.class == "Floor" then
                iterate_floor(line_object)
            elseif line_object.class == "Line" then
                local proto = migration_map[line_object.recipe.proto.name]
                if proto then line_object.recipe.proto = prototyper.util.simplify_prototype(proto, nil) end
            end
        end
    end

    iterate_floor(packed_factory.top_floor)
end

return migration
