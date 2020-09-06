local migration = {}  -- same migration as 0.18.51, not sure why that one didn't take

function migration.global()
end

function migration.player_table(player_table)
end

function migration.subfactory(subfactory)
    if subfactory.icon and subfactory.icon.type == "virtual-signal" then
        subfactory.icon.type = "virtual"
    end
end

function migration.packed_subfactory(packed_subfactory)
    if packed_subfactory.icon and packed_subfactory.icon.type == "virtual-signal" then
        packed_subfactory.icon.type = "virtual"
    end
end

return migration