local migration = {}

function migration.global()
end

function migration.player_table(player_table)
end

function migration.subfactory(subfactory)
    for _, floor in pairs(Subfactory.get_all_floors(subfactory)) do
        for _, line in pairs(Floor.get_in_order(floor, "Line")) do
            if line.machine and line.machine.fuel and line.machine.fuel.proto == nil then
                Floor.remove(floor, line)  -- needs to be fully removed to fix the issue
            end
        end
    end
end

function migration.packed_subfactory(packed_subfactory)
end

return migration
