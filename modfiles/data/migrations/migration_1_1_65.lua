local migration = {}

function migration.global()
end

function migration.player_table(player_table)
end

function migration.subfactory(subfactory)
    subfactory.blueprints = {}
end

function migration.packed_subfactory(packed_subfactory)
    packed_subfactory.blueprints = {}
end

return migration
