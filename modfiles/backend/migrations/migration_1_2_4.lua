---@diagnostic disable

local migration = {}

local function normal_quality_proto()
    return {name = "normal", data_type = "qualities", simplified = true}
end

function migration.player_table(player_table)
    local function update_modules(module_set)
        for module in module_set:iterator() do
            module.quality_proto = normal_quality_proto()
        end
    end

    for district in player_table.realm:iterator() do
        for factory in district:iterator() do
            local function iterate_floor(floor)
                for line in floor:iterator() do
                    if line.class == "Floor" then
                        iterate_floor(line)
                    else
                        line.machine.quality_proto = normal_quality_proto()
                        update_modules(line.machine.module_set)
                        if line.beacon then
                            line.beacon.quality_proto = normal_quality_proto()
                            update_modules(line.beacon.module_set)
                        end
                    end
                end
            end
            iterate_floor(factory.top_floor)
        end
    end
end

function migration.packed_factory(packed_factory)
    local function update_modules(module_set)
        for _, module in pairs(module_set.modules) do
            module.quality_proto = normal_quality_proto()
        end
    end

    local function iterate_floor(packed_floor)
        for _, packed_line in pairs(packed_floor.lines) do
            if packed_line.class == "Floor" then
                iterate_floor(packed_line)
            else
                packed_line.machine.quality_proto = normal_quality_proto()
                update_modules(packed_line.machine.module_set)
                if packed_line.beacon then
                    packed_line.beacon.quality_proto = normal_quality_proto()
                    update_modules(packed_line.beacon.module_set)
                end
            end
        end
    end
    iterate_floor(packed_factory.top_floor)
end

return migration
