migration_0_17_10 = {}

function migration_0_17_10.global()
    global.devmode = nil
    global.margin_of_error = nil

    -- Add mod version for the first time to the player_table
    for _, player_table in pairs(global.players) do
        player_table.mod_version = global.mod_version
    end
end

function migration_0_17_10.player_table(player_table)
    player_table.preferences = {}
    player_table.ui_state = {}

    player_table.factory.mod_version = nil

    player_table.main_dialog_dimensions = nil
    player_table.view_state = nil
    player_table.preferred_belt_name = nil
    player_table.default_machines = nil
    player_table.context = nil
    player_table.recipe_filter_preferences = nil
    player_table.modal_dialog_type = nil
    player_table.selected_object = nil
    player_table.modal_data = nil
    player_table.current_activity = nil
    player_table.queued_message = nil
end