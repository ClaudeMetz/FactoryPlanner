local migration = {}

function migration.global()
end

function migration.subfactory(subfactory)
  for _, floor in pairs(Subfactory.get_all_floors(subfactory)) do
    for _, line in pairs(Floor.get_in_order(floor, "Line")) do
      if not line.subfloor then
        line.done = false
      end
    end
  end
end

function migration.packed_subfactory(packed_subfactory)
    local function update_lines(floor)
        for _, packed_line in ipairs(floor.Line.objects) do
            if packed_line.subfloor then
                update_lines(packed_line.subfloor)
            else
                packed_line.done = false
            end
        end
    end
    update_lines(packed_subfactory.top_floor)  
end
  
function migration.player_table(player_table)
    player_table.preferences.done_column = false
end

return migration