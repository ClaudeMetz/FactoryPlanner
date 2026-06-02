---@diagnostic disable

util = require("__factoryplanner__.util.util")

local suite = require("suite")

-- Runs data stage setup code for each test case

local error_count = 0
for name, case in pairs(suite) do
    local ok, error = pcall(case.setup)
    if not ok then
        error_count = error_count + 1
        log("setup_failed | " .. name .. " | " .. error)
    end
end

log(string.format("%d successful, %d failed", table_size(suite) - error_count, error_count))
log(error_count > 0 and "setup_failed" or "setup_successful")
