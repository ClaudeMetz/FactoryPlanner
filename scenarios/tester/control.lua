-- ** LLOG **
llog = require("__factoryplanner__/llog")
LLOG_EXCLUDES = {}

-- ** TESTS **
TESTS = {
    (function()
        game.print("hello")
    end)
}

script.on_event(defines.events.on_game_created_from_scenario, function()
    llog("Factory Planner test suite initiated")
    game.autosave_enabled = false
    game.speed = 100
    global.test_index = 1
end)

script.on_event(defines.events.on_tick, function()
    local test = TESTS[global.test_index]
    if test == nil then game.set_game_state{game_finished=true}; return end
    global.test_index = global.test_index + 1
    test()
end)
