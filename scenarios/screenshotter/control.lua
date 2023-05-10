-- Runs through a series of steps, taking screenshots of various FP windows

script.on_event(defines.events.on_game_created_from_scenario, function()
    game.autosave_enabled = false

    -- Excuse the stupid move naming, this has been a long process
    -- (it totally doesn't correlate to the actual meanings in a sensible way)
    global.scene = 1
    global.shot = 1
    global.pause = 10

    global.setup = function() remote.call("screenshotter_input", "execute_action", 1, "player_setup") end
    global.dimensions = {}

    global.protected_names = remote.call("screenshotter_input", "initial_setup")
end)


remote.add_interface("screenshotter_output", {
    return_dimensions = function(scene, dimensions)
        global.dimensions[scene] = dimensions
    end
})

local function write_metadata_file()
    local frame_corners = {}

    for scene, dimensions in pairs(global.dimensions) do
        local location, size = dimensions.location, dimensions.actual_size
        frame_corners[scene] = {
            top_left = {x = location.x, y = location.y},
            bottom_right = {x = location.x + size.width, y = location.y + size.height}
        }
    end

    local metadata = {frame_corners=frame_corners, protected_names=global.protected_names}
    game.write_file("metadata.json", game.table_to_json(metadata))
end


local scenes = {
    "01_main_interface",
    "02_compact_interface",
    "03_item_picker",
    "04_recipe_picker",
    "05_machine",
    "06_import",
    "07_utility",
    "08_preferences"
}

local shots = {
    function(scene)
        remote.call("screenshotter_input", "execute_action", 1, ("setup_" .. scene))
        global.pause = 10
    end,
    function(scene)
        game.take_screenshot{path=(scene .. ".png"), show_gui=true, zoom=3}
    end,
    function(scene)
        remote.call("screenshotter_input", "execute_action", 1, ("teardown_" .. scene))
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
            write_metadata_file()
            script.on_event(defines.events.on_tick, nil)
            print("screenshotter_done")  -- let script know to kill Factorio
        end
    end
end)
