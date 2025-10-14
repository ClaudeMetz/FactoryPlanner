-- ** LOCAL UTIL **
local function select_temperature(player, temperature)
    local modal_data = util.globals.modal_data(player)
    local table_temperatures = modal_data.modal_elements.temperatures_table

    for _, button in pairs(table_temperatures.children) do
        local matched = (button.tags.temperature == temperature)
        button.toggled = not button.toggled and matched
    end
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

    for index, temperature in pairs(values) do
        table_temperatures.add{type="button", caption={"fp.temperature_value", temperature},
            tags={mod="fp", on_gui_click="change_item_temperature", temperature=temperature},
            style="fp_button_push", mouse_button_filter={"left"}}
    end

    local temperature = nil  -- needs to be an if because the value can be nil
    if object.class == "Fuel" then temperature = object.temperature
    else temperature = object.temperatures[modal_data.name] end
    select_temperature(player, temperature)  -- sets toggled state
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
