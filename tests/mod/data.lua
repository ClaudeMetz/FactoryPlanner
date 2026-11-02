---@diagnostic disable

lib = require("__factoryplanner__.util.lib")

local configuration = require("configuration")

-- The first run tells the launcher which configurations to run next, without a discovery launch
for _, entry in ipairs(configuration.configurations) do log("FPTEST_CONFIGURATION " .. entry.name) end

-- Configuration setup is independent of the runtime case filter
local lines = {}
for index, setup in ipairs(configuration.setup) do
    local ok, error = xpcall(setup, debug.traceback)
    if not ok then
        table.insert(lines, "  ✗ setup " .. index .. configuration.suffix .. ": "
            .. tostring(error):gsub("\n", "\n    "))
    end
end

if #lines > 0 then
    log("FPTEST_REPORT\n" .. table.concat(lines, "\n") .. "\nFPTEST_REPORT_END")
    error("Prototype setup failed")
end
