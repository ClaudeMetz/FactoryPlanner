---@diagnostic disable

local migration = {}

local function category_map()
    local category_map = {}
    for _, category in pairs(storage.prototypes.fuels) do
        category_map[string.gsub(category.name, "%|", "")] = category.name
    end
    return category_map
end

local function combined_category(categories)
    local list = {}
    for category, _ in pairs(categories) do
        table.insert(list, category)
    end

    table.sort(list)
    return table.concat(list, "|")
end

function migration.player_table(player_table)
    -- Migrate fuel prototypes
    for district in player_table.realm:iterator() do
        for factory in district:iterator() do
            local function iterate_floor(floor)
                for line in floor:iterator() do
                    if line.class == "Floor" then
                        iterate_floor(line)
                    else
                        local fuel = line.machine.fuel
                        if fuel then
                            local burner = line.machine.proto.burner
                            fuel.proto.combined_category = combined_category(burner.categories)
                        end
                    end
                end
            end
            iterate_floor(factory.top_floor)
        end
    end

    -- Migrate fuel defaults
    local category_map = category_map()
    for _, default in pairs(player_table.preferences.default_fuels) do
        default.proto.combined_category = category_map[default.proto.combined_category]
    end
end

function migration.packed_factory(packed_factory)
    local category_map = category_map()

    local function iterate_floor(packed_floor)
        for _, packed_line in pairs(packed_floor.lines) do
            if packed_line.class == "Floor" then
                iterate_floor(packed_line)
            else
                if packed_line.machine.fuel then
                    local fuel_proto = packed_line.machine.fuel.proto
                    -- combined_category saved as category when simplified
                    if category_map[fuel_proto.category] then
                        fuel_proto.category = category_map[fuel_proto.category]
                    end
                end
            end
        end
    end
    iterate_floor(packed_factory.top_floor)
end

return migration
