---@diagnostic disable

local parts = require("solver.parts")
local framework = require("solver.framework")
-- Doing the following is really bad, but writing a proper interface kinda is as well
--      Also, it doesn't work without dumb changes to the main mod, so this whole test
--      setup is non-functional and untested until the requires are cleaned up
require("__factoryplanner__.control")  -- pull in all the crap
local Factory = require("__factoryplanner__.backend.data.Factory")
local District= require("__factoryplanner__.backend.data.District")

local tests = {
    {
        name = "example_subfactory",
        -- TODO: This setup data is currently completely ignored, the export_string below is what is used.
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
        export_string = "eNp9U9uOmzAQ/ZXKz2wEyRICH9CnVlpp+1atkDFD1pJva49XjSL+vWMgK5I0RUjg4zNz5szYZwZ/nPXYatsHQNacWccDsIZtN/mmZhnroYtH3nOH4Bd4S/CgZEfLfFOUmzytuUDrT05xY1bE8bIjIbDm95kJxQP9se8znyIN10nvFwT8VtC6UxGclwaJdqZ4YzHFMtpy3vZRoPyUeGo7a+TMWOBrgZcZnKPQJmeLkvTWPFGhCLQp6HNMhRCOoJNhjrzFk4MFCoQFqZ2Sg4SeNegjjKkvgzTQt10K5dpGk7Q8fETpCV6Qhhq0v37K4rDf7etdnj/XdVUX26p+3pVFWVVVeagOdb7fluNbxtC6dlDW+lT6V9smIGMKPkGxpqA/quLa+Q9CplKEdND+1/3a68x/4PbSeWsu9BmZkljSawauAmSMp/HAHEdh4AUY5EdCijzPmObiPZW3svRzge4HFZAyPw3RGy5uZhU0KJTmeONhSf/AxEfkKp2cWx1jvebqJtVMlo9yDZactUpqiRezQ0wjWc0qre9dCTtprcyId9BS3FWQ8v1TneTpukYF7XJlv1o5oa+QTuLMmO5QChBWa0gHkrHxbaT3L8IaU6g=",
        body = (function(subfactory)
            -- TODO: This is all very temporary proof-of-concept
            local EPSILON = 0.00001
            local expected = 0.16666666666667
            local ore_ingredient = subfactory.top_floor.ingredients.items[1]
            if ore_ingredient.proto.name == "iron-ore" and (math.abs(ore_ingredient.amount - expected) < EPSILON) then
                return "pass"

            else
                return "Expected " .. expected .. " got " .. ore_ingredient.amount
            end
            -- The framework needs to change but I don't know what too yet.
            --return framework.check_top_level_product(subfactory, "iron-plate", 10)
        end)
    }
}

local function runner(test)
    -- This approach doesn't work with the test data as-is because it is too old
    -- a format to be migrated.
    --local export_string = helpers.encode_string(parts.export_string(test.setup))

    -- Instead, for now we'll use an export string direct from the game/mod.
    local import_factory = util.porter.process_export_string(test.export_string)  ---@cast import_factory -nil
    local subfactory = import_factory.factories[1]
    -- A district is necessary for a location/pollutant_type
    subfactory.parent = District.init("Test District")
    if not subfactory.valid then error("Loaded subfactory setup is invalid") end
    solver.update(game.get_player(1), subfactory)  -- jank

    return test.body(subfactory)
end

for _, test in pairs(tests) do test.runner = runner end
return tests
