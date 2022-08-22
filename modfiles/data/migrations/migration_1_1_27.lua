local migration = {}

function migration.global()
end

function migration.player_table(player_table)
end

function migration.subfactory(subfactory)
    for _, floor in pairs(Subfactory.get_all_floors(subfactory)) do
        for _, line in pairs(Floor.get_all(floor, "Line")) do
            local beacon = line.beacon
            if beacon and beacon.module then
                beacon.Module = Collection.init()
                beacon.module_count = 0
                beacon.module.parent = beacon
                Collection.add(beacon.Module, beacon.module)
                beacon.module_count = beacon.module_count + beacon.module.amount
                beacon.module = nil
            end
        end
    end
end

function migration.packed_subfactory(packed_subfactory)
    local function update_lines(floor)
        for _, packed_line in ipairs(floor.Line.objects) do
            if packed_line.subfloor then
                update_lines(packed_line.subfloor)
            elseif packed_line.beacon and packed_line.beacon.module then
                local beacon = packed_line.beacon
                local module = Module.unpack(beacon.module)
                local modules = Collection.init()
                Collection.add(modules, module)
                beacon.Module = Collection.pack(modules, Module)
                beacon.module_count = module.amount
            end
        end
    end
    update_lines(packed_subfactory.top_floor)
end

return migration
