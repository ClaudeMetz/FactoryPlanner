matrix_dialog = {}

-- ** LOCAL UTIL **
local function update_dialog_submit_button(modal_data, matrix_metadata)
    local num_needed_free_items = matrix_metadata.num_rows - matrix_metadata.num_cols + #matrix_metadata.free_items
    local curr_free_items = #modal_data["free_items"]

    local message = nil
    if num_needed_free_items > curr_free_items then
        message = {"fp.matrix_constrained_items", num_needed_free_items, {"fp.pl_item", num_needed_free_items}}
    end
    modal_dialog.set_submit_button_state(modal_data.modal_elements, (message == nil), message)
end

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

    local title_string = (type == "free") and {"fp.matrix_free_items"} or
      {"fp.matrix_constrained_items", label_arg, {"fp.pl_item", label_arg}}
    local label_title = flow_category.add{type="label", caption=title_string}
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

    -- update the free items here, set the constrained items based on linear dependence data
    if type == "free" then
        -- note this assumes the gui's list has the same order as the subfactory
        table.remove(subfactory.matrix_free_items, proto_index)
    else -- "constrained"
        local item_proto = modal_data["constrained_items"][proto_index]
        table.insert(subfactory.matrix_free_items, item_proto)
    end

    local subfactory_data = calculation.interface.generate_subfactory_data(player, subfactory)
    local matrix_metadata = matrix_solver.get_matrix_solver_metadata(subfactory_data)
    local linear_dependence_data = matrix_solver.get_linear_dependence_data(subfactory_data, matrix_metadata)
    modal_data.constrained_items = linear_dependence_data.allowed_free_items
    modal_data.free_items = matrix_metadata.free_items

    refresh_item_category(modal_data, "constrained")
    refresh_item_category(modal_data, "free")
    update_dialog_submit_button(modal_data, matrix_metadata)
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
    local subfactory_data = calculation.interface.generate_subfactory_data(player, subfactory)
    if #subfactory_data.top_floor.lines == 0 then
        modal_dialog.exit(player, "cancel")
        return true
    end

    local matrix_metadata = matrix_solver.get_matrix_solver_metadata(subfactory_data)
    local linear_dependence_data = matrix_solver.get_linear_dependence_data(subfactory_data, matrix_metadata)

    -- too many ways to create the products
    if matrix_metadata.num_rows < matrix_metadata.num_cols then
        local label_title = modal_data.modal_elements.content_frame.add{type="label", caption={"fp.matrix_linear_dependent_recipes"}}
        label_title.style.font = "heading-2"
        return
    end

    modal_data.constrained_items = linear_dependence_data.allowed_free_items
    modal_data.free_items = matrix_metadata.free_items

    local num_needed_free_items = matrix_metadata.num_rows - matrix_metadata.num_cols + #matrix_metadata.free_items

    -- user doesn't need select any free items, just run the matrix solver
    if num_needed_free_items == 0 then
        modal_dialog.exit(player, "submit")
        return true
    end

    create_item_category(modal_data, "constrained", num_needed_free_items)
    create_item_category(modal_data, "free")
    update_dialog_submit_button(modal_data, matrix_metadata)
end

function matrix_dialog.close(player, action)
    local ui_state = data_util.get("ui_state", player)
    local subfactory = ui_state.context.subfactory

    if action == "submit" then
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