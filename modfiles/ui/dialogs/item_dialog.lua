-- ** LOCAL UTIL **
local function refresh_defaults_table(player)
    local modal_data = util.globals.modal_data(player)
    local defaults_table = modal_data.modal_elements["defaults_table"]


    local active_temperatures = {}
    for _, temperature in pairs(modal_data.defaults) do
        active_temperatures[temperature] = true
    end

    local passive_temperatures = {}
    for _, prototype in pairs(TEMPERATURE_MAP[modal_data.name]) do
        if not active_temperatures[prototype.temperature] then
            table.insert(passive_temperatures, prototype.temperature)
        end
    end

    defaults_table.clear()
    defaults_table.add{type="label", caption={"fp.temperature_defaults_active"},
        tooltip={"fp.temperature_defaults_active_tt"}, style="bold_label"}
    defaults_table.add{type="label", caption={"fp.temperature_defaults"},
        tooltip={"fp.temperature_defaults_tt"}, style="bold_label"}

    local index = 1
    local active_temp, passive_temp = nil, nil

    while index <= #modal_data.defaults or index <= #passive_temperatures do
        active_temp = modal_data.defaults[index]
        passive_temp = passive_temperatures[index]

        local active_flow = defaults_table.add{type="flow", direction="horizontal",
            style="fp_flow_temperature_defaults"}
        local passive_flow = defaults_table.add{type="flow", direction="horizontal",
            style="fp_flow_temperature_defaults"}

        if active_temp then
            active_flow.add{type="sprite-button", sprite="fp_arrow_up",
                tags={mod="fp", on_gui_click="move_temperature_default", direction="up", index=index},
                style="fp_sprite-button_move_small", enabled=(index > 1), mouse_button_filter={"left"}}
            active_flow.add{type="sprite-button", sprite="fp_arrow_down",
                tags={mod="fp", on_gui_click="move_temperature_default", direction="down", index=index},
                style="fp_sprite-button_move_small", mouse_button_filter={"left"}}

            local active_label = active_flow.add{type="label", caption={"fp.temperature_value", active_temp},
                tags={temperature=active_temp}}
            active_label.style.left_margin = 4
        end

        if passive_temp then
            passive_flow.add{type="sprite-button", sprite="fp_arrow_left",
                tags={mod="fp", on_gui_click="move_temperature_default", direction="left", temperature=passive_temp},
                style="fp_sprite-button_move_small", mouse_button_filter={"left"}}

            local passive_label = passive_flow.add{type="label", caption={"fp.temperature_value", passive_temp},
                tags={temperature=passive_temp}}
            passive_label.style.left_margin = 4
        end

        index = index + 1
    end
end


local function select_temperature(player, temperature)
    local modal_data = util.globals.modal_data(player)
    local table_temperatures = modal_data.modal_elements.temperatures_table

    for _, button in pairs(table_temperatures.children) do
        local matched = (button.tags.temperature == temperature)
        button.toggled = not button.toggled and matched
    end
end

local function handle_default_temperature_move(player, tags, _)
    local modal_data = util.globals.modal_data(player)

    if tags.direction == "left" then
        table.insert(modal_data.defaults, tags.temperature)
    else  -- "up"/"down"
        if tags.direction == "down" and tags.index == #modal_data.defaults then
            table.remove(modal_data.defaults, tags.index)
        else
            local temperature = table.remove(modal_data.defaults, tags.index)
            local new_index = (tags.direction == "up") and (tags.index - 1) or (tags.index + 1)
            table.insert(modal_data.defaults, new_index, temperature)
        end
    end

    refresh_defaults_table(player)
end


local function open_item_dialog(player, modal_data)
    local object = OBJECT_INDEX[modal_data.recipe_id or modal_data.fuel_id]
    local temperature_data = (modal_data.fuel_id) and object.temperature_data
        or object.temperature_data[modal_data.name]

    local content_frame = modal_data.modal_elements.content_frame
    local flow_temperature = content_frame.add{type="flow", direction="horizontal"}
    flow_temperature.style.vertical_align = "center"
    flow_temperature.add{type="label", caption={"fp.info_label", {"fp.compatible_temperatures"}},
        tooltip={"fp.item_temperature_tt"}}

    local annotation = flow_temperature.add{type="label", caption=temperature_data.annotation}
    annotation.style.left_margin = 16

    local values = temperature_data.applicable_values
    local table_temperatures = content_frame.add{type="table", column_count=#values}
    table_temperatures.style.horizontal_spacing = 0
    table_temperatures.style.top_margin = 8
    table_temperatures.style.left_margin = 12
    modal_data.modal_elements["temperatures_table"] = table_temperatures

    for _, temperature in pairs(values) do
        table_temperatures.add{type="button", caption={"fp.temperature_value", temperature},
            tags={mod="fp", on_gui_click="change_item_temperature", temperature=temperature},
            style="fp_button_push", mouse_button_filter={"left"}}
    end

    local temperature = nil  -- needs to be an if because the value can be nil
    if object.class == "Fuel" then temperature = object.temperature
    else temperature = object.temperatures[modal_data.name] end
    select_temperature(player, temperature)  -- sets toggled state

    -- Defaults
    local line = content_frame.add{type="line", direction="horizontal"}
    line.style.margin = {8, 0, 8, 0}

    local flow_defaults = content_frame.add{type="flow", direction="horizontal"}
    flow_defaults.add{type="empty-widget", style="flib_horizontal_pusher"}
    local frame_defaults = flow_defaults.add{type="frame", style="deep_frame_in_shallow_frame"}
    local table_defaults = frame_defaults.add{type="table", style="table_with_selection", column_count=2}
    modal_data.modal_elements["defaults_table"] = table_defaults
    flow_defaults.add{type="empty-widget", style="flib_horizontal_pusher"}

    modal_data.defaults = util.globals.preferences(player).default_temperatures[modal_data.name]
    refresh_defaults_table(player)
end

local function close_item_dialog(player, action)
    if action == "submit" then
        local modal_data = util.globals.modal_data(player)
        local table_temperatures = modal_data.modal_elements.temperatures_table

        local object = OBJECT_INDEX[modal_data.recipe_id or modal_data.fuel_id]
        local temperature = nil  -- reset if none is selected

        for _, button in pairs(table_temperatures.children) do
            if button.toggled then
                temperature = button.tags.temperature
                break
            end
        end

        if object.class == "Fuel" then
            object.temperature = temperature
        else  -- "Recipe"
            object.temperatures[modal_data.name] = temperature
        end

        solver.update(player)
        util.gui.run_refresh(player, "factory")
    end
end


-- ** EVENTS **
local listeners = {}

listeners.gui = {
    on_gui_click = {
        {
            name = "change_item_temperature",
            handler = (function(player, tags, _)
                select_temperature(player, tags.temperature)
            end)
        },
        {
            name = "move_temperature_default",
            handler = handle_default_temperature_move
        }
    }
}

listeners.dialog = {
    dialog = "item",
    metadata = (function(modal_data)
        local data_type = (modal_data.fuel_id) and "fuels" or "items"
        local proto = prototyper.util.find(data_type, modal_data.name, modal_data.category_id)
        return {
            caption = {"", {"fp.edit"}, " ", {"fp.pl_item", 1}},
            subheader_text = {"fp.item_dialog_description", proto.localised_name},
            show_submit_button = true
        }
    end),
    open = open_item_dialog,
    close = close_item_dialog
}

return { listeners }
