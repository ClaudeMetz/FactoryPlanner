local migration = {}

function migration.global()
    global.tutorial_subfactory = nil
end

function migration.player_table(player_table)
end

function migration.subfactory(subfactory)
    subfactory.linearly_dependant = false

    -- Not sure if this is necessary; TODO hacky
    for _, floor in pairs(Subfactory.get_all_floors(subfactory)) do
        for _, line in pairs(Floor.get_in_order(floor, "Line")) do
            if line.machine == nil then line.machine = {count=0, empty=true} end
        end
    end
end

function migration.packed_subfactory(packed_subfactory)
end

return migration