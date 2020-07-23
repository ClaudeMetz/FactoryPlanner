local migration = {}

function migration.player_table(player_table)
    player_table.preferences.default_prototypes = {
        belts = {structure_type="simple", prototype=player_table.preferences.preferred_belt},
        beacons = {structure_type="simple", prototype=player_table.preferences.preferred_beacon},
        machines = {structure_type="complex", prototypes=player_table.preferences.default_machines.categories}
    }
    player_table.preferences.preferred_belt = nil
    player_table.preferences.preferred_beacon = nil
    player_table.preferences.preferred_fuel = nil
    player_table.preferences.default_machines = nil
end

function migration.subfactory(subfactory)
    for _, floor in pairs(Subfactory.get_all_floors(subfactory)) do
        for _, line in pairs(Floor.get_in_order(floor, "Line")) do
            local fuel = Line.get_by_gui_position(line, "Fuel", 1)
            if fuel ~= nil and fuel.valid and fuel.proto ~= nil then
                fuel.category = fuel.proto.fuel_category
                line.fuel = fuel
            end
            line.Fuel = nil
        end
    end
end

return migration