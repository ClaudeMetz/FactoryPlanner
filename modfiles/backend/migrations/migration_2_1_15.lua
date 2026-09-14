---@diagnostic disable

local migration = {}

function migration.player_table(player_table)
    local preferences = player_table.preferences.item_views
    if preferences and not preferences.selected then
        local selected = preferences.views[preferences.selected_index]
        preferences.selected = {primary=selected.name}
        preferences.selected_index = nil
    end

    local function migrate_floor(floor)
        for line in floor:iterator() do
            if line.class == "Floor" then
                migrate_floor(line)
            else
                if line.percentage == 0 then line.active = false end
                line.percentage = nil
            end
        end
    end

    for district in player_table.realm:iterator() do
        for factory in district:iterator() do
            migrate_floor(factory.top_floor)
            local inventory = factory.blueprints_inventory
            for index = 9, #inventory do
                if inventory[index].valid_for_read then
                    local empty_stack, empty_index = inventory.find_empty_stack()
                    if not empty_index or empty_index > 8 then break end
                    empty_stack.swap_stack(inventory[index])
                end
            end
            inventory.resize(8)
        end
    end
end

function migration.packed_factory(packed_factory)
    local function migrate_floor(floor)
        for _, line in pairs(floor.lines) do
            if line.class == "Floor" then
                migrate_floor(line)
            else
                if line.percentage == 0 then line.active = false end
                line.percentage = nil
            end
        end
    end
    migrate_floor(packed_factory.top_floor)

    local blueprints = packed_factory.blueprint_strings
    for index = 9, 12 do
        if blueprints[index] then
            for empty_index = 1, 8 do
                if not blueprints[empty_index] then
                    blueprints[empty_index] = blueprints[index]
                    break
                end
            end
            blueprints[index] = nil
        end
    end
end

return migration
