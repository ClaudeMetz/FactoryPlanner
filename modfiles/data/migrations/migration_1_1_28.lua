local migration = {}

function migration.global()
end

function migration.player_table(player_table)
end

function migration.subfactory(subfactory)
    if subfactory.matrix_free_items then
        subfactory.solver_type = "matrix"
    else
        subfactory.solver_type = "traditional"
    end
end

function migration.packed_subfactory(packed_subfactory)
    if packed_subfactory.matrix_free_items then
        packed_subfactory.solver_type = "matrix"
    else
        packed_subfactory.solver_type = "traditional"
    end
end

return migration
