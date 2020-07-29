local migration = {}

function migration.global()
end

function migration.player_table(player_table)
    player_table.ui_state.current_activity = nil
end

function migration.subfactory(subfactory)
    for _, floor in pairs(Subfactory.get_all_floors(subfactory)) do
        for _, line in pairs(Floor.get_in_order(floor, "Line")) do
            if line.machine and line.machine.fuel then line.machine.fuel.satisfied_amount = 0 end

            line.Product = Collection.init()
            line.Byproduct = Collection.init()
            line.Ingredient = Collection.init()
        end
    end
end

function migration.packed_subfactory(packed_subfactory)
end

return migration