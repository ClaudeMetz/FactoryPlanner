local migration = {}

function migration.global()
    for _, event_data in pairs(global.nth_tick_events) do
        if event_data.handler_name == "delete_subfactory" then
            event_data.handler_name = "delete_subfactory_for_good"
        end
    end
end

return migration
