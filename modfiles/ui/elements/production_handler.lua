production_handler = {}

-- ** LOCAL UTIL **
local function handle_recipe_click(player, button, metadata)
    local line_id = tonumber(string.match(button.name, "%d+"))
    local context = data_util.get("context", player)
    local line = Floor.get(context.floor, "Line", line_id)

    if metadata.direction ~= nil then  -- Shifts line in the given direction
        if not ui_util.check_archive_status(player) then return end

        local shifting_function = (metadata.alt) and Floor.shift_to_end or Floor.shift
        -- Can't shift second line into the first position on subfloors. Top line is disabled, so no special handling
        if not (metadata.direction == "negative" and context.floor.level > 1 and line.gui_position == 2)
          and shifting_function(context.floor, line, metadata.direction) then
            calculation.update(player, context.subfactory)
            main_dialog.refresh(player, "subfactory")
        else
            local direction_string = (metadata.direction == "negative") and {"fp.up"} or {"fp.down"}
            local message = {"fp.error_list_item_cant_be_shifted", {"fp.pl_recipe", 1}, direction_string}
            title_bar.enqueue_message(player, message, "error", 1, true)
        end

    elseif metadata.alt then
        local relevant_line = (line.subfloor == nil) and line or Floor.get(line.subfloor, "Line", 1)
        data_util.execute_alt_action(player, "show_recipe",
          {recipe=relevant_line.recipe.proto, line_products=Line.get_in_order(line, "Product")})

    elseif metadata.click == "left" then  -- Attaches a subfloor to this line
        local subfloor = line.subfloor

        if subfloor == nil then
            if not ui_util.check_archive_status(player) then return end

            subfloor = Floor.init(line)  -- attaches itself to the given line automatically
            Subfactory.add(context.subfactory, subfloor)
            calculation.update(player, context.subfactory)
        end

        ui_util.context.set_floor(player, subfloor)
        main_dialog.refresh(player, "subfactory")

    -- Handle removal of clicked (assembly) line
    elseif metadata.action == "delete" then
        if not ui_util.check_archive_status(player) then return end

        Floor.remove(context.floor, line)
        calculation.update(player, context.subfactory)
        main_dialog.refresh(player, "subfactory")
    end
end


-- ** TOP LEVEL **
production_handler.gui_events = {
    on_gui_click = {
        {
            pattern = "^fp_sprite%-button_production_recipe_%d+$",
            timeout = 20,
            handler = (function(player, element, metadata)
                handle_recipe_click(player, element, metadata)
            end)
        },
    }
}