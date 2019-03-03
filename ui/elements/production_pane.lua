-- Creates the production pane that displays 
function add_production_pane_to(main_dialog, player)
    local flow = main_dialog.add{type="flow", name="flow_production_pane", direction="vertical"}
    flow.style.bottom_padding = 20

    -- Production titlebar
    local flow_titlebar = flow.add{type="table", name="flow_production_titlebar", column_count = 4}
    flow_titlebar.style.vertical_align = "center"
    flow_titlebar.style.top_padding = 8

    -- Info label
    local info = flow.add{type="label", name="label_production_info", caption={"", " (",  {"label.production_info"}, ")"}}

    -- Main production pane
    local scroll_pane = flow.add{type="scroll-pane", name="scroll-pane_production_pane", direction="vertical"}
    scroll_pane.style.horizontally_stretchable = true
    scroll_pane.style.vertically_stretchable = true
    local column_count = 7
    local table = scroll_pane.add{type="table", name="table_production_pane",  column_count=column_count}
    for i=1, column_count do table.style.column_alignments[i] = "middle-center" end
    table.style.horizontal_spacing = 15
    table.style.vertical_spacing = 12
    table.draw_horizontal_lines = true

    refresh_production_pane(player)
end

-- Refreshes the prodiction pane (actionbar + table)
function refresh_production_pane(player)
    local flow_production = player.gui.center["fp_main_dialog"]["flow_production_pane"]
     -- Cuts function short if the production pane hasn't been initialized yet
    if not flow_production then return end

    local subfactory_id = global["selected_subfactory_id"]
    -- selected_subfactory_id is always 0 when there are no subfactories
    if (subfactory_id ~= 0) and Subfactory.is_valid(subfactory_id) then
        local flow_titlebar = flow_production["flow_production_titlebar"]
        flow_titlebar.clear()

        local title = flow_titlebar.add{type="label", name="label_production_pane_title", 
          caption={"", "  ", {"label.production"}, " "}}
        title.style.font = "fp-font-20p"

        local floor_id = Subfactory.get_selected_floor_id(subfactory_id)
        if Floor.get_line_count(subfactory_id, floor_id) > 0 then
            local floor_level = Floor.get_level(subfactory_id, floor_id)
            local label_level = flow_titlebar.add{type="label", name="label_actionbar_level", 
            caption={"", {"label.level"}, " ", floor_level, "  "}}
            label_level.style.font = "fp-font-bold-15p"
            label_level.style.top_padding = 1

            if floor_level > 1 then
                flow_titlebar.add{type="button", name="fp_button_floor_up", caption={"label.go_up"}, style="fp_button_mini"}
                flow_titlebar.add{type="button", name="fp_button_floor_top", caption={"label.to_the_top"}, style="fp_button_mini"}
            end
        end
    end

    refresh_production_table(player)

    --game.print("Floors: " .. Subfactory.get_count(subfactory_id, "Floor"))
end

-- Refreshes the production table by reloading the data
function refresh_production_table(player)
    local flow_production = player.gui.center["fp_main_dialog"]["flow_production_pane"]
    -- Cuts function short if the production pane hasn't been initialized yet
    if not flow_production then return end

    local subfactory_id = global["selected_subfactory_id"]
    -- selected_subfactory_id is always 0 when there are no subfactories
    if (subfactory_id ~= 0) and Subfactory.is_valid(subfactory_id) then
        flow_production.style.visible = true

        local table_production = flow_production["scroll-pane_production_pane"]["table_production_pane"]
        table_production.clear()

        local floor_id = Subfactory.get_selected_floor_id(subfactory_id)
        if Floor.get_line_count(subfactory_id, floor_id) == 0 then
            flow_production["label_production_info"].style.visible = true
        else
            flow_production["label_production_info"].style.visible = false
            
            -- Table titles
            local title_strings = {
                {name="recipe", label={"label.recipe"}},
                {name="percent", label="%"}, 
                {name="machine", label={"label.machine"}},
                {name="energy", label={"label.energy"}},
                {name="products", label={"label.products"}},
                {name="byproducts", label={"label.byproducts"}},
                {name="ingredients", label={"label.ingredients"}}
            }
            for _, title in ipairs(title_strings) do
                local title = table_production.add{type="label", name="label_title_" .. title.name, caption=title.label}
                title.style.font = "fp-font-16p"
            end

            -- Table rows
            for _, line_id in ipairs(Floor.get_lines_in_order(subfactory_id, floor_id)) do
                local line = Floor.get_line(subfactory_id, floor_id, line_id)
                create_line_table_row(player, line)
            end
        end
    else
        flow_production.style.visible = false
    end
end

-- Creates a single row of the table containing all (assembly) lines
function create_line_table_row(player, line)
    local line_id = line.id
    local table_production = player.gui.center["fp_main_dialog"]["flow_production_pane"]
      ["scroll-pane_production_pane"]["table_production_pane"]

    local subfactory_id = global["selected_subfactory_id"]
    local level = Floor.get_level(subfactory_id, Subfactory.get_selected_floor_id(subfactory_id))
    local style = "fp_button_icon_medium_blank"

    local gui_position = line.gui_position
    if line.type == "FloorReference" then
        style = "fp_button_icon_medium_green"
        gui_position = line.gui_position
        line = Floor.get_line(subfactory_id, line.floor_id, 1)
    end

    -- Recipe button
    local button_recipe = table_production.add{type="sprite-button", name="fp_sprite-button_line_recipe_" .. line_id,
      sprite="recipe/" .. line.recipe_name, style=style}
    button_recipe.tooltip = global["all_recipes"][line.recipe_name].localised_name
    
    if level > 1 and gui_position == 1 then
        button_recipe.style = "fp_button_icon_medium_hidden"
        button_recipe.ignored_by_interaction = true
    end

    -- Percentage textfield
    local textfield_percentage = table_production.add{type="textfield", name="fp_textfield_line_percentage_" .. line_id,
      text=line.percentage}
    textfield_percentage.style.minimal_width = 32
    textfield_percentage.style.align = "center"

    -- Machine button
    local machine_category = global["all_machines"][line.recipe_category]
    local table_machines = table_production.add{type="table", name="flow_line_machines_" .. line_id, 
      column_count=#machine_category.order}
    table_machines.style.horizontal_spacing = 4
    table_machines.style.align = "center"

    if global["selected_line_id"] == line_id and global["current_activity"] == "changing_machine" then
        for _, machine_name in ipairs(machine_category.order) do
            local button_machine = table_machines.add{type="sprite-button", name="fp_sprite-button_line_" .. line_id .. 
              "_machine_" .. machine_name, sprite="entity/" .. machine_name, style="fp_button_icon_medium_default"}
            button_machine.tooltip = machine_category.machines[machine_name].localised_name
        end
    else
        local machine = global["all_machines"][line.recipe_category].machines[line.machine_name]
        local button_machine = table_machines.add{type="sprite-button", name="fp_sprite-button_line_machine_" .. line_id,
          sprite="entity/" .. machine.name, style="fp_button_icon_medium_default"}
        button_machine.tooltip = machine.localised_name
    end

    -- Energy label
    local label_energy = table_production.add{type="label", name="fp_label_line_energy_" .. line_id,
      caption=ui_util.format_energy_consumption(line.energy_consumption, 3)}
    label_energy.tooltip = ui_util.format_energy_consumption(line.energy_consumption, 8)

    -- Products
    create_item_flow(table_production, "product", line.products, line_id, "fp_button_icon_medium_blank")

    -- Byproducts
    create_item_flow(table_production, "byproduct", line.byproducts, line_id, "fp_button_icon_medium_red")

    -- Ingredients
    create_item_flow(table_production, "ingredient", line.ingredients, line_id, "fp_button_icon_medium_green")
end

-- Adds the flow containing all item buttons of the given type in the given style
function create_item_flow(table, type, items, line_id, style)
    local flow = table.add{type="flow", name="flow_line_" .. type .. "s_" .. line_id, direction="horizontal"}
    for _, item in ipairs(items) do
        local button = flow.add{type="sprite-button", name="fp_sprite-button_line_" .. type .. "_" .. line_id 
          .. "_" .. item.name, sprite=item.type .. "/" .. item.name, style=style}
        if item.amount == nil then item.amount = item.probability end
        button.tooltip = {"", game[item.type .. "_prototypes"][item.name].localised_name, "\n",
          ui_util.format_number(item.amount, 8)}
        button.number = item.amount
    end
end


-- Handles any clicks on the recipe icon of an (assembly) line
function handle_line_recipe_click(player, line_id, click, direction)
    local subfactory_id = global["selected_subfactory_id"]
    local floor_id = Subfactory.get_selected_floor_id(subfactory_id)
    local floor = Subfactory.get(subfactory_id, "Floor", floor_id)

    local line = Floor.get_line(subfactory_id, floor_id, line_id)
    -- Shift (assembly) line in the given direction
    if direction ~= nil then
        -- Can't shift second line into the first position
        if not(floor.level > 1 and line.gui_position == 2 and direction == "negative") then
            Floor.shift(subfactory_id, floor_id, line_id, direction)
            refresh_production_table(player)
        end

    else
        -- Opens a new floor to further detail the recipe of that (assembly) line
        if click == "left" then
            if line.type == "FloorReference" then
                Subfactory.set_selected_floor_id(subfactory_id, line.floor_id)
            else
                Floor.convert_line_to_floor(subfactory_id, floor_id, line_id)
            end

        -- Remove clicked (assembly) line
        elseif click == "right" then
            Floor.delete_line(subfactory_id, floor_id, line_id)
        end
        refresh_production_pane(player)
    end
end


-- Is called to persist (assembly) line percentage changes
function apply_percentage_change(player, changed_element)
    local subfactory_id = global["selected_subfactory_id"]
    local line_id = tonumber(string.match(changed_element.name, "%d+"))

    local new_percentage = tonumber(changed_element.text)
    if changed_element.text == "" then new_percentage = 0 end
    if true and (new_percentage == nil or new_percentage < 0) then
        changed_element.text = Line.get_percentage(subfactory_id, Subfactory.get_selected_floor_id(subfactory_id), line_id)
    	queue_hint_message(player, {"label.error_invalid_percentage"})
    else
        queue_hint_message(player, "")
        Line.set_percentage(subfactory_id, Subfactory.get_selected_floor_id(subfactory_id), line_id, new_percentage)
    end
end

-- Handles the machine changing process
function handle_machine_change(player, line_id, machine_name, click, direction)
    local subfactory_id = global["selected_subfactory_id"]
    local floor_id = Subfactory.get_selected_floor_id(subfactory_id)

      -- machine_name being nil means the user wants to change the machine of this (assembly) line
    if machine_name == nil then
        local current_recipe_category = Line.get_recipe_category(subfactory_id, floor_id, line_id)
        local current_category_data = global["all_machines"][current_recipe_category]
        local current_machine_name = Line.get_machine_name(subfactory_id, floor_id, line_id)
        local current_machine_position = current_category_data.machines[current_machine_name].position

        -- Change the machine to be one tier lower if possible
        if direction == "negative" then
            if current_machine_position > 1 then
                local new_machine_name = current_category_data.order[current_machine_position - 1]
                Line.set_machine_name(subfactory_id, floor_id, line_id, new_machine_name) 
            end

        -- Change the machine to be one tier higher if possible
        elseif direction == "positive" then
            if current_machine_position < #current_category_data.order then
                local new_machine_name = current_category_data.order[current_machine_position + 1]
                Line.set_machine_name(subfactory_id, floor_id, line_id, new_machine_name) 
            end

        -- Display all the options for this machine category
        elseif click == "left" then
            -- Changing machines only makes sense if there are more than one in it's category
            if #current_category_data.order > 1 then
                global["current_activity"] = "changing_machine"
                global["selected_line_id"] = line_id
            end
        end
    else
        -- Accept the user selection of new machine for this (assembly) line
        if click == "left" then
            Line.set_machine_name(subfactory_id, floor_id, line_id, machine_name)
            global["current_activity"] = nil
        end
    end

    refresh_main_dialog(player)
end

-- Handles a click on any of the 3 item buttons of a specific line
function handle_item_button_click(player, type, line_id, item_name)
    if type == "ingredient" then
        game.print("F ME")
    end
end