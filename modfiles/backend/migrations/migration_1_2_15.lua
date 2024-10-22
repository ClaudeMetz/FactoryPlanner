---@diagnostic disable

local migration = {}

function migration.global()
end

function migration.player_table(player_table)
    local item_views = player_table.preferences.item_views
    if item_views == nil then return end

    local preferences = { views = {}, selected_index = nil }
    for index, view in pairs(item_views) do
        if view.selected then preferences.selected_index = index end
        table.insert(preferences.views, {name=view.name, enabled=view.enabled})
    end
    player_table.preferences.item_views = preferences
end

function migration.packed_factory(packed_factory)
end

return migration
