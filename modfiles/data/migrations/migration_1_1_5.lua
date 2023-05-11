local migration = {}

function migration.player_table(player_table)
    player_table.ui_state.view_states = player_table.ui_state.view_state
    player_table.preferences.toggle_column = false
end

function migration.subfactory(subfactory)
    for _, floor in pairs(Subfactory.get_all_floors(subfactory)) do
        if floor.level > 1 then floor.defining_line = floor.Line.datasets[1] end

        for _, line in pairs(Floor.get_in_order(floor, "Line")) do
            if not line.subfloor then
                line.machine.effects_tooltip = ""
                for _, module in pairs(line.machine.Module.datasets) do
                    module.effects_tooltip = ""
                end

                line.active = true
            end

            if line.beacon then
                line.beacon.effects_tooltip = ""
                line.beacon.module.effects_tooltip = ""  -- not strictly necessary yet
            end
        end
    end
end

function migration.packed_subfactory(packed_subfactory)
    local function update_lines(floor)
        for _, packed_line in ipairs(floor.Line.objects) do
            if packed_line.subfloor then
                update_lines(packed_line.subfloor)
            else
                packed_line.active = true
            end
        end
    end
    update_lines(packed_subfactory.top_floor)
end

return migration
