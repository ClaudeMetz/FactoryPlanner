data_util = {}

-- Returns given datasets' id's in order by position (-> [gui_position] = id)
function data_util.order_by_position(datasets)
    local ordered_table = {}
    for id, dataset in pairs(datasets) do
        ordered_table[dataset.gui_position] = id
    end
    return ordered_table
end

-- Shifts every position after the deleted one down by 1
function data_util.update_positions(datasets, deleted_position)
    for _, dataset in pairs(datasets) do
        if dataset.gui_position > deleted_position then
            dataset.gui_position = dataset.gui_position - 1
        end
    end
end

-- Returns the id of the dataset that has the given position in the given table
function data_util.get_id_by_position(datasets, gui_position)
    if gui_position == 0 then return 0 end
    for id, dataset in pairs(datasets) do
        if dataset.gui_position == gui_position then
            return id
        end
    end
end

-- Shifts position of given dataset (indicated by main_id) in the given direction
function data_util.shift_position(datasets, main_id, direction, dataset_count)
    local main_dataset = datasets[main_id]
    local main_gui_position = main_dataset.gui_position
    
    -- Doesn't shift if outer elements are being shifted further outward
    if (main_gui_position == 1 and direction == "negative") or
      (main_gui_position == dataset_count and direction == "positive") then 
        return 
    end

    local second_gui_position
    if direction == "positive" then
        second_gui_position = main_gui_position + 1
    else  -- direction == "negative"
        second_gui_position = main_gui_position - 1
    end
    local second_id = data_util.get_id_by_position(datasets, second_gui_position)
    local second_dataset = datasets[second_id]

    main_dataset.gui_position = second_gui_position
    second_dataset.gui_position = main_gui_position
end