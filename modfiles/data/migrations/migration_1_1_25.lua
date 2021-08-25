local migration = {}

function migration.global()
    for _, event_data in pairs(global.nth_tick_events) do
        if event_data.handler_name == "delete_subfactory" then
            event_data.handler_name = "delete_subfactory_for_good"
        end
    end
end

function migration.player_table(player_table)
end

function migration.subfactory(subfactory)
end

function migration.packed_subfactory(packed_subfactory)
end

return migration
