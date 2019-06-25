-- Refreshes the production table by reloading the data
function refresh_production_table(player)
    local flow_production = player.gui.center["fp_frame_main_dialog"]["flow_production_pane"]
    -- Cuts function short if the production pane hasn't been initialized yet
    if not flow_production then return end

    flow_production["label_production_info"].visible = false
    local scroll_pane_production = flow_production["scroll-pane_production_pane"]
    local preferences = get_preferences(player)

    -- Production table needs to be destroyed to change it's column count
    local table_production = scroll_pane_production["table_production_pane"]
    if table_production ~= nil then table_production.destroy() end
    
    local column_count = preferences.enable_recipe_comments and 8 or 7
    local table_production = scroll_pane_production.add{type="table", name="table_production_pane",
      column_count=column_count}
    table_production.style = "table_with_selection"
    table_production.style.horizontal_spacing = 16
    table_production.style.top_padding = 0
    table_production.style.left_margin = 6
    for i=1, column_count do
        if i < 5 then table_production.style.column_alignments[i] = "middle-center"
        else table_production.style.column_alignments[i] = "middle-left" end
    end

    local context = get_context(player)
    if context.subfactory ~= nil and context.subfactory.valid then
        if context.floor.Line.count == 0 then
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

            -- If enabled, add the comment column and it's clear button
            if preferences.enable_recipe_comments then
                local flow = table_production.add{type="flow", name="flow_comment_clear", direction="horizontal"}
                flow.style.vertical_align = "center"
                local title = flow.add{type="label", name="label_title_comment", caption={"", {"label.comment"}, " "}}
                title.style.font = "fp-font-16p"
                local button = flow.add{type="button", name="fp_button_production_clear_comments",
                  caption={"button-text.clear"},  tooltip={"tooltip.clear_recipe_comments"}, style="fp_button_mini",
                  mouse_button_filter={"left"}}
                button.style.font = "fp-font-14p-semi"
                button.style.height = 20
                button.style.left_padding = 1
                button.style.right_padding = 1
            end

            -- Table rows
            for _, line in ipairs(Floor.get_in_order(context.floor, "Line")) do
                create_line_table_row(player, line)
            end
        end
    end
end

-- Creates a single row of the table containing all (assembly) lines
function create_line_table_row(player, line)
    local table_production = player.gui.center["fp_frame_main_dialog"]["flow_production_pane"]
      ["scroll-pane_production_pane"]["table_production_pane"]

    local player_table = get_table(player)
    local ui_state = player_table.ui_state
    local subfactory = ui_state.context.subfactory
    local floor = ui_state.context.floor

    -- Recipe button
    local recipe = line.recipe
    local style = line.subfloor and "fp_button_icon_medium_green" or "fp_button_icon_medium_blank"
    local button_recipe = table_production.add{type="sprite-button", name="fp_sprite-button_line_recipe_" .. line.id,
      sprite=recipe.sprite, tooltip=recipe.proto.localised_name, mouse_button_filter={"left-and-right"}}
    if global.devmode == true then button_recipe.tooltip = {"", recipe.proto.localised_name, "\n", recipe.proto.name} end

    if line.subfloor then
        if ui_state.current_activity == "deleting_line" and ui_state.context.line.id == line.id then
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
    textfield_percentage.style.width = 55
    textfield_percentage.style.horizontal_align = "center"

    -- Machine button
    local table_machines = table_production.add{type="table", name="flow_line_machines_" .. line.id, 
      column_count=#line.machine.category.machines}
    table_machines.style.horizontal_spacing = 3
    table_machines.style.horizontal_align = "center"

    local context_line = ui_state.context.line
    if context_line ~= nil and context_line.id == line.id and ui_state.current_activity == "changing_machine" then
        for _, machine in ipairs(line.machine.category.machines) do
            local count = (line.production_ratio / (machine.speed / line.recipe.energy) ) / subfactory.timescale
            -- Create temporary machine class for consistency
            local machine = Machine.init_by_proto(machine)
            create_machine_button(table_machines, line, machine, count, true)
        end
    else
        create_machine_button(table_machines, line, line.machine, line.machine.count, false)
    end
    
    -- Energy label
    local label_energy = table_production.add{type="label", name="fp_label_line_energy_" .. line.id,
      caption=ui_util.format_energy_consumption(line.energy_consumption, 3)}
    label_energy.tooltip = ui_util.format_energy_consumption(line.energy_consumption, 5)

    -- Item buttons
    create_item_button_flow(player_table, table_production, line, "Product", "fp_button_icon_medium_blank")
    create_item_button_flow(player_table, table_production, line, "Byproduct", "fp_button_icon_medium_red")
    create_item_button_flow(player_table, table_production, line, "Ingredient", "fp_button_icon_medium_green")

    -- Comment textfield
    if get_preferences(player).enable_recipe_comments then
        local textfield_comment = table_production.add{type="textfield", name="fp_textfield_line_comment_" .. line.id,
          text=(line.comment or "")}
        textfield_comment.style.width = 160
    end
end

-- Creates and places a single machine button
function create_machine_button(gui_table, line, machine, count, append_machine_id)
    local player = game.get_player(gui_table.player_index)
    if data_util.machine.is_applicable(machine, line.recipe) then
        local appendage = (append_machine_id) and ("_" .. machine.proto.id) or ""
        local button = gui_table.add{type="sprite-button", name="fp_sprite-button_line_machine_" .. line.id .. appendage,
          sprite=machine.sprite, style="fp_button_icon_medium_recipe", number=math.ceil(count),
          mouse_button_filter={"left"}, tooltip={"", machine.proto.localised_name, "\n", ui_util.format_number(count, 4), " ",
          {"tooltip.machines"}}}

        -- Add overlay to indicate if machine the machine count is rounded or not
        add_rounding_overlay(player, button, {count = count})
    end
end

-- Function that adds the rounding indication to the given button
function add_rounding_overlay(player, button, data)
    -- Add overlay to indicate if machine the machine count is rounded or not
    local rounding_threshold =  get_settings(player).indicate_rounding
    if rounding_threshold > 0 then  -- it being 0 means the setting is disabled
        local sprite = nil
        if data.count ~= 0 and data.count ~= math.floor(data.count) then
            if (data.count - math.floor(data.count)) < rounding_threshold then
                sprite = "fp_sprite_red_arrow_down"
                button.number = math.floor(data.count)
            elseif (math.ceil(data.count) - data.count) > rounding_threshold then
                sprite = "fp_sprite_green_arrow_up"
            end
        end

        if sprite ~= nil then
            local overlay = button.add{type="sprite", name="sprite_machine_button_overlay", sprite=sprite}
            overlay.resize_to_sprite = false
            overlay.style.height = 10
            overlay.style.width = 10
        end
    end
end


-- Creates the flow containing all line items of the given type
function create_item_button_flow(player_table, gui_table, line, class, style)
    local flow = gui_table.add{type="flow", name="flow_line_products_" .. class .. "_" .. line.id, direction="horizontal"}
    
    for _, item in ipairs(Line.get_in_order(line, class)) do
        local s = (item.fuel) and "fp_button_icon_medium_cyan" or style

        local button = flow.add{type="sprite-button", name="fp_sprite-button_line_" .. line.id .. "_" .. class
           .. "_" .. item.id, sprite=item.sprite, style=s, mouse_button_filter={"left-and-right"}}

        -- Special handling for mining recipes
        local tooltip_name = item.proto.localised_name
        if item.proto.type == "entity" then 
            button.style = "fp_button_icon_medium_blank"
            tooltip_name = {"", {"label.raw"}, " ", tooltip_name}
        end

        local number = nil
        local timescale = player_table.ui_state.context.subfactory.timescale
        local view = player_table.ui_state.view_state[player_table.ui_state.view_state.selected_view_id]
        if view.name == "items_per_timescale" then
            number = item.amount
        elseif view.name == "belts_or_lanes" and item.type ~= "fluid" then
            local throughput = player_table.preferences.preferred_belt.throughput
            local divisor = (player_table.settings.belts_or_lanes == "Belts") and throughput or (throughput / 2)
            number = item.amount / divisor / timescale
        elseif view.name == "items_per_second" then
            number = item.amount / timescale
        end
        
        if number ~= nil then
            button.number = ("%.4g"):format(number)
            button.tooltip = {"", tooltip_name, "\n", ui_util.format_number(number, 4), " ", view.caption}
        else
            button.tooltip = tooltip_name 
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


-- Clears all comments on the current floor
function clear_recipe_comments(player)
    local floor = get_context(player).floor
    for _, line in ipairs(Floor.get_in_order(floor, "Line")) do
        line.comment = nil
    end
    refresh_production_pane(player)
end


-- Handles any clicks on the recipe icon of an (assembly) line
function handle_line_recipe_click(player, line_id, click, direction, alt)
    local ui_state = get_ui_state(player)
    local subfactory = ui_state.context.subfactory
    local floor = ui_state.context.floor
    local line = Floor.get(floor, "Line", line_id)
    
    
    if alt then  -- Open item in FNEI
        ui_util.fnei.show_recipe(line.recipe, Line.get_in_order(line, "Product"))

    elseif direction ~= nil then  -- Shift (assembly) line in the given direction
        -- Can't shift second line into the first position on subfloors
        -- (Top line ignores interaction, so no special handling there)
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
            ui_state.current_activity = nil
            data_util.context.set_floor(player, line.subfloor)
            
            -- Handle removal of clicked (assembly) line
        elseif click == "right" then
            if line.subfloor == nil then
                Floor.remove(floor, line)
                update_calculations(player, subfactory)
            else
                if ui_state.current_activity == "deleting_line" then
                    Floor.remove(floor, line)
                    update_calculations(player, subfactory)
                    ui_state.current_activity = nil
                else
                    ui_state.current_activity = "deleting_line"
                    ui_state.context.line = line
                end
            end
        end
        
    end
    
    refresh_main_dialog(player)
end

-- Handles the changing of the percentage textfield
function handle_percentage_change(player, element)
    local ui_state = get_ui_state(player)
    local floor = ui_state.context.floor
    local line = Floor.get(floor, "Line", tonumber(string.match(element.name, "%d+")))
    local new_percentage = tonumber(element.text)  -- returns nil if text is not a number

    if new_percentage == nil or new_percentage < 0 then
        queue_message(player, {"label.error_invalid_percentage"}, "warning")
    -- Two separate patterns are needed here as Lua doesn't allow applying modifiers on patterns (no "(01)?")
    elseif string.find(element.text, "^%d+%.$") or string.find(element.text, "^%d+%.[0-9]*0$") then
        -- Allow people to enter decimal numbers
    else
        line.percentage = new_percentage

        -- Update related datasets
        if line.subfloor then Floor.get(line.subfloor, "Line", 1).percentage = new_percentage
        elseif line.id == 1 and floor.origin_line then floor.origin_line.percentage = new_percentage end

        local scroll_pane = element.parent.parent
        update_calculations(player, ui_state.context.subfactory)
        ui_state.current_activity = nil
        refresh_main_dialog(player)
        
        -- Refocus the textfield after the table is reloaded
        scroll_pane["table_production_pane"]["fp_textfield_line_percentage_" .. line.id].focus()
    end

    refresh_message(player)
end


-- Handles the machine changing process
function handle_machine_change(player, line_id, machine_id, click, direction)
    local ui_state = get_ui_state(player)
    local subfactory = ui_state.context.subfactory
    local floor = ui_state.context.floor
    local line = Floor.get(floor, "Line", line_id)
    
    -- machine_id being nil means the user wants to change the machine of this (assembly) line
    if machine_id == nil then
        -- Change the machine to be one tier lower/higher if possible
        if direction ~= nil then
            data_util.machine.change(player, line, nil, direction)
            update_calculations(player, subfactory)

        -- Display all the options for this machine category
        elseif click == "left" then            
            -- Changing machines only makes sense if there are more than one in it's category
            if #line.machine.category.machines > 1 then
                if #line.machine.category.machines < 5 then  -- if there are more than 4 machines, no picker is needed
                    ui_state.current_activity = "changing_machine"

                else  -- Open a chooser dialog presenting all machine choices
                    ui_state.modal_data = {
                        title = {"label.machine"},
                        text = {"", {"label.chooser_machine"}, " '", line.recipe.proto.localised_name, "':"},
                        choices = {},
                        reciever_name = "machine",
                        effects_function = add_rounding_overlay
                    }
                    for machine_id, machine in ipairs(line.machine.category.machines) do
                        local machine = Machine.init_by_proto(machine)
                        if data_util.machine.is_applicable(machine, line.recipe) then
                            local count = (line.production_ratio / (machine.proto.speed / line.recipe.energy)) / subfactory.timescale
                            table.insert(ui_state.modal_data.choices, {
                                name = machine_id,
                                tooltip = {"", machine.proto.localised_name, "\n", ui_util.format_number(count, 4)},
                                sprite = "entity/" .. machine.proto.name,
                                number = math.ceil(count)
                            })
                        end
                    end

                    enter_modal_dialog(player, {type="chooser"})
                end

                ui_state.context.line = line  -- won't be reset after use, but that doesn't matter
            end
        end
    else
        -- Accept the user selection of new machine for this (assembly) line
        if click == "left" then
            local new_machine = global.all_machines.categories[line.machine.category.id].machines[machine_id]
            data_util.machine.change(player, line, new_machine, nil)
            ui_state.current_activity = nil
            update_calculations(player, subfactory)
        end
    end

    refresh_main_dialog(player)
end

-- Recieves the result of a chooser user choice and applies it
function apply_chooser_machine_choice(player, element_name)
    local context = get_context(player)
    local machine = global.all_machines.categories[context.line.machine.category.id].machines[tonumber(element_name)]
    data_util.machine.change(player, context.line, machine, nil)
    update_calculations(player, context.subfactory)
end

-- Handles a click on any of the 3 item buttons of a specific line
function handle_item_button_click(player, line_id, class, item_id, click, direction, alt)
    local line = Floor.get(get_context(player).floor, "Line", line_id)
    local item = Line.get(line, class, item_id)

    if alt then  -- Open item in FNEI
        ui_util.fnei.show_item(item, click)

    elseif direction ~= nil then  -- Shift item in the given direction
        Line.shift(line, item, direction)
        
    else
        if click == "right" and item.fuel then
            local ui_state = get_ui_state(player)
            -- Setup chooser dialog
            ui_state.modal_data = {
                title = {"label.fuel"},
                choices = {},
                reciever_name = "fuel",
                effects_function = nil
            }

            -- Set different message depending on whether this fuel is on a line with a subfloor or not
            if line.subfloor == nil then
                ui_state.modal_data.text = {"", {"label.chooser_fuel_line"}, " '", line.machine.proto.localised_name, "':"}
            else
                ui_state.modal_data.text = {"", {"label.chooser_fuel_floor"}, " '", item.proto.localised_name, "':"}
            end

            -- Fill chooser dialog with elements
            local old_fuel_id = global.all_fuels.map[item.proto.name]
            local machine = line.machine
            for new_fuel_id, fuel in pairs(global.all_fuels.fuels) do
                local count, tooltip
                if line.subfloor == nil then
                    local energy_consumption = machine.count * (machine.proto.energy * 60)
                      count = ((energy_consumption / machine.proto.burner.effectivity) / fuel.fuel_value)
                      * ui_state.context.subfactory.timescale
                    tooltip = {"", fuel.localised_name, "\n", ui_util.format_number(count, 4)}
                else
                    count = nil
                    tooltip = fuel.localised_name
                end
                
                table.insert(ui_state.modal_data.choices, {
                    name = old_fuel_id .. "_" .. new_fuel_id,  -- incorporate old fuel id for later use
                    tooltip = tooltip,
                    sprite = fuel.sprite,
                    number = count
                })
            end

            ui_state.context.line = line  -- won't be reset after use, but that doesn't matter
            enter_modal_dialog(player, {type="chooser"})

        -- Pick recipe to produce said ingredient
        elseif click == "left" and item.proto.type ~= "entity" then
            if item.class == "Ingredient" then
                enter_modal_dialog(player, {type="recipe_picker", object=item, preserve=true})
            elseif item.class == "Byproduct" then
                --enter_modal_dialog(player, {type="recipe_picker", object=item, preserve=true})
            end
        end
    end
    
    refresh_production_table(player)
end

-- Recieves the result of a chooser user choice and applies it
function apply_chooser_fuel_choice(player, fuel_element_name)
    -- Sets the given fuel_id on the given line
    local function apply_fuel_to_line(line, fuel)
        line.fuel = fuel
        if line.id == 1 and line.parent and line.parent.level > 1 then
            line.parent.origin_line.fuel = fuel
        end
    end
    
    -- Sets the given fuel_id to all relevant lines on the given floor and all it's subfloors
    local function apply_fuel_to_floor(floor, old_fuel, new_fuel)
        for _, line in ipairs(Floor.get_in_order(floor, "Line")) do
            if line.subfloor == nil then
                if line.fuel == old_fuel then
                    apply_fuel_to_line(line, new_fuel)
                end
            else
                apply_fuel_to_floor(line.subfloor, old_fuel, new_fuel)
            end
        end
    end

    -- Get the old and new fuel_id from the element_name
    local split = ui_util.split(fuel_element_name, "_")
    local fuels = global.all_fuels.fuels
    local old_fuel = fuels[tonumber(split[1])]
    local new_fuel = fuels[tonumber(split[2])]
    
    local context = get_context(player)
    if context.line.subfloor == nil then
        apply_fuel_to_line(context.line, new_fuel)
    else
        apply_fuel_to_floor(context.line.subfloor, old_fuel, new_fuel)
    end

    update_calculations(player, context.subfactory)
end


-- Handles the changing of the comment textfield
function handle_comment_change(player, element)
    local line = Floor.get(get_context(player).floor, "Line", tonumber(string.match(element.name, "%d+")))
    line.comment = element.text
end