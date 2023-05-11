local migration = {}

function migration.player_table(player_table)
    local Subfactory = player_table.archive.Subfactory
    Subfactory.count = table_size(Subfactory.datasets)

    local gui_position = 1
    for _, subfactory in pairs(Subfactory.datasets) do
        subfactory.gui_position = gui_position
        gui_position = gui_position + 1
    end
end

return migration
