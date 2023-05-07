-- ** LLOG **
llog = require("__factoryplanner__/llog")
LLOG_EXCLUDES = {}

-- ** AUX **
local function initial_setup()
    llog("Factory Planner test suite initiated")
    game.autosave_enabled = false
    game.speed = 100
    global.test_index = 1
    global.test_results = {}
end

local function teardown()
    game.set_game_state{game_finished=true}

    local output = "Test results\n"
    for name, result in pairs(global.test_results) do
        output = output .. "\nTest '" .. name .. "': " .. result
    end
    game.write_file("test_results.txt", output)
end

-- ** TESTS **
TESTS = {
    {
        name = "test1",
        runner = (function()
            game.print("success")
            return "Success"
        end)
    },
    {
        name = "test2",
        runner = (function()
            game.print("failure")
            return "Failed because X"
        end)
    }
}

script.on_event(defines.events.on_game_created_from_scenario, initial_setup)

script.on_event(defines.events.on_tick, function()
    local test = TESTS[global.test_index]
    if test == nil then teardown(); return end
    global.test_index = global.test_index + 1

    global.test_results[test.name] = test.runner()
end)
