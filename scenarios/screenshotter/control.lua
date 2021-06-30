-- Runs through a series of steps, taking screenshots of various FP windows

script.on_event(defines.events.on_game_created_from_scenario, function()
    game.autosave_enabled = false

    -- Excuse the stupid move naming, this has been a long process
    global.scene = 1
    global.shot = 1
    global.pause = 10

    global.setup = function() remote.call("factoryplanner", "execute_action", 1, "player_setup") end

    remote.call("factoryplanner", "initial_setup")  -- set up before the player is created
end)


local scenes = {
    "01_main_interface",
    "02_item_picker",
    "03_recipe_picker",
    "04_beacon",
    "05_import",
    "06_utility",
    "07_preferences"
}

local shots = {
    function(scene)
        remote.call("factoryplanner", "execute_action", 1, ("setup_" .. scene))
        global.pause = 5
    end,
    function(scene)
        game.take_screenshot{path=(scene .. ".png"), show_gui=true, zoom=3}
    end,
    function(scene)
        remote.call("factoryplanner", "execute_action", 1, ("teardown_" .. scene))
    end,
}

script.on_event(defines.events.on_tick, function()
    if global.setup then
        global.setup()
        global.setup = nil
    end

    if global.pause > 0 then
        global.pause = global.pause - 1
    else
        local scene, shot = scenes[global.scene], shots[global.shot]
        shot(scene)  -- execute the current shot

        global.shot = global.shot + 1
        if global.shot > table_size(shots) then
            global.scene = global.scene + 1
            global.shot = 1
        end

        if global.scene > table_size(scenes) then
            script.on_event(defines.events.on_tick, nil)
        end
    end
end)
