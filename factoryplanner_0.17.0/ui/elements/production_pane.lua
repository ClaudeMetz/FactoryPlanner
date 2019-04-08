-- Creates the production pane that displays 
function add_production_pane_to(main_dialog)
    local flow = main_dialog.add{type="flow", name="flow_production_pane", direction="vertical"}

    -- Production titlebar
    local flow_titlebar = flow.add{type="table", name="flow_production_titlebar", column_count = 4}
    flow_titlebar.style.top_margin = 10
    flow_titlebar.style.bottom_margin = 4

    -- Info label
    local info = flow.add{type="label", name="label_production_info", caption={"", " (",  {"label.production_info"}, ")"}}
    info.visible = false

    -- Main production pane
    local scroll_pane = flow.add{type="scroll-pane", name="scroll-pane_production_pane", direction="vertical"}
    scroll_pane.style.minimal_height = 585
    scroll_pane.style.horizontally_stretchable = true
    scroll_pane.style.vertically_stretchable = true

    local column_count = 7
    local table = scroll_pane.add{type="table", name="table_production_pane",  column_count=column_count}
    table.style = "table_with_selection"
    table.style.top_padding = 0
    table.style.left_margin = 4
    for i=1, column_count do
        if i < 5 then table.style.column_alignments[i] = "middle-center"
        else table.style.column_alignments[i] = "middle-left" end
    end

    refresh_production_pane(game.get_player(main_dialog.player_index))
end

-- Refreshes the prodiction pane (actionbar + table)
function refresh_production_pane(player)
    local flow_production = player.gui.center["fp_frame_main_dialog"]["flow_production_pane"]
     -- Cuts function short if the production pane hasn't been initialized yet
    if not flow_production then return end

    local flow_titlebar = flow_production["flow_production_titlebar"]
    flow_titlebar.clear()

    local player_table = global.players[player.index]
    local subfactory = player_table.context.subfactory
    if subfactory ~= nil and subfactory.valid then
        local title = flow_titlebar.add{type="label", name="label_production_pane_title", 
          caption={"", "  ", {"label.production"}, " "}}
        title.style.font = "fp-font-20p"

        local floor = player_table.context.floor
        if floor.Line.count > 0 then
            local label_level = flow_titlebar.add{type="label", name="label_actionbar_level", 
            caption={"", {"label.level"}, " ", floor.level, "  "}}
            label_level.style.font = "fp-font-bold-15p"
            label_level.style.top_padding = 4

            if floor.level > 1 then
                flow_titlebar.add{type="button", name="fp_button_floor_up", caption={"label.go_up"},
                  style="fp_button_mini"}
                flow_titlebar.add{type="button", name="fp_button_floor_top", caption={"label.to_the_top"},
                  style="fp_button_mini"}
            end
        end
    end

    refresh_production_table(player)
end

-- Refreshes the production table by reloading the data
function refresh_production_table(player)
    local flow_production = player.gui.center["fp_frame_main_dialog"]["flow_production_pane"]
    -- Cuts function short if the production pane hasn't been initialized yet
    if not flow_production then return end

    flow_production["label_production_info"].visible = false
    local table_production = flow_production["scroll-pane_production_pane"]["table_production_pane"]
    table_production.clear()

    local player_table = global.players[player.index]
    local subfactory = player_table.context.subfactory
    if subfactory ~= nil and subfactory.valid then
        local floor = player_table.context.floor

        if floor.Line.count == 0 then
            flow_production["label_production_info"].visible = true
        else            
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
            for _, line in ipairs(Floor.get_in_order(floor, "Line")) do
                create_line_table_row(player, line)
            end
        end
    end
end


-- Updates the whole subfactory calculations from top to bottom
-- (doesn't refresh the production table so calling functions can refresh at the appropriate point for themselves)
function update_calculations(player, subfactory)
    calc.update(player, subfactory)
    refresh_subfactory_pane(player)
end


-- Creates a single row of the table containing all (assembly) lines
function create_line_table_row(player, line)
    local table_production = player.gui.center["fp_frame_main_dialog"]["flow_production_pane"]
      ["scroll-pane_production_pane"]["table_production_pane"]

    local player_table = global.players[player.index]
    local subfactory = player_table.context.subfactory
    local floor = player_table.context.floor

    local style = line.subfloor and "fp_button_icon_medium_green" or "fp_button_icon_medium_blank"

    -- Recipe button
    local recipe = global.all_recipes[player.force.name][line.recipe_name]
    local sprite = ui_util.get_recipe_sprite(player, recipe)
    local button_recipe = table_production.add{type="sprite-button", name="fp_sprite-button_line_recipe_" .. line.id,
      sprite=sprite, style=style}
    button_recipe.tooltip = recipe.localised_name
    
    -- Make the first line of every subfloor uninteractable, it stays constant
    if floor.level > 1 and line.gui_position == 1 then
        button_recipe.style = "fp_button_icon_medium_hidden"
        button_recipe.ignored_by_interaction = true
    end

    -- Percentage textfield
    local textfield_percentage = table_production.add{type="textfield", name="fp_textfield_line_percentage_" .. line.id,
      text=line.percentage}
    textfield_percentage.style.width = 45
    textfield_percentage.style.horizontal_align = "center"

    -- Machine button
    local machine_category = global.all_machines[line.recipe_category]
    local table_machines = table_production.add{type="table", name="flow_line_machines_" .. line.id, 
      column_count=#machine_category.order}
    table_machines.style.horizontal_spacing = 3
    table_machines.style.horizontal_align = "center"

    local context_line = player_table.context.line
    if context_line ~= nil and context_line.id == line.id and player_table.current_activity == "changing_machine" then
        for _, machine_name in ipairs(machine_category.order) do
            local machine = global.all_machines[line.recipe_category].machines[machine_name]
            local count = (line.production_ratio / (machine.speed / line.recipe_energy) ) / subfactory.timescale
            create_machine_button(table_machines, line, machine_name, count, ("_" .. machine.name))
        end
    else
        create_machine_button(table_machines, line, line.machine_name, line.machine_count, "")
    end
    
    -- Energy label
    local label_energy = table_production.add{type="label", name="fp_label_line_energy_" .. line.id,
      caption=ui_util.format_energy_consumption(line.energy_consumption, 3)}
    label_energy.tooltip = ui_util.format_energy_consumption(line.energy_consumption, 6)

    -- Item buttons
    create_item_button_flow(table_production, line, "Product", "fp_button_icon_medium_blank")
    create_item_button_flow(table_production, line, "Byproduct", "fp_button_icon_medium_red")
    create_item_button_flow(table_production, line, "Ingredient", "fp_button_icon_medium_green")
end

-- Creates and places a single machine button
function create_machine_button(gui_table, line, name, count, name_appendage)
    local machine = global.all_machines[line.recipe_category].machines[name]
    local button = gui_table.add{type="sprite-button", name="fp_sprite-button_line_machine_" .. line.id
      .. name_appendage, sprite="entity/" .. name, style="fp_button_icon_medium_recipe"}
    button.number = math.ceil(count)
    button.tooltip = {"", machine.localised_name, "\n", ui_util.format_number(count, 4)}
end

-- Creates the flow containing all line items of the given type
function create_item_button_flow(gui_table, line, class, style)
    local flow = gui_table.add{type="flow", name="flow_line_products_" .. class .. "_" .. line.id, direction="horizontal"}
    
    for _, item in ipairs(Line.get_in_order(line, class)) do
        local button = flow.add{type="sprite-button", name="fp_sprite-button_line_" .. line.id .. "_" .. class
          .. "_" .. item.id, sprite=item.type .. "/" .. item.name, style=style}

        -- Special handling for mining recipes
        local tooltip_name = game[item.type .. "_prototypes"][item.name].localised_name
        if item.type == "entity" then 
            button.style = "fp_button_icon_medium_blank"
            tooltip_name = {"", {"label.raw"}, " ", tooltip_name}
        end

        button.tooltip = {"", tooltip_name, "\n", ui_util.format_number(item.amount, 8)}
        button.number = item.amount
    end
end


-- Handles a click on a button that changes the viewed floor of a subfactory
function handle_floor_change_click(player, destination)
    local player_table = global.players[player.index]
    local subfactory = player_table.context.subfactory
    local floor = player_table.context.floor

    local selected_floor = nil
    if destination == "up" then
        selected_floor = floor.origin_line.parent
    elseif destination == "top" then
        selected_floor = Subfactory.get(subfactory, "Floor", 1)
    end
    subfactory.selected_floor = selected_floor
    player_table.context.floor = selected_floor

    -- Remove floor if no recipes have been added to it
    if floor.level > 1 and floor.Line.count == 1 then
        floor.origin_line.subfloor = nil
        Subfactory.remove(subfactory, floor)
    end

    update_calculations(player, subfactory)
    refresh_production_pane(player)
end

-- Handles any clicks on the recipe icon of an (assembly) line
function handle_line_recipe_click(player, line_id, click, direction)
    local player_table = global.players[player.index]
    local subfactory = player_table.context.subfactory
    local floor = player_table.context.floor
    local line = Floor.get(floor, "Line", line_id)

    -- Shift (assembly) line in the given direction
    if direction ~= nil then
        -- Can't shift second line into the first position on subfloors
        -- (Top line is ignores interaction, so no special handling there)
        if not(direction == "negative" and floor.level > 1 and line.gui_position == 2) then
            Floor.shift(floor, line, direction)
            update_calculations(player, subfactory)
            refresh_production_table(player)
        end

    else
        -- Attaches a subfloor to this line
        if click == "left" then
            if line.subfloor == nil then  -- create new subfloor
                local subfloor = Floor.init(line)
                line.subfloor = Subfactory.add(subfactory, subfloor)
                update_calculations(player, subfactory)
            end
            subfactory.selected_floor = line.subfloor
            player_table.context.floor = line.subfloor

        -- Remove clicked (assembly) line
        elseif click == "right" then
            Floor.remove(floor, line)
            update_calculations(player, subfactory)
        end
        
        refresh_production_pane(player)
    end
end

-- Handles the machine changing process
function handle_machine_change(player, line_id, machine_name, click, direction)
    local player_table = global.players[player.index]
    local subfactory = player_table.context.subfactory
    local floor = player_table.context.floor
    local line = Floor.get(floor, "Line", line_id)

    -- Local function to centralize machine changing instructions
    local function set_machine(machine_name)
        line.machine_name = machine_name
        if line.subfloor then Floor.get(line.subfloor, "Line", 1).machine_name = machine_name
        elseif line.id == 1 and floor.origin_line then floor.origin_line.machine_name = machine_name end
        update_calculations(player, subfactory)
    end

      -- machine_name being nil means the user wants to change the machine of this (assembly) line
    if machine_name == nil then
        local current_category_data = global.all_machines[line.recipe_category]
        local current_machine_position = current_category_data.machines[line.machine_name].position

        -- Change the machine to be one tier lower if possible
        if direction == "negative" then
            if current_machine_position > 1 then
                set_machine(current_category_data.order[current_machine_position - 1])
            end

        -- Change the machine to be one tier higher if possible
        elseif direction == "positive" then
            if current_machine_position < #current_category_data.order then
                set_machine(current_category_data.order[current_machine_position + 1])
            end

        -- Display all the options for this machine category
        elseif click == "left" then
            -- Changing machines only makes sense if there are more than one in it's category
            if #current_category_data.order > 1 then
                player_table.current_activity = "changing_machine"
                player_table.context.line = line  -- won't be reset after use, but that doesn't matter
            end
        end
    else
        -- Accept the user selection of new machine for this (assembly) line
        if click == "left" then
            set_machine(machine_name)
            player_table.current_activity = nil
        end
    end

    refresh_main_dialog(player)
end

-- Handles a click on any of the 3 item buttons of a specific line
function handle_item_button_click(player, line_id, class, item_id, click, direction)
    local player_table = global.players[player.index]
    local line = Floor.get(player_table.context.floor, "Line", line_id)
    local item = Line.get(line, class, item_id)

    -- Shift item in the given direction
    if direction ~= nil then
        Line.shift(line, item, direction)
    else
        if click == "left" and item.type ~= "entity" then
            if item.class == "Ingredient" then
                enter_modal_dialog(player, {type="recipe_picker", object=item, preserve=true})
            elseif item.class == "Byproduct" then
                enter_modal_dialog(player, {type="recipe_picker", object=item, preserve=true})
            end
        end
    end
    
    refresh_production_table(player)
end