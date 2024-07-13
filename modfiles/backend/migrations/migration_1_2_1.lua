---@diagnostic disable

local migration = {}

function migration.player_table(player_table)
    for factory in player_table.district:iterator() do
        if factory.item_request_proxy and factory.item_request_proxy.valid then
            factory.item_request_proxy.destroy{raise_destroy=false}
        end
        factory.item_request_proxy = nil
    end
end

return migration
