---@diagnostic disable

local migration = {}

local function check_quality(default)
    default.quality = default.quality or PROTOTYPE_MAPS.qualities["normal"]
    if default.modules then
        for _, module in pairs(default.modules) do
            check_quality(module)
        end
    end
end

function migration.player_table(player_table)
    if player_table.preferences.mb_defaults == nil then
        for _, machine in pairs(player_table.preferences.default_machines) do
            check_quality(machine)
        end
        check_quality(player_table.preferences.default_beacons)
        check_quality(player_table.preferences.default_pumps)
        check_quality(player_table.preferences.default_wagons[1])
        check_quality(player_table.preferences.default_wagons[2])
    end
end

return migration
