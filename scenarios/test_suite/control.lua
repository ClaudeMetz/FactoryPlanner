require("__factoryplanner__/lualib/llog.lua")

script.on_event(defines.events.on_game_created_from_scenario, function()
    llog("Factory Planner test suite initiated")
    game.autosave_enabled = false
    --game.speed = 1000
end)