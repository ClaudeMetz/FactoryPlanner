local migration = {}

function migration.player_table(player, player_table)
    player_table.archive = Factory.init()
end

return migration