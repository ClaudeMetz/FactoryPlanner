---@diagnostic disable

local migration = {}

local function combined_category(categories)
    local list = {}
    for category, _ in pairs(categories) do
        table.insert(list, category)
    end

    table.sort(list)
    return table.concat(list, "|")
end

local function fuel_category_map(data_type)
    local category_map = {}
    for _, category in pairs(storage.prototypes.fuels) do
        category_map[string.gsub(category.name, "%|", "")] = category.name
    end
    return category_map
end


-- This uses prototype copys so there's no cross-talk
function migration.player_table(player_table)
    local fuels_map = fuel_category_map()

    for district in player_table.realm:iterator() do
        for factory in district:iterator() do
            local function iterate_floor(floor)
                for line in floor:iterator() do
                    if line.class == "Floor" then
                        iterate_floor(line)
                    else
                        -- Machine validation fixes this to a proper combined_category if applicable
                        local machine_copy = ftable.deep_copy(line.machine.proto)
                        machine_copy.combined_category = line.machine.proto.category
                        line.machine.proto = machine_copy

                        local fuel = line.machine.fuel
                        if fuel then
                            local burner = line.machine.proto.burner
                            local fuel_copy = ftable.deep_copy(fuel.proto)
                            fuel_copy.combined_category = fuels_map[fuel.proto.combined_category]
                            fuel.proto = fuel_copy
                        end
                    end
                end
            end
            iterate_floor(factory.top_floor)
        end
    end

    for _, default in pairs(player_table.preferences.default_machines) do
        -- This is appropriate as there were no defaults with combined categories before
        local copy = ftable.deep_copy(default.proto)
        copy.combined_category = default.proto.category
        default.proto = copy
    end

    for _, default in pairs(player_table.preferences.default_fuels) do
        local new_category_name = fuels_map[default.proto.combined_category]
        if new_category_name then
            local copy = ftable.deep_copy(default.proto)
            copy.combined_category = new_category_name
            default.proto = copy
        end
    end
end

function migration.packed_factory(packed_factory)
    local fuels_map = fuel_category_map()

    local function iterate_floor(packed_floor)
        for _, packed_line in pairs(packed_floor.lines) do
            if packed_line.class == "Floor" then
                iterate_floor(packed_line)
            else
                -- Machines don't need their category migrated, their validation fixes this

                if packed_line.machine.fuel then
                    local fuel_proto = packed_line.machine.fuel.proto
                    -- Note that combined_category is saved as category when simplified
                    if fuels_map[fuel_proto.category] then
                        fuel_proto.category = fuels_map[fuel_proto.category]
                    end
                end
            end
        end
    end
    iterate_floor(packed_factory.top_floor)
end

return migration
