production_box = {}

-- ** LOCAL UTIL **
local function refresh_production(player)
    local subfactory = data_util.get("context", player).subfactory
    if subfactory and subfactory.valid and main_dialog.is_in_focus(player) then
        calculation.update(player, subfactory)
        main_dialog.refresh(player, "subfactory")
    end
end

local function handle_matrix_toggle(player)
    local subfactory = data_util.get("context", player).subfactory

    if subfactory.matrix_free_items == nil then
        subfactory.matrix_free_items = {}  -- 'activate' the matrix solver
        refresh_production(player)
    else
        subfactory.matrix_free_items = nil  -- disable the matrix solver
        subfactory.linearly_dependant = false

        -- This function works its way through subfloors. Consuming recipes can't have subfloors though.
        local any_lines_removed = false
        local function remove_consuming_recipes(floor)
            for _, line in pairs(Floor.get_in_order(floor, "Line")) do
                if line.subfloor then
                    remove_consuming_recipes(line.subfloor)
                elseif line.recipe.production_type == "consume" then
                    Floor.remove(floor, line)
                    any_lines_removed = true
                end
            end
        end

        -- The sequential solver doesn't like byproducts yet, so remove those lines
        local top_floor = Subfactory.get(subfactory, "Floor", 1)
        remove_consuming_recipes(top_floor)

        if any_lines_removed then  -- inform the user if any byproduct recipes are being removed
            title_bar.enqueue_message(player, {"fp.hint_byproducts_removed"}, "hint", 1, false)
        end

        refresh_production(player)  -- recalculate with the sequential solver
    end
end


-- ** TOP LEVEL **
function production_box.build(player)
    local main_elements = data_util.get("main_elements", player)
    main_elements.production_box = {}

    local parent_flow = main_elements.flows.right_vertical
    local frame_vertical = parent_flow.add{type="frame", direction="vertical", style="inside_deep_frame"}
    frame_vertical.style.vertically_stretchable = true
    frame_vertical.style.horizontally_stretchable = true
    main_elements.production_box["vertical_frame"] = frame_vertical

    local subheader = frame_vertical.add{type="frame", direction="horizontal", style="subheader_frame"}
    subheader.style.maximal_height = 100  -- large value to nullify maximal_height
    subheader.style.padding = {8, 8, 6, 8}

    local button_refresh = subheader.add{type="sprite-button", name="fp_sprite-button_production_refresh",
      sprite="utility/refresh", style="tool_button", tooltip={"fp.refresh_production"}, mouse_button_filter={"left"}}
    main_elements.production_box["refresh_button"] = button_refresh

    local label_title = subheader.add{type="label", caption={"fp.production"}, style="frame_title"}
    label_title.style.padding = 0
    label_title.style.left_margin = 6

    local label_level = subheader.add{type="label"}
    label_level.style.margin = {0, 12, 0, 6}
    main_elements.production_box["level_label"] = label_level

    local button_floor_up = subheader.add{type="button", name="fp_button_production_floor_up", caption={"fp.floor_up"},
      tooltip={"fp.floor_up_tt"}, style="fp_button_rounded_mini", mouse_button_filter={"left"}}
    button_floor_up.style.disabled_font_color = {}
    main_elements.production_box["floor_up_button"] = button_floor_up
    local button_floor_top = subheader.add{type="button", name="fp_button_production_floor_top",
      caption={"fp.floor_top"}, tooltip={"fp.floor_top_tt"}, style="fp_button_rounded_mini",
      mouse_button_filter={"left"}}
    button_floor_top.style.disabled_font_color = {}
    main_elements.production_box["floor_top_button"] = button_floor_top

    subheader.add{type="empty-widget", style="flib_horizontal_pusher"}

    local table_matrix_solver = subheader.add{type="table", column_count=2}
    table_matrix_solver.style.horizontal_spacing = 0
    table_matrix_solver.style.right_margin = 12

    local button_solver_toggle = table_matrix_solver.add{type="button", name="fp_button_production_solver_toggle",
      caption={"fp.matrix_solver"}, mouse_button_filter={"left"}}
    --button_solver_toggle.style.disabled_font_color = {}
    main_elements.production_box["solver_toggle_button"] = button_solver_toggle
    local button_solver_configure = table_matrix_solver.add{type="sprite-button", sprite="utility/change_recipe",
      name="fp_button_production_solver_configure", style="fp_button_push", mouse_button_filter={"left"}}
    button_solver_configure.style.size = 26
    button_solver_configure.style.padding = -2
    main_elements.production_box["solver_configure_button"] = button_solver_configure

    local table_view_state = view_state.build(player, subheader)
    main_elements.production_box["view_state_table"] = table_view_state

    local label_instruction = frame_vertical.add{type="label", style="bold_label"}
    label_instruction.style.margin = 20
    main_elements.production_box["instruction_label"] = label_instruction

    production_box.refresh(player)
end

function production_box.refresh(player)
    local ui_state = data_util.get("ui_state", player)
    local production_box_elements = ui_state.main_elements.production_box

    local subfactory = ui_state.context.subfactory
    local subfactory_valid = subfactory and subfactory.valid

    local current_level = (subfactory_valid) and subfactory.selected_floor.level or 1
    local any_lines_present = (subfactory_valid) and (subfactory.selected_floor.Line.count > 0) or false
    local matrix_solver_active = (subfactory_valid and subfactory.matrix_free_items ~= nil)
    local archive_open = (ui_state.flags.archive_open)

    production_box_elements.refresh_button.enabled = (not archive_open and subfactory_valid and any_lines_present)
    production_box_elements.level_label.caption = (not subfactory_valid) and ""
      or {"fp.bold_label", {"fp.two_word_title", {"fp.level"}, current_level}}

    production_box_elements.floor_up_button.visible = (subfactory_valid)
    production_box_elements.floor_up_button.enabled = (current_level > 1)

    production_box_elements.floor_top_button.visible = (subfactory_valid)
    production_box_elements.floor_top_button.enabled = (current_level > 2)

    production_box_elements.solver_toggle_button.visible = (subfactory_valid)
    production_box_elements.solver_toggle_button.enabled = (not archive_open)
    production_box_elements.solver_toggle_button.style = (matrix_solver_active)
      and "fp_button_push_active" or "fp_button_push"
    production_box_elements.solver_toggle_button.style.padding = {0, 8}  -- needs to be re-set when changing the style

    production_box_elements.solver_configure_button.visible = (subfactory_valid)
    production_box_elements.solver_configure_button.enabled = (matrix_solver_active and not archive_open)

    view_state.refresh(player, production_box_elements.view_state_table)
    production_box_elements.view_state_table.visible = (subfactory_valid)

    -- This structure is stupid and huge, but not sure how to do it more elegantly
    production_box_elements.instruction_label.visible = false
    if not archive_open then
        if subfactory == nil then
            production_box_elements.instruction_label.caption = {"fp.production_instruction_subfactory"}
            production_box_elements.instruction_label.visible = true
        elseif subfactory_valid then
            if subfactory.Product.count == 0 then
                production_box_elements.instruction_label.caption = {"fp.production_instruction_product"}
                production_box_elements.instruction_label.visible = true
            elseif not any_lines_present then
                production_box_elements.instruction_label.caption = {"fp.production_instruction_recipe"}
                production_box_elements.instruction_label.visible = true
            end
        end
    end
end


-- Changes the floor to either be the top one or the one above the current one
function production_box.change_floor(player, destination)
    local ui_state = data_util.get("ui_state", player)
    local subfactory = ui_state.context.subfactory
    local floor = ui_state.context.floor

    if subfactory == nil or floor == nil then return end

    local selected_floor = nil
    if destination == "up" and floor.level > 1 then
        selected_floor = floor.origin_line.parent
    elseif destination == "top" then
        selected_floor = Subfactory.get(subfactory, "Floor", 1)
    end

    -- Only need to refresh if the floor was indeed changed
    if selected_floor ~= nil then
        ui_util.context.set_floor(player, selected_floor)

        -- Remove previous floor if it has no recipes
        local floor_removed = Floor.remove_if_empty(floor)

        if floor_removed then calculation.update(player, subfactory) end
        main_dialog.refresh(player, "production_detail")
    end
end


-- ** EVENTS **
production_box.gui_events = {
    on_gui_click = {
        {
            name = "fp_sprite-button_production_refresh",
            timeout = 20,
            handler = refresh_production
        },
        {
            pattern = "^fp_button_production_floor_[a-z]+$",
            handler = (function(player, element, _)
                local destination = string.gsub(element.name, "fp_button_production_floor_", "")
                production_box.change_floor(player, destination)
            end)
        },
        {
            name = "fp_button_production_solver_toggle",
            handler = handle_matrix_toggle
        },
        {
            name = "fp_button_production_solver_configure",
            handler = (function(player, _, _)
                modal_dialog.enter(player, {type="matrix", modal_data={configuration=true}})
            end)
        }
    }
}

production_box.misc_events = {
    fp_refresh_production = refresh_production,

    fp_floor_up = (function(player, _)
        if main_dialog.is_in_focus(player) then
            production_box.change_floor(player, "up")
        end
    end)
}