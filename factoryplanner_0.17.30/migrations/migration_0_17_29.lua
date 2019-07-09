migration_0_17_29 = {}

function migration_0_17_29.global()
end

function migration_0_17_29.player_table(player, player_table)
end

function migration_0_17_29.subfactory(player, subfactory)
    for _, floor in pairs(Subfactory.get_in_order(subfactory, "Floor")) do
        for _, line in pairs(Floor.get_in_order(floor, "Line")) do
            local beacon = line.beacon
            if beacon ~= nil then beacon.module.parent = beacon end
        end
    end
end