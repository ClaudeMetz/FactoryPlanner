-- ** LLOG **
llog = require("__factoryplanner__.llog")
LLOG_EXCLUDES = {}

-- ** TESTS **
local solver_tests = require("solver.tests")

local function setup()
    game.autosave_enabled = false
    game.speed = 100

    global.runplan = {}
    global.results = {}
    global.next_test = 1
    for _, test_set in pairs{solver_tests} do
        for _, test in ipairs(test_set) do
            table.insert(global.runplan, test)
        end
    end
end

local function teardown()
    local failures = ""

    for name, result in pairs(global.results) do
        if result ~= "pass" then failures = failures .. "\nTest " .. name .. ": " .. result end
    end

    local output = (failures ~= "") and "Passed all " .. #global.runplan .. " tests"
        or "Failed " .. #failures .. " of " .. #global.runplan .. " tests" .. failures
    game.write_file("results.txt", output)

    script.on_event(defines.events.on_tick, nil)
    print("tester_done")  -- let script know to kill Factorio
end

local function run_test()
    local test = global.runplan[global.next_test]
    if not test then teardown(); return end

    global.results[test.name] = test.runner(test)
    global.next_test = global.next_test + 1
end


script.on_event(defines.events.on_game_created_from_scenario, setup)

script.on_event(defines.events.on_tick, run_test)
