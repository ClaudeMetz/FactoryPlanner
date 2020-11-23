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

local function create_item_category(modal_data, type, label_arg)
    local flow_category = modal_data.modal_elements.content_frame.add{type="flow", direction="vertical"}

    local label_title = flow_category.add{type="label", caption={"fp.matrix_" .. type .. "_items", label_arg}}
    label_title.style.font = "heading-2"

    local frame_items = flow_category.add{type="frame", direction="horizontal", style="slot_button_deep_frame"}
    local table_items = frame_items.add{type="table", column_count=8, style="filter_slot_table"}
    modal_data.modal_elements[type .. "_table"] = table_items

    refresh_item_category(modal_data, type)
end

local function swap_item_category(player, element)
    local ui_state = data_util.get("ui_state", player)
    local subfactory = ui_state.context.subfactory

    local split_string = split_string(element.name, "_")
    local type, proto_index = split_string[4], tonumber(split_string[5])

    local modal_data = data_util.get("modal_data", player)
    local free_items = modal_data["free_items"]

    -- update the free items here, set the constrained items based on linear dependence data
    if type == "free" then
        -- TODO: seems a little hacky to assume the gui's list has the same order as the subfactory?
        table.remove(subfactory.matrix_free_items, proto_index)
    else -- "constrained"
        local item_proto = modal_data["constrained_items"][proto_index]
        table.insert(subfactory.matrix_free_items, item_proto)
    end

    local matrix_modal_data = matrix_solver.get_matrix_solver_modal_data(player, subfactory)
    local linear_dependence_data = matrix_solver.get_linear_dependence_data(player, subfactory, matrix_modal_data)
    modal_data.constrained_items = linear_dependence_data.allowed_free_items --todo: rename constrained_items to something like allowed_free_items
    modal_data.free_items = matrix_modal_data.free_items

    refresh_item_category(modal_data, "constrained")
    refresh_item_category(modal_data, "free")
end


-- ** TOP LEVEL **
matrix_dialog.dialog_settings = (function(_) return {
    caption = {"fp.matrix_solver"},
    create_content_frame = true
} end)

function matrix_dialog.open(player, modal_data)
    local ui_state = data_util.get("ui_state", player)
    local subfactory = ui_state.context.subfactory

    local matrix_modal_data = matrix_solver.get_matrix_solver_modal_data(player, subfactory)

    modal_data.constrained_items = {} --todo: rename constrained_items to something like allowed_free_items
    modal_data.free_items = matrix_modal_data.free_items

    local num_needed_free_items = matrix_modal_data.num_rows - matrix_modal_data.num_cols + #matrix_modal_data.free_items

    create_item_category(modal_data, "constrained", num_needed_free_items)
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