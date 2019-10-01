migration_0_17_51 = {}

function migration_0_17_51.global()
end

function migration_0_17_51.player_table(player, player_table)
    player_table.archive = Factory.init()
end

function migration_0_17_51.subfactory(player, subfactory)
end