---@diagnostic disable

local migration = {}

function migration.global()
    for tick, _ in pairs(storage.nth_tick_events) do script.on_nth_tick(tick, nil) end
    storage.nth_tick_events = {}  -- reset because some bad data ended up in there
end

return migration
