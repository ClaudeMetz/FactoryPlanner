local migration = {}

function migration.global()
end

function migration.player_table(player_table)
    player_table.ui_state.current_activity = nil
end

function migration.subfactory(subfactory)
end

function migration.packed_subfactory(packed_subfactory)
end

return migration