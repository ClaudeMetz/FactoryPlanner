---@diagnostic disable

lib = require("__factoryplanner__.util.lib")

-- Without the base mod, the engine-required prototypes have to come from somewhere
if not mods["base"] then require("scaffold") end

-- run.sh bakes the active world file into this mod copy as world.lua
local world = require("world")

-- Runs data stage setup code for each test case that has any

local setup_count, error_count = 0, 0
for name, case in pairs(world.cases) do
    if case.setup then
        setup_count = setup_count + 1
        local ok, error = pcall(case.setup)
        if not ok then
            error_count = error_count + 1
            log("setup_failed | " .. name .. " | " .. error)
        end
    end
end

log(string.format("%d successful, %d failed", setup_count - error_count, error_count))
log(error_count > 0 and "setup_failed" or "setup_successful")
