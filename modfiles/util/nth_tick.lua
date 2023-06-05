local _nth_tick = {}

---@class NthTickEvent: { handler_name: string, metadata: table }

---@param tick Tick
local function register_nth_tick_handler(tick)
    script.on_nth_tick(tick, function(nth_tick_data)
        local event_data = global.nth_tick_events[nth_tick_data.nth_tick]
        local handler = GLOBAL_HANDLERS[event_data.handler_name]  ---@type function
        handler(event_data.metadata)
        util.nth_tick.cancel(tick)
    end)
end


---@param desired_tick Tick
---@param handler_name string
---@param metadata table
---@return Tick
function _nth_tick.register(desired_tick, handler_name, metadata)
    local actual_tick = desired_tick
    -- Search until the next free nth_tick is found
    while (global.nth_tick_events[actual_tick] ~= nil) do
        actual_tick = actual_tick + 1
    end

    global.nth_tick_events[actual_tick] = {handler_name=handler_name, metadata=metadata}
    register_nth_tick_handler(actual_tick)

    return actual_tick  -- let caller know which tick they actually got
end

---@param tick Tick
function _nth_tick.cancel(tick)
    script.on_nth_tick(tick, nil)
    global.nth_tick_events[tick] = nil
end

function _nth_tick.register_all()
    if not global.nth_tick_events then return end
    for tick, _ in pairs(global.nth_tick_events) do
        register_nth_tick_handler(tick)
    end
end

return _nth_tick
