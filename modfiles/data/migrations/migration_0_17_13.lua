local migration = {}

function migration.global()
    global.devmode = nil
    global.margin_of_error = nil

    global.all_belts = generator.all_belts()
    global.all_fuels = generator.all_fuels()
    global.all_machines = generator.all_machines()

    -- Add mod version and player_index for the first time to the player_table
    for player_index, player_table in pairs(global.players) do
        player_table.mod_version = global.mod_version
        player_table.index = player_index
    end
end

function migration.player_table(player_table)
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

function migration.subfactory(subfactory)
    for _, floor in pairs(Subfactory.get_all_floors(subfactory)) do
        for _, line in pairs(Floor.get_in_order(floor, "Line")) do
            local category_id = global.all_machines.map[line.recipe_category]
            line.category_id = category_id
            line.recipe_category = nil
            if category_id ~= nil then
                local machine_id = global.all_machines.categories[category_id].map[line.machine_name]
                line.machine_id = machine_id
            else
                line.machine_id = nil
            end
            line.machine_name = nil
        end
    end
end

return migration