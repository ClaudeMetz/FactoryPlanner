local migration = {}

function migration.global()
end

function migration.player_table(player_table)
end

function migration.subfactory(subfactory)
    if subfactory.icon then
        local icon_path = subfactory.icon.type .. "/" .. subfactory.icon.name
        subfactory.name = "[img=" .. icon_path .. "] " .. subfactory.name
        subfactory.icon = nil
    end
end

function migration.packed_subfactory(packed_subfactory)
    if packed_subfactory.icon then
        local icon_path = packed_subfactory.icon.type .. "/" .. packed_subfactory.icon.name
        packed_subfactory.name = "[img=" .. icon_path .. "] " .. packed_subfactory.name
        packed_subfactory.icon = nil
    end
end

return migration
