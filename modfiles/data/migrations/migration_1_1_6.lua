local migration = {}

function migration.global()
    global.tutorial_subfactory = nil
end

function migration.player_table(player_table)
end

function migration.subfactory(subfactory)
    subfactory.linearly_dependant = false
end

function migration.packed_subfactory(packed_subfactory)
end

return migration