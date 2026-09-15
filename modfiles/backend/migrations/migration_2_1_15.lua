---@diagnostic disable

local migration = {}

local function migrate_beacon(line)
    local beacon = line.beacon
    if not beacon or beacon.total_amount == nil then return end

    local machine_amount = line.machine.amount
    if machine_amount and machine_amount > 0 then
        beacon.amount_per_machine = beacon.total_amount / machine_amount
    end
    beacon.total_amount = nil
end

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
                migrate_beacon(line)
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
                migrate_beacon(line)
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
