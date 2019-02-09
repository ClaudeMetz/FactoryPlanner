-- Returns given table ordered and formatted (-> [gui_position] = id)
function order_by_position(data_table)
    local ordered_table = {}
    for id, dataset in pairs(data_table) do
        ordered_table[dataset:get_gui_position()] = id
    end
    return ordered_table
end

-- Shifts every position after the deleted one down by 1
function update_positions(data_table, deleted_position)
    for _, dataset in pairs(data_table) do
        if dataset:get_gui_position() > deleted_position then
            dataset:set_gui_position(dataset:get_gui_position() - 1)
        end
    end
end

-- Returns the id of the dataset that has the given position in the given table
function get_id_by_position(data_table, gui_position)
    if gui_position == 0 then return 0 end
    for id, dataset in pairs(data_table) do
        if dataset:get_gui_position() == gui_position then
            return id
        end
    end
end

-- Shifts position of given dataset (indicated by id) in the given direction
function shift_position(data_table, main_id, direction, total_datasets)
    local main_dataset = data_table[main_id]
    local main_gui_position = main_dataset:get_gui_position()
    -- Doesn't shift if outer elements are being shifted further outward
    if (main_gui_position == 1 and direction == "negative") or
      (main_gui_position == total_datasets and direction == "positive") then 
        return 
    end

    local second_gui_position
    if direction == "positive" then
        second_gui_position = main_gui_position + 1
    else  -- direction == "negative"
        second_gui_position = main_gui_position - 1
    end
    local second_id = get_id_by_position(data_table, second_gui_position)
    local second_dataset = data_table[second_id]

    main_dataset:set_gui_position(second_gui_position)
    second_dataset:set_gui_position(main_gui_position)
end