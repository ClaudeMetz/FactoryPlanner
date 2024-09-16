---@diagnostic disable

local migration = {}

function migration.global()
    for _, event_data in pairs(storage.nth_tick_events) do
        if event_data.handler_name == "adjust_interface_dimensions" then
            event_data.handler_name = "shrinkwrap_interface"
        end
    end
end

return migration
