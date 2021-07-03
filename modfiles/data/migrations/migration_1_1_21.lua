local migration = {}

function migration.global()
end

function migration.player_table(player_table)
    local Subfactory = player_table.archive.Subfactory
    Subfactory.count = table_size(Subfactory.datasets)
end

function migration.subfactory(subfactory)
end

function migration.packed_subfactory(packed_subfactory)
end

return migration
