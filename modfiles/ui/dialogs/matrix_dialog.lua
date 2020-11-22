matrix_dialog = {}

-- ** LOCAL UTIL **
local function refresh_item_category(modal_data, type)
    local table_items = modal_data.modal_elements[type .. "_table"]
    table_items.clear()

    for index, proto in ipairs(modal_data[type .. "_items"]) do
        table_items.add{type="sprite-button", name="fp_sprite-button_matrix_" .. type .. "_" .. index,
          sprite=proto.sprite, tooltip=proto.localised_name, style="flib_slot_button_default",
          mouse_button_filter={"left"}}
    end
end

local function create_item_category(modal_data, type)
    local flow_category = modal_data.modal_elements.content_frame.add{type="flow", direction="vertical"}

    local label_title = flow_category.add{type="label", caption={"fp.matrix_" .. type .. "_items"}}
    label_title.style.font = "heading-2"

    local frame_items = flow_category.add{type="frame", direction="horizontal", style="slot_button_deep_frame"}
    local table_items = frame_items.add{type="table", column_count=8, style="filter_slot_table"}
    modal_data.modal_elements[type .. "_table"] = table_items

    refresh_item_category(modal_data, type)
end

local function swap_item_category(player, element)
    local split_string = split_string(element.name, "_")
    local type, proto_index = split_string[4], tonumber(split_string[5])

    local modal_data = data_util.get("modal_data", player)
    local item_array = modal_data[type .. "_items"]
    local swapped_proto = item_array[proto_index]
    table.remove(item_array, proto_index)

    local opposing_type = (type == "free") and "constrained" or "free"
    local opposing_item_array = modal_data[opposing_type .. "_items"]
    table.insert(opposing_item_array, swapped_proto)

    refresh_item_category(modal_data, "constrained")
    refresh_item_category(modal_data, "free")
end


-- ** TOP LEVEL **
matrix_dialog.dialog_settings = (function(_) return {
    caption = {"fp.matrix_solver"},
    create_content_frame = true,
    show_submit_button = true
} end)

function matrix_dialog.open(player, modal_data)
    local ui_state = data_util.get("ui_state", player)
    local subfactory = ui_state.context.subfactory

    -- Provisional item to test the swapping, need to fill in what goes here
    -- Also the format could need to be adjusted
    local items = Subfactory.get_in_order(subfactory, "Product")

    -- Both of these need to be continuously indexed (for now)
    modal_data.constrained_items = {items[1].proto, items[2].proto, items[3].proto}
    modal_data.free_items = subfactory.matrix_free_items

    create_item_category(modal_data, "constrained")
    create_item_category(modal_data, "free")
end

function matrix_dialog.close(player, action)
    local ui_state = data_util.get("ui_state", player)
    local subfactory = ui_state.context.subfactory

    if action == "submit" then
        -- This is provisional, I don't know what format you intend to store the free items in
        subfactory.matrix_free_items = ui_state.modal_data.free_items

        calculation.update(player, subfactory)
        main_dialog.refresh(player, "subfactory")
    elseif action == "cancel" and ui_state.modal_data.first_open then
        subfactory.matrix_free_items = nil
    end
end


-- ** EVENTS **
matrix_dialog.gui_events = {
    on_gui_click = {
        {
            pattern = "^fp_sprite%-button_matrix_[a-z]+_%d+$",
            handler = swap_item_category
        }
    }
}