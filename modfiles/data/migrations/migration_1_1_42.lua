local migration = {}

local function migrate_modules(object)
    object.module_count = nil
    if object.proto.simplified then object.proto = {module_limit = 0} end
    local module_set = ModuleSet.init(object)
    for _, module in pairs(object.Module.datasets) do
        ModuleSet.add(module_set, module.proto, module.amount)
    end
    object.Module = nil
    object.module_set = module_set
end

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

function migration.player_table(player_table)
    player_table.clipboard = nil
    player_table.preferences.tutorial_mode = true
end

function migration.subfactory(subfactory)
    if subfactory.icon then
        local icon_path = subfactory.icon.type .. "/" .. subfactory.icon.name
        subfactory.name = "[img=" .. icon_path .. "] " .. subfactory.name
        subfactory.icon = nil
    end

    for _, floor in pairs(Subfactory.get_all_floors(subfactory)) do
        for _, line in pairs(Floor.get_all(floor, "Line")) do
            line.effects_tooltip = ""
            if not line.subfloor then migrate_modules(line.machine) end
            if line.beacon then migrate_modules(line.beacon) end
        end
    end
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
