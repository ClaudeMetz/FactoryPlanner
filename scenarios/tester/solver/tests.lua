---@diagnostic disable

local parts = require("solver.parts")
local framework = require("solver.framework")
-- TODO doing the following is really bad, but writing a proper interface kinda is as well
--      Also, it doesn't work without dumb changes to the main mod, so this whole test
--      setup is non-functional and untested until the requires are cleaned up
require("__factoryplanner__.control")  -- pull in all the crap

local tests = {
    {
        name = "example_subfactory",
        setup = parts.subfactory{
            products = {
                parts.top_level_product("item", "iron-plate", 10)
            },
            lines = {
                parts.line{
                    recipe = parts.recipe("smelting", "iron-plate"),
                    --percentage = 100,
                    machine = parts.machine("smelting", "stone-furnace", {
                        fuel = parts.fuel("chemical", "coal"),
                        module_set = parts.module_set({})
                    })
                }
            }
        },
        body = (function(subfactory)
            return framework.check_top_level_product(subfactory, "iron-plate", 10)
        end)
    }
}


local function runner(test)
    local export_string = game.encode_string(parts.export_string(test.setup))
    local import_factory = data_util.porter.get_subfactories(export_string)  ---@cast import_factory -nil
    local subfactory = Factory.get(import_factory, "Subfactory", 1)
    if not subfactory.valid then error("Loaded subfactory setup is invalid") end
    solver.update(game.get_player(1), subfactory)  -- jank

    return test.body(subfactory)
end

for _, test in pairs(tests) do test.runner = runner end
return tests
