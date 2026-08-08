---@diagnostic disable

-- Shared helpers for test cases

local helpers = {}

-- Collects failures instead of aborting on the first one, so a single run reports every mismatch
function helpers.collector()
    local failures = {}

    return {
        check = function(condition, message)
            if not condition then table.insert(failures, message) end
        end,
        done = function()
            if #failures > 0 then
                error(string.format("%d checks failed:\n    ", #failures)
                    .. table.concat(failures, "\n    "), 0)
            end
        end
    }
end

return helpers
