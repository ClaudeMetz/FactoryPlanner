local migration = {}

function migration.global()
end

function migration.player_table(player_table)
    if player_table.ui_state then
        player_table.ui_state.view_states = player_table.ui_state.view_state
    end
end

function migration.subfactory(subfactory)
    for _, floor in pairs(Subfactory.get_all_floors(subfactory)) do
        for _, line in pairs(Floor.get_in_order(floor, "Line")) do
            if not line.subfloor then
                line.machine.effects_tooltip = ""
                for _, module in pairs(Machine.get_in_order(line.machine, "Module")) do
                    module.effects_tooltip = ""
                end
            end

            if line.beacon then
                line.beacon.effects_tooltip = ""
                line.beacon.module.effects_tooltip = ""  -- not strictly necessary yet
            end
        end
    end
end

function migration.packed_subfactory(packed_subfactory)
end

return migration