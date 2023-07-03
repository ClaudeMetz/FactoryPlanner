---@diagnostic disable

local migration = {}

local function migrate_packed_modules(packed_object)
    local module_set = {
        modules = packed_object.Module,
        module_count = packed_object.module_count,
        empty_slots = 0,  -- updated later
        class = "ModuleSet"
    }
    packed_object.Module = nil
    packed_object.module_set = module_set
end

function migration.packed_subfactory(packed_subfactory)
    if packed_subfactory.icon then
        local icon_path = packed_subfactory.icon.type .. "/" .. packed_subfactory.icon.name
        packed_subfactory.name = "[img=" .. icon_path .. "] " .. packed_subfactory.name
        packed_subfactory.icon = nil
    end

    local function update_lines(floor)
        for _, packed_line in ipairs(floor.Line.objects) do
            if packed_line.subfloor then
                update_lines(packed_line.subfloor)
            else
                migrate_packed_modules(packed_line.machine)
                if packed_line.beacon then migrate_packed_modules(packed_line.beacon) end
            end
        end
    end
    update_lines(packed_subfactory.top_floor)
end

return migration
