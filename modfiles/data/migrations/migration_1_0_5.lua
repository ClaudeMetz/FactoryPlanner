local migration = {}

function migration.global()
end

function migration.player_table(player_table)
    if player_table.ui_state then
        player_table.ui_state.view_states = player_table.ui_state.view_state
    end
end

function migration.subfactory(subfactory)
end

function migration.packed_subfactory(packed_subfactory)
end

return migration