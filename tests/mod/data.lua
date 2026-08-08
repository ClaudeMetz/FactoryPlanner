---@diagnostic disable

lib = require("__factoryplanner__.util.lib")

-- Without the base mod, the engine-required prototypes have to come from somewhere
if not mods["base"] then require("scaffold") end

-- run.sh bakes the active world file into this mod copy as world.lua, and the
-- case filter as filter.lua; an empty filter matches every case
local world = require("world")
local filter = require("filter")

-- Runs data stage setup code for each test case that has any; only failures
-- are worth reporting here, success just means the checks get to run
local lines = {}
for name, case in pairs(world.cases) do
    if case.setup and name:find(filter) then
        local ok, error = pcall(case.setup)
        if not ok then
            table.insert(lines, "  ✗ setup " .. name .. ": " .. error)
        end
    end
end

if #lines > 0 then
    -- run.sh lifts everything between these markers out of the game log for display
    log("FPTEST_REPORT\n" .. table.concat(lines, "\n") .. "\nFPTEST_REPORT_END")
    log("setup_failed")
end
