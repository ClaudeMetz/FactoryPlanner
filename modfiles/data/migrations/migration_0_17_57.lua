migration_0_17_57 = {}

function migration_0_17_57.global()
end

function migration_0_17_57.player_table(player, player_table)
end

function migration_0_17_57.subfactory(player, subfactory)
    for _, floor in pairs(Subfactory.get_all_floors(subfactory)) do
        for _, line in pairs(Floor.get_in_order(floor, "Line")) do
            line.uncapped_production_ratio = 0
        end
    end
end