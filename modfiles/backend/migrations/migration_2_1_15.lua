---@diagnostic disable

local migration = {}

function migration.player_table(player_table)
    local preferences = player_table.preferences.item_views
    if not preferences or preferences.selected then return end

    local selected = preferences.views[preferences.selected_index]
    preferences.selected = {primary=selected.name}
    preferences.selected_index = nil
end

return migration
