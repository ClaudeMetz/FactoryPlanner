migration_0_18_27 = {}

function migration_0_18_27.global()
end

function migration_0_18_27.player_table(player, player_table)
    player_table.preferences.preferred_belt = nil
    player_table.preferences.preferred_beacon = nil
    player_table.preferences.preferred_fuel = nil
    player_table.preferences.default_machines = nil
end

function migration_0_18_27.subfactory(player, subfactory)
    for _, floor in pairs(Subfactory.get_in_order(subfactory, "Floor")) do
        for _, line in pairs(Floor.get_in_order(floor, "Line")) do
            local fuel = Line.get(line, "Fuel", 1)
            if fuel ~= nil and fuel.proto ~= nil then
                fuel.category = fuel.proto.category
            end
        end
    end
end