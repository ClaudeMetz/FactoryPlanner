---@diagnostic disable

local migration = {}

---@return table<string, string>
local function get_migration_map()
    local recipe_map = {}
    for _, entity in pairs(prototypes.entity) do
        if entity.fixed_recipe then
            recipe_map[entity.fixed_recipe.name .. "-for-" .. entity.name] = entity.fixed_recipe.name
        end
    end

    local launch_items = {}
    for _, item in pairs(prototypes.item) do
        if #item.rocket_launch_products > 0 then table.insert(launch_items, item.name) end
    end

    local silo_filter = {{filter="type", type="rocket-silo"}, {filter="hidden", invert=true, mode="and"}}
    for _, silo in pairs(prototypes.get_entity_filtered(silo_filter)) do
        -- Reconstruct the parts recipes the generator considered for this silo
        local parts_recipes = {}
        if silo.fixed_recipe then
            table.insert(parts_recipes, silo.fixed_recipe)
        else
            for _, recipe in pairs(prototypes.recipe) do
                for _, category in pairs(recipe.categories) do
                    if silo.crafting_categories[category] then
                        table.insert(parts_recipes, recipe)
                        break
                    end
                end
            end
        end

        for _, recipe in pairs(parts_recipes) do
            if recipe.main_product then
                local suffix = "-from-" .. silo.rocket_parts_required .. "-" .. recipe.main_product.name

                -- Old names carried a disambiguator when the silo had several parts recipes
                for _, old_suffix in pairs({"", "-using-" .. recipe.name}) do
                    for _, item_name in pairs(launch_items) do
                        recipe_map["impostor-launch-" .. item_name .. "-from-" .. silo.name .. old_suffix]
                            = "impostor-launch-" .. item_name .. suffix
                    end
                    recipe_map["impostor-" .. silo.name .. "-rocket" .. old_suffix]
                        = "impostor-rocket" .. suffix
                end
            end
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
