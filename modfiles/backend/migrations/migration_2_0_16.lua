---@diagnostic disable

local migration = {}

function migration.player_table(player_table)
    local item_views = player_table.preferences.item_views
    if item_views then
        local found_index, enabled = nil, nil
        for index, view in pairs(item_views.views) do
            if view.name == "belts_or_lanes" then
                found_index = index
                enabled = view.enabled
            end
        end
        if found_index then
            item_views.views[found_index] = {name="throughput", enabled=enabled}
        else
            table.insert(item_views.views, {name="throughput", enabled=false})
        end
    end
end

return migration
