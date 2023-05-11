local migration = {}

function migration.player_table(player_table)
    for _, factory_name in pairs({"factory", "archive"}) do
        local factory = player_table[factory_name]
        local subfactories = Factory.get_in_order(factory, "Subfactory")
        if table_size(subfactories) ~= factory.Subfactory.count then
            local gui_position = 1
            for _, subfactory in pairs(factory.Subfactory.datasets) do
                subfactory.gui_position = gui_position
                gui_position = gui_position + 1
            end
        end
    end
end

return migration
