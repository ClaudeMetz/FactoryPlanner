---@diagnostic disable

local configuration = require("configuration")

local context = {
    classes = {
        District = require("__factoryplanner__.backend.data.District"),
        Factory = require("__factoryplanner__.backend.data.Factory"),
        TLProduct = require("__factoryplanner__.backend.data.TLProduct"),
        Floor = require("__factoryplanner__.backend.data.Floor"),
        Line = require("__factoryplanner__.backend.data.Line"),
        Machine = require("__factoryplanner__.backend.data.Machine"),
        Beacon = require("__factoryplanner__.backend.data.Beacon"),
        Module = require("__factoryplanner__.backend.data.Module"),
        Fuel = require("__factoryplanner__.backend.data.Fuel"),
    }
}

-- Called by backend/init.lua at the end of on_init
return function()
    local names = configuration.names

    local lines, error_count = {}, 0
    for _, name in ipairs(names) do
        local ok, error = xpcall(configuration.cases[name].check, debug.traceback, context)
        local label = name .. configuration.suffix
        if ok then
            table.insert(lines, "  ✓ " .. label)
        else
            error_count = error_count + 1
            table.insert(lines, "  ✗ " .. label .. ": " .. tostring(error):gsub("\n", "\n    "))
        end
    end

    if #names == 0 then
        table.insert(lines, "  ✗ no test cases selected" .. configuration.suffix)
    end

    -- run.sh lifts everything between these markers out of the game log for display
    log("FPTEST_REPORT\n" .. table.concat(lines, "\n") .. "\nFPTEST_REPORT_END")
    log(string.format("FPTEST_RESULT %d %d", #names - error_count, error_count))
end
