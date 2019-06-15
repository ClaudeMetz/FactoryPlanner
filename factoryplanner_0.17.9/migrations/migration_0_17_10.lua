migration_0_17_10 = {}

function migration_0_17_10.global()
    global.devmode = nil
    global.margin_of_error = nil

    -- Add mod version and player_index for the first time to the player_table
    for player_index, player_table in pairs(global.players) do
        player_table.mod_version = global.mod_version
        player_table.index = player_index
    end
end

function migration_0_17_10.player_table(player, player_table)
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

function migration_0_17_10.subfactory(player, subfactory)
    for _, floor in pairs(Subfactory.get_in_order(subfactory, "Floor")) do
        for _, line in pairs(Floor.get_in_order(floor, "Line")) do
            line.recipe_category = nil
            line.category_id = nil

            line.machine_name = nil
            line.machine_id = nil
        end
    end
end