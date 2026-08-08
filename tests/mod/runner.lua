---@diagnostic disable

-- run.sh bakes the active world file into this mod copy as world.lua, and the
-- case filter as filter.lua; an empty filter matches every case
local world = require("world")
local filter = require("filter")

-- Called by the main mod's control.lua with the data class modules, and returns
-- the actual runner, which backend/init.lua calls at the end of on_init
return function(classes)
    local context = { classes = classes }

    return function()
        local names = {}
        for name in pairs(world.cases) do
            if name:find(filter) then table.insert(names, name) end
        end
        table.sort(names)

        -- Filtered runs are for digging into failures, so they get full tracebacks
        local handler = (filter ~= "") and function(error) return debug.traceback(error, 2) end
            or function(error) return error end

        local lines, error_count = {}, 0
        for _, name in ipairs(names) do
            local ok, error = xpcall(world.cases[name].check, handler, context)
            if ok then
                table.insert(lines, "  ✓ " .. name)
            else
                error_count = error_count + 1
                table.insert(lines, "  ✗ " .. name .. ": " .. error)
            end
        end

        if filter ~= "" and #names == 0 then
            error_count = 1
            table.insert(lines, "  ✗ no cases match filter '" .. filter .. "'")
        else
            table.insert(lines, string.format("  %d passed, %d failed%s", #names - error_count,
                error_count, (filter ~= "") and (" (filter: " .. filter .. ")") or ""))
        end

        -- run.sh lifts everything between these markers out of the game log for display
        log("FPTEST_REPORT\n" .. table.concat(lines, "\n") .. "\nFPTEST_REPORT_END")
        log(error_count > 0 and "tests_failed" or "tests_passed")
    end
end
