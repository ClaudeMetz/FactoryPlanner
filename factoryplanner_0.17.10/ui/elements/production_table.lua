-- Refreshes the production table by reloading the data
function refresh_production_table(player)
    local flow_production = player.gui.center["fp_frame_main_dialog"]["flow_production_pane"]
    -- Cuts function short if the production pane hasn't been initialized yet
    if not flow_production then return end

    flow_production["label_production_info"].visible = false
    local scroll_pane_production = flow_production["scroll-pane_production_pane"]
    local table_production = scroll_pane_production["table_production_pane"]
    table_production.clear()

    local player_table = global.players[player.index]
    local subfactory = player_table.context.subfactory
    if subfactory ~= nil and subfactory.valid then
        local floor = player_table.context.floor

        if floor.Line.count == 0 then
            scroll_pane_production.visible = false
            flow_production["label_production_info"].visible = true
        else
            scroll_pane_production.visible = true
            
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
      sprite=sprite, tooltip=recipe.localised_name, mouse_button_filter={"left-and-right"}}
    if global.devmode == true then button_recipe.tooltip = {"", recipe.localised_name, "\n", recipe.name} end

    if line.subfloor then
        if player_table.current_activity == "deleting_line" and player_table.context.line.id == line.id then
            button_recipe.style = "fp_button_icon_medium_red"
        else
            button_recipe.style = "fp_button_icon_medium_green"
        end
    else button_recipe.style = "fp_button_icon_medium_blank" end
    
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
    create_item_button_flow(player_table, table_production, line, "Product", "fp_button_icon_medium_blank")
    create_item_button_flow(player_table, table_production, line, "Byproduct", "fp_button_icon_medium_red")
    create_item_button_flow(player_table, table_production, line, "Ingredient", "fp_button_icon_medium_green")
end

-- Creates and places a single machine button
function create_machine_button(gui_table, line, name, count, name_appendage)
    local machine = global.all_machines[line.recipe_category].machines[name]
    local button = gui_table.add{type="sprite-button", name="fp_sprite-button_line_machine_" .. line.id
      .. name_appendage, sprite="entity/" .. name, style="fp_button_icon_medium_recipe", 
      mouse_button_filter={"left"}, number=math.ceil(count)}
    button.tooltip = {"", machine.localised_name, "\n", ui_util.format_number(count, 4), " ", {"tooltip.machines"}}
end

-- Creates the flow containing all line items of the given type
function create_item_button_flow(player_table, gui_table, line, class, style)
    local flow = gui_table.add{type="flow", name="flow_line_products_" .. class .. "_" .. line.id, direction="horizontal"}
    
    for _, item in ipairs(Line.get_in_order(line, class)) do
        if item.amount == 0 or item.amount > global.margin_of_error then
            local button = flow.add{type="sprite-button", name="fp_sprite-button_line_" .. line.id .. "_" .. class
            .. "_" .. item.id, sprite=item.type .. "/" .. item.name, style=style, mouse_button_filter={"left-and-right"}}

            -- Special handling for mining recipes
            local tooltip_name = game[item.type .. "_prototypes"][item.name].localised_name
            if item.type == "entity" then 
                button.style = "fp_button_icon_medium_blank"
                tooltip_name = {"", {"label.raw"}, " ", tooltip_name}
            end

            local number = nil
            local view = player_table.view_state[player_table.view_state.selected_view_id]
            if view.name == "items_per_timescale" then
                number = item.amount
            elseif view.name == "belts_or_lanes" and item.type ~= "fluid" then
                local throughput = global.all_belts[player_table.preferred_belt_name].throughput
                local divisor = (player_table.settings.belts_or_lanes == "Belts") and throughput or (throughput / 2)
                number = item.amount / divisor / 60
            elseif view.name == "items_per_second" then
                number = item.amount / player_table.context.subfactory.timescale
            end
            
            button.number = ("%.4g"):format(number)
            if number ~= nil then 
                button.tooltip = {"", tooltip_name, "\n", ui_util.format_number(number, 8), " ", view.caption}
            else 
                button.tooltip = tooltip_name 
            end
        end
    end
end


-- Updates the whole subfactory calculations from top to bottom
-- (doesn't refresh the production table so calling functions can refresh at the appropriate point for themselves)
function update_calculations(player, subfactory)
    calc.update(player, subfactory)
    if player.gui.center["fp_frame_main_dialog"] ~= nil then
        refresh_subfactory_pane(player)
    end
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
            player_table.current_activity = nil
            data_util.context.set_floor(player, line.subfloor)
            
            -- Handle removal of clicked (assembly) line
        elseif click == "right" then
            if line.subfloor == nil then
                Floor.remove(floor, line)
                update_calculations(player, subfactory)
            else
                if player_table.current_activity == "deleting_line" then
                    Floor.remove(floor, line)
                    update_calculations(player, subfactory)
                    player_table.current_activity = nil
                else
                    player_table.current_activity = "deleting_line"
                    player_table.context.line = line
                end
            end
        end
        
    end
    
    refresh_main_dialog(player)
end

-- Handles the changing of the percentage textfield
function handle_percentage_change(player, element)
    local player_table = global.players[player.index]
    local floor = player_table.context.floor
    local line = Floor.get(floor, "Line", tonumber(string.match(element.name, "%d+")))
    local new_percentage = tonumber(element.text)  -- returns nil if text is not a number

    if new_percentage == nil or new_percentage < 0 then
        queue_message(player, {"label.error_invalid_percentage"}, "warning")
    elseif string.find(element.text, "^%d+%.$") then
        -- Do nothing to allow people to enter decimal numbers
    else
        line.percentage = new_percentage

        -- Update related datasets
        if line.subfloor then Floor.get(line.subfloor, "Line", 1).percentage = new_percentage
        elseif line.id == 1 and floor.origin_line then floor.origin_line.percentage = new_percentage end

        local scroll_pane = element.parent.parent
        update_calculations(player, player_table.context.subfactory)
        player_table.current_activity = nil
        refresh_main_dialog(player)
        
        scroll_pane["table_production_pane"]["fp_textfield_line_percentage_" .. line.id].focus()
    end

    refresh_message(player)
end

-- Handles clicks on percentage textfields to improve user experience
-- (Uses session variable previously_selected_textfield defined in listeners.lua)
function handle_percentage_textfield_click(player, element)
    if previously_selected_textfield ~= nil and previously_selected_textfield.valid then
        previously_selected_textfield.select(0, 0)
        local floor = global.players[player.index].context.floor
        local line_id = tonumber(string.match(previously_selected_textfield.name, "%d+"))
        local line = Floor.get(floor, "Line", line_id)
        previously_selected_textfield.text = line.percentage
    end
    
    element.select_all()
    previously_selected_textfield = element
end

-- Local function to centralize machine changing instructions
local function set_machine(floor, line, machine_name)
    line.machine_name = machine_name
    if line.subfloor then Floor.get(line.subfloor, "Line", 1).machine_name = machine_name
    elseif line.id == 1 and floor.origin_line then floor.origin_line.machine_name = machine_name end
end

-- Handles the machine changing process
function handle_machine_change(player, line_id, machine_name, click, direction)
    local player_table = global.players[player.index]
    local subfactory = player_table.context.subfactory
    local floor = player_table.context.floor
    local line = Floor.get(floor, "Line", line_id)

      -- machine_name being nil means the user wants to change the machine of this (assembly) line
    if machine_name == nil then
        local current_category_data = global.all_machines[line.recipe_category]
        local current_machine_position = current_category_data.machines[line.machine_name].position

        -- Change the machine to be one tier lower if possible
        if direction == "negative" then
            if current_machine_position > 1 then
                set_machine(floor, line, current_category_data.order[current_machine_position - 1])
                update_calculations(player, subfactory)
            end

        -- Change the machine to be one tier higher if possible
        elseif direction == "positive" then
            if current_machine_position < #current_category_data.order then
                set_machine(floor, line, current_category_data.order[current_machine_position + 1])
                update_calculations(player, subfactory)
            end

        -- Display all the options for this machine category
        elseif click == "left" then
            -- Changing machines only makes sense if there are more than one in it's category
            local possible_machine_count = #current_category_data.order
            if possible_machine_count > 1 then
                if possible_machine_count < 5 then
                    player_table.current_activity = "changing_machine"
                    player_table.context.line = line  -- won't be reset after use, but that doesn't matter
                else
                    -- Open a chooser dialog presenting all machine choices
                    local recipe = global.all_recipes[player.force.name][line.recipe_name]
                    player_table.modal_data = {
                        title = {"label.machine"},
                        text = {"", "Choose a machine for the recipe '", recipe.localised_name, "':"},
                        choices = {},
                        reciever_name = "machine"
                    }
                    for index, machine_name in ipairs(current_category_data.order) do
                        local machine = global.all_machines[line.recipe_category].machines[machine_name]
                        local count = (line.production_ratio / (machine.speed / line.recipe_energy) ) / subfactory.timescale
                        player_table.modal_data.choices[index] = {
                            name = machine.name,
                            tooltip = {"", machine.localised_name, "\n", ui_util.format_number(count, 4)},
                            sprite = "entity/" .. machine.name,
                            number = math.ceil(count)
                        }
                    end

                    enter_modal_dialog(player, {type="chooser"})
                end
                player_table.context.line = line  -- won't be reset after use, but that doesn't matter
            end
        end
    else
        -- Accept the user selection of new machine for this (assembly) line
        if click == "left" then
            set_machine(floor, line, machine_name)
            player_table.current_activity = nil
            update_calculations(player, subfactory)
        end
    end

    refresh_main_dialog(player)
end

-- Recieves the result of a chooser user choice and applies it
function apply_chooser_machine_choice(player, machine_name)
    local player_table = global.players[player.index]
    set_machine(player_table.context.floor, player_table.context.line, machine_name)
    update_calculations(player, player_table.context.subfactory)
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
                --enter_modal_dialog(player, {type="recipe_picker", object=item, preserve=true})
            end
        end
    end
    
    refresh_production_table(player)
end