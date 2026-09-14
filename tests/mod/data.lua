---@diagnostic disable

lib = require("__factoryplanner__.util.lib")

local configuration = require("configuration")

-- The first run tells the launcher which configurations to run next, without a discovery launch
for _, entry in ipairs(configuration.configurations) do log("FPTEST_CONFIGURATION " .. entry.name) end
log("FPTEST_SELECTED " .. configuration.name)

-- Runs data stage setup code for each test case that has any; only failures
-- are worth reporting here, success just means the checks get to run
local lines = {}
for _, name in ipairs(configuration.names) do
    local case = configuration.cases[name]
    if case.setup then
        local ok, error = xpcall(case.setup, debug.traceback)
        if not ok then
            table.insert(lines, "  ✗ setup " .. name .. configuration.suffix .. ": "
                .. tostring(error):gsub("\n", "\n    "))
        end
    end
end

if #lines > 0 then
    -- run.sh lifts everything between these markers out of the game log for display
    log("FPTEST_REPORT\n" .. table.concat(lines, "\n") .. "\nFPTEST_REPORT_END")
    error("FPTEST_SETUP_FAILED")
end
