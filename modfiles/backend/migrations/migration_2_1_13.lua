-- -@diagnostic disable

local migration = {}

---@return table<string, string>
local function get_migration_map()
    local recipe_map = {}
    for _, entity in pairs(prototypes.entity) do
        if entity.fixed_recipe then
            recipe_map[entity.fixed_recipe.name .. "-for-" .. entity.name] = entity.fixed_recipe.name
        end
    end
    return recipe_map
end

---@param player_table PlayerTable
function migration.player_table(player_table)
    local recipe_map = get_migration_map()

    ---@param floor Floor
    local function migrate_floor(floor)
        for line_object in floor:iterator() do
            if line_object.class == "Floor" then
                migrate_floor(line_object)
            else
                local new_recipe_name = recipe_map[line_object.recipe.proto.name]
                if new_recipe_name then
                    line_object.recipe.proto = {name=new_recipe_name, data_type="recipes", simplified=true}
                end
            end
        end
    end

    for district in player_table.realm:iterator() do
        for factory in district:iterator() do
            migrate_floor(factory.top_floor)
        end
    end
end

---@param packed_factory PackedFactory
function migration.packed_factory(packed_factory)
    local recipe_map = get_migration_map()

    ---@param floor PackedFloor
    local function migrate_floor(floor)
        for _, line_object in pairs(floor.lines) do
            if line_object.class == "Floor" then
                migrate_floor(line_object)
            else
                local new_recipe_name = recipe_map[line_object.recipe.proto.name]
                if new_recipe_name then
                    line_object.recipe.proto = {name=new_recipe_name, data_type="recipes", simplified=true}
                end
            end
        end
    end

    migrate_floor(packed_factory.top_floor)
end

return migration
