---@diagnostic disable

local migration = {}

function migration.global()
end

function migration.player_table(player_table)
    local preferences = { views = {}, selected_index = nil }
    for index, view in pairs(player_table.preferences.item_views) do
        if view.selected then preferences.selected_index = index end
        table.insert(preferences.views, {name=view.name, enabled=view.enabled})
    end
    player_table.preferences.item_views = preferences
end

function migration.packed_factory(packed_factory)
end

return migration
