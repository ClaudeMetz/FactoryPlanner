---@diagnostic disable

-- Gets going via an event the main mod doesn't use, so there's no event shadowing
script.on_event(defines.events.on_game_created_from_scenario, function(event)

    log("Tests completed")
end)
