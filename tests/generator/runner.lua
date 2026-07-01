---@diagnostic disable

local suite = require("suite")

-- This gets called by the main mod so it runs in the same environment
return (function()
    local error_count = 0

    for name, case in pairs(suite) do
        local ok, error = pcall(case.check)
        if not ok then
            error_count = error_count + 1
            log("test_failed | " .. name .. " | " .. error)
        end
    end

    log(string.format("%d passed, %d failed", table_size(suite) - error_count, error_count))
    log(error_count > 0 and "tests_failed" or "tests_passed")
end)
