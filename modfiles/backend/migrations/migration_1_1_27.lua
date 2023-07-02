---@diagnostic disable

local migration = {}

-- Hard to fix migration

function migration.subfactory(subfactory)
    for _, floor in pairs(subfactory.Floor.datasets) do
        for _, line in pairs(floor.Line.datasets) do
            local beacon = line.beacon
            if beacon and beacon.module then
                beacon.Module = {datasets={}, index=0, count=0, class="Collection"}
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
                local modules = {datasets={}, index=0, count=0, class="Collection"}
                Collection.add(modules, module)
                beacon.Module = Collection.pack(modules, Module)
                beacon.module_count = module.amount
            end
        end
    end
    update_lines(packed_subfactory.top_floor)
end

return migration
