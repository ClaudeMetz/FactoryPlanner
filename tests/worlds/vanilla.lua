---@diagnostic disable

-- Runs alongside the regular base game, for cases that need its prototypes.
-- Each case consists of data stage setup and runtime checks: setup runs via the
-- test mod's data.lua, check runs in the main mod's environment.

return {
    cases = {
        testOffshorePumpWithNoFilter = require("cases.offshore-pump-no-filter")
    }
}
