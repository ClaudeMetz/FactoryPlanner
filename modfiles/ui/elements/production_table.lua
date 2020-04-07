require("production_handler")

-- Refreshes the production table by reloading the data
function refresh_production_table(player)
    local flow_production = player.gui.screen["fp_frame_main_dialog"]["flow_production_pane"]
    -- Cuts function short if the production pane hasn't been initialized yet
    if not flow_production then return end

    flow_production["label_production_info"].visible = false
    local scroll_pane_production = flow_production["scroll-pane_production_pane"]
    local optional_columns = get_preferences(player).optional_production_columns

    -- Production table needs to be destroyed to change it's column count
    local table_production = scroll_pane_production["table_production_pane"]
    if table_production ~= nil then table_production.destroy() end
    
    local column_count = 9
    for _, optional_column in pairs(optional_columns) do
        if optional_column == true then column_count = column_count + 1 end
    end

    local table_production = scroll_pane_production.add{type="table", name="table_production_pane",
      column_count=column_count}
    table_production.style = "table_with_selection"
    table_production.style.horizontal_spacing = 16
    table_production.style.top_padding = 0
    table_production.style.left_margin = 6

    local context = get_context(player)
    if context.subfactory ~= nil and context.subfactory.valid then
        if context.floor.Line.count == 0 then
            scroll_pane_production.visible = false
            flow_production["label_production_info"].visible = true
        else
            scroll_pane_production.visible = true

            -- Custom column creation
            local function add_line_comments_column()
                local flow = table_production.add{type="flow", name="flow_comment_clear", direction="horizontal"}
                flow.style.vertical_align = "center"
                local title = flow.add{type="label", name="label_title_comment", caption={"", {"fp.comments"}, " "}}
                title.style.font = "fp-font-16p"
                local button = flow.add{type="button", name="fp_button_production_clear_comments",
                  caption={"fp.clear"},  tooltip={"fp.clear_recipe_comments"}, style="fp_button_mini",
                  mouse_button_filter={"left"}}
                button.style.font = "fp-font-14p-semi"
                button.style.height = 20
                button.style.left_padding = 1
                button.style.right_padding = 1
            end
            
            -- Table titles
            local title_strings = {
                {name="recipe", label={"fp.recipe"}, alignment="middle-center"},
                {name="percent", label="% [img=info]", tooltip={"fp.line_percentage_tooltip"}, alignment="middle-center"}, 
                {name="machine", label={"fp.cmachine"}, alignment="middle-center"},
                {name="modules", label={"fp.cmodules"}, alignment="middle-center"},
                {name="beacons", label={"fp.cbeacons"}, alignment="middle-center"},
                {name="energy", label={"fp.energy"}, alignment="middle-center"},
                {name="pollution", label={"fp.cpollution"}, alignment="middle-center"},
                {name="products", label={"fp.products"}, alignment="middle-left"},
                {name="byproducts", label={"fp.byproducts"}, alignment="middle-left"},
                {name="ingredients", label={"fp.ingredients"}, alignment="middle-left"},
                {name="line_comments", custom_function=add_line_comments_column, alignment="middle-left"}
            }

            for index, title in ipairs(title_strings) do
                if optional_columns[title.name] == nil or optional_columns[title.name] == true then
                    table_production.style.column_alignments[index] = title.alignment

                    if title.custom_function then
                        title.custom_function()
                    else
                        local title = table_production.add{type="label", name="label_title_" .. title.name,
                          caption=title.label, tooltip=title.tooltip}
                        title.style.font = "fp-font-16p"
                    end
                end
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
    local table_production = player.gui.screen["fp_frame_main_dialog"]["flow_production_pane"]
      ["scroll-pane_production_pane"]["table_production_pane"]

    local player_table = get_table(player)
    local ui_state = player_table.ui_state
    local archive_open = ui_state.flags.archive_open
    local subfactory = ui_state.context.subfactory
    local floor = ui_state.context.floor
    local optional_columns = get_preferences(player).optional_production_columns


    -- Recipe button
    refresh_recipe_button(player, line, table_production)
    

    -- Percentage textfield
    local textfield_percentage = table_production.add{type="textfield", name="fp_textfield_line_percentage_" .. line.id,
      text=line.percentage, enabled=(not archive_open)}
    textfield_percentage.style.width = 55
    textfield_percentage.style.horizontal_align = "center"
    ui_util.setup_numeric_textfield(textfield_percentage, true, false)


    -- Machine button
    refresh_machine_table(player, line, table_production)


    -- Modules
    local flow_modules = table_production.add{type="flow", name="flow_line_modules_" .. line.id, direction="horizontal"}
    if line.machine.proto.module_limit > 0 and line.recipe.proto.name ~= "fp-space-science-pack" then
        for _, module in ipairs(Line.get_in_order(line, "Module")) do
            create_module_button(flow_modules, line, module, "module", "fp_sprite-button_line_module_" .. line.id 
              .. "_" .. module.id)
        end

        if Line.empty_slots(line) > 0 then  -- only add the add-module-button if a module can be added at all
            local button_add_module = flow_modules.add{type="sprite-button", name="fp_sprite-button_line_add_module_"
              .. line.id, sprite="fp_sprite_plus", style="fp_sprite-button_inset_line", tooltip={"fp.add_a_module"},
              mouse_button_filter={"left"}, enabled=(not archive_open)}
        end
    end


    -- Beacons
    local flow_beacons = table_production.add{type="flow", name="flow_line_beacons_" .. line.id, direction="horizontal"}
    flow_beacons.style.vertical_align = "center"
    -- Beacons only work on machines that have some allowed_effects
    if line.machine.proto.allowed_effects ~= nil and line.recipe.proto.name ~= "fp-space-science-pack" then
        if line.beacon == nil then  -- only add the add-beacon-button if this does not have a beacon yet
            local button_add_beacon = flow_beacons.add{type="sprite-button", name="fp_sprite-button_line_add_beacon_"
              .. line.id, sprite="fp_sprite_plus", style="fp_sprite-button_inset_line", tooltip={"fp.add_beacons"},
              mouse_button_filter={"left"}, enabled=(not archive_open)}
        else
            local beacon = line.beacon
            create_module_button(flow_beacons, line, beacon.module, "beacon_module",
              "fp_sprite-button_line_beacon_module_" .. line.id)
            flow_beacons.add{type="label", name="label_beacon_separator", caption="X"}

            local m = (beacon.amount == 1) and {"fp.beacon"} or {"fp.beacons"}
            local b = (beacon.total_amount ~= nil) and {"", " (", {"fp.total"}, ": ", beacon.total_amount, ")"} or ""
            local tutorial_tooltip = ui_util.tutorial_tooltip(player, nil, "beacon_beacon", true)
            
            local button_beacon = flow_beacons.add{type="sprite-button", name="fp_sprite-button_line_beacon_beacon_"
              .. line.id, sprite=beacon.proto.sprite, style="fp_button_icon_medium_recipe", number=beacon.amount,
              mouse_button_filter={"left-and-right"}, tooltip={"", beacon.proto.localised_name, "\n", beacon.amount,
              " ", m, b, ui_util.generate_module_effects_tooltip(beacon.total_effects, nil), tutorial_tooltip}}
            button_beacon.style.padding = 2

            if beacon.total_amount ~= nil then ui_util.add_overlay_sprite(button_beacon, "fp_sprite_purple_circle", 32) end
        end
    end
    

    -- Energy label (don't add pollution to the tooltip if it gets it's own column)
    local pollution_line = (optional_columns.pollution) and "" or {"", "\n", {"fp.cpollution"}, ": ",
      ui_util.format_SI_value(line.pollution, "P/s", 3)}
    local label_energy = table_production.add{type="label", name="fp_label_line_energy_" .. line.id,
      caption=ui_util.format_SI_value(line.energy_consumption, "W", 3), tooltip={"",
      ui_util.format_SI_value(line.energy_consumption, "W", 5), pollution_line}}


    -- Pollution label
    if optional_columns.pollution then
        local label_pollution = table_production.add{type="label", name="fp_label_line_pollution_" .. line.id,
          caption=ui_util.format_SI_value(line.pollution, "P/s", 3),
          tooltip={"", ui_util.format_SI_value(line.pollution, "P/s", 5)}}
    end


    -- Item buttons
    create_item_button_flow(player_table, table_production, line, "products", {"Product"}, {"blank"})
    create_item_button_flow(player_table, table_production, line, "byproducts", {"Byproduct"}, {"red"})
    create_item_button_flow(player_table, table_production, line, "ingredients", {"Ingredient", "Fuel"}, {"green", "cyan"})

    
    -- Comment textfield
    if optional_columns.line_comments then
        local textfield_comment = table_production.add{type="textfield", name="fp_textfield_line_comment_" .. line.id,
          text=(line.comment or "")}
        textfield_comment.style.width = 160
        ui_util.setup_textfield(textfield_comment)
    end
end


-- Separate function so it can be refreshed independently
function refresh_recipe_button(player, line, table_production)
    local ui_state = get_ui_state(player)
    local tooltip, style, enabled = line.recipe.proto.localised_name, "fp_button_icon_medium_blank", true
    if devmode then tooltip = {"", tooltip, "\n", line.recipe.proto.name} end

    -- Make the first line of every subfloor uninteractable, it stays constant
    if ui_state.context.floor.level > 1 and line.gui_position == 1 then
        style = "fp_button_icon_medium_hidden"
        enabled = false
    else
        if line.subfloor then
            tooltip = {"", tooltip, "\n", {"fp.subfloor_attached"}}

            style = (ui_state.current_activity == "deleting_line" and ui_state.context.line.id == line.id) and
              "fp_button_icon_medium_red" or "fp_button_icon_medium_green"
        end

        -- Tutorial tooltip only needed for interactable buttons
        tooltip = {"", tooltip, ui_util.tutorial_tooltip(player, nil, "recipe", true)}
    end

    local button_name = "fp_sprite-button_line_recipe_" .. line.id
    local button_recipe = table_production[button_name]

    -- Either create or refresh the recipe button
    if button_recipe == nil then
        table_production.add{type="sprite-button", name=button_name, style=style, sprite=line.recipe.proto.sprite,
          tooltip=tooltip, enabled=enabled, mouse_button_filter={"left-and-right"}}
    else
        button_recipe.tooltip = tooltip
        button_recipe.style = style
        button_recipe.enabled = enabled
    end
end

-- Separate function so it can be refreshed independently
function refresh_machine_table(player, line, table_production)
    local ui_state = get_ui_state(player)

    -- Create or clear the machine flow
    local table_machines = table_production["flow_line_machines_" .. line.id]
    if table_machines == nil then
        table_machines = table_production.add{type="table", name="flow_line_machines_" .. line.id, 
        column_count=#line.machine.category.machines}
        table_machines.style.horizontal_spacing = 3
        table_machines.style.horizontal_align = "center"
    else
        table_machines.clear()
    end

    local context_line = ui_state.context.line
    if context_line ~= nil and context_line.id == line.id and ui_state.current_activity == "changing_machine" then
        for _, machine_proto in ipairs(line.machine.category.machines) do
            if data_util.machine.is_applicable(machine_proto, line.recipe) then
                local button = table_machines.add{type="sprite-button", name="fp_sprite-button_line_machine_" .. line.id ..
                  "_" .. machine_proto.id, mouse_button_filter={"left"}}
                setup_machine_choice_button(player, button, machine_proto, line.machine.proto.id, 32)
            end
        end
    else
        local machine_proto = line.machine.proto
        local total_effects = Line.get_total_effects(line, player)
        local machine_count = ui_util.format_number(line.machine.count, 4)
        if machine_count == "0" and line.production_ratio > 0 then machine_count = "0.0001" end
        local machine_text = (tonumber(machine_count) == 1) and {"fp.machine"} or {"fp.machines"}

        local limit = line.machine.limit
        local style, limit_notice = "fp_button_icon_medium_recipe", ""
        if limit ~= nil then
            if line.machine.hard_limit then
                style = "fp_button_icon_medium_cyan"
                limit_notice = {"", "\n- ", {"fp.machine_limit_hard", limit}, " -"}
            elseif line.production_ratio < line.uncapped_production_ratio then
                style = "fp_button_icon_medium_yellow"
                limit_notice = {"", "\n- ", {"fp.machine_limit_enforced", limit}, " -"}
            else
                style = "fp_button_icon_medium_green"
                limit_notice = {"", "\n- ", {"fp.machine_limit_set", limit}, " -"}
            end
        end

        local tutorial_tooltip = ui_util.tutorial_tooltip(player, nil, "machine", true)
        local button = table_machines.add{type="sprite-button", name="fp_sprite-button_line_machine_" .. line.id,
          sprite=machine_proto.sprite, style=style, mouse_button_filter={"left-and-right"}, 
          tooltip={"", machine_proto.localised_name, limit_notice, "\n", machine_count, " ", machine_text, 
          ui_util.generate_module_effects_tooltip(total_effects, machine_proto, player, subfactory), tutorial_tooltip}}
        button.number = (get_preferences(player).round_button_numbers) and math.ceil(machine_count) or machine_count
        button.style.padding = 1

        add_rounding_overlay(player, button, {count = tonumber(machine_count), sprite_size = 32})
    end
end


-- Sets up the given button for a machine choice situation
function setup_machine_choice_button(player, button, machine_proto, current_machine_proto_id, button_size)
    local ui_state = get_ui_state(player)
    local subfactory = ui_state.context.subfactory
    local line = ui_state.context.line
    local selected = (machine_proto.id == current_machine_proto_id)

    local machine_count = calculation.util.determine_machine_count(machine_proto, line.recipe.proto, 
      Line.get_total_effects(line, player), line.uncapped_production_ratio, subfactory.timescale)
    machine_count = ui_util.format_number(machine_count, 4)
    button.number = (get_preferences(player).round_button_numbers) and math.ceil(machine_count) or machine_count
    
    -- Table to easily determine the appropriate style dependent on button_size and select-state
    local styles = {
        [32] = {
            [true] = "fp_button_icon_medium_green",
            [false] = "fp_button_icon_medium_recipe"
        },
        [36] = {
            [true] = "fp_button_icon_large_green",
            [false] = "fp_button_icon_large_recipe"
        }
    }
    button.style = styles[button_size][selected]
    button.style.padding = 1
    button.sprite = machine_proto.sprite

    local s = (selected) and {"", " (", {"fp.selected"}, ")"} or ""
    local m = (tonumber(machine_count) == 1) and {"fp.machine"} or {"fp.machines"}
    local tt = ui_util.tutorial_tooltip(player, nil, "machine_choice", true)
    button.tooltip = {"", machine_proto.localised_name, s, "\n", machine_count,
      " ", m, "\n", ui_util.attributes.machine(machine_proto), tt}

    add_rounding_overlay(player, button, {count=tonumber(machine_count), sprite_size=button_size})
end

-- Function that adds the rounding indication to the given button
function add_rounding_overlay(player, button, data)
    local rounding_threshold = get_settings(player).indicate_rounding
    local count, floor, ceil = data.count, math.floor(data.count), math.ceil(data.count)
    -- A treshold of 0 indicates the setting being disabled
    if (rounding_threshold > 0) and (count ~= floor) then
        local sprite = nil

        if count - floor < rounding_threshold then
            button.number = floor
            sprite = "fp_sprite_red_arrow_down"
        else
            button.number = ceil
            if ceil - count > rounding_threshold then
                sprite = "fp_sprite_green_arrow_up"
            end
        end

        if sprite ~= nil then ui_util.add_overlay_sprite(button, sprite, data.sprite_size) end
    end
end

-- Creates and places a single module button
function create_module_button(flow, line, module, type, button_name)
    local m = (module.amount == 1) and {"fp.module"} or {"fp.modules"}
    local tutorial_tooltip = ui_util.tutorial_tooltip(game.get_player(flow.player_index), nil, type, true)

    local button_module = flow.add{type="sprite-button", name=button_name, sprite=module.proto.sprite,
      style="fp_button_icon_medium_recipe", number=module.amount, mouse_button_filter={"left-and-right"},
      tooltip={"", module.proto.localised_name, "\n", module.amount, " ", m,
      ui_util.generate_module_effects_tooltip_proto(module), tutorial_tooltip}}
    button_module.style.padding = 2
end

-- Creates the flow containing all line items of the given type
function create_item_button_flow(player_table, gui_table, line, group, classes, styles)
    local player = game.get_player(gui_table.player_index)
    local preferences = player_table.preferences

    local view_name = player_table.ui_state.view_state.selected_view.name
    local round_belts = (view_name == "belts_or_lanes" and preferences.round_button_numbers)

    local flow = gui_table.add{type="flow", name="flow_line_products_" .. group .. "_" .. line.id, direction="horizontal"}

    for index, class in ipairs(classes) do
        local style = "fp_button_icon_medium_" .. styles[index]
        local tutorial_tooltip = ui_util.tutorial_tooltip(player, nil, string.lower(class), true)
        local indication = (class == "Fuel") and {"fp.indication", {"fp.fuel"}} or ""
        
        for _, item in ipairs(Line.get_in_order(line, class)) do
            local raw_amount, appendage = ui_util.determine_item_amount_and_appendage(player_table, view_name,
              item.proto.type, item.amount, math.ceil(line.machine.count))
              
            if raw_amount == nil or raw_amount > margin_of_error then
                -- Determine potential different button style and the potential satisfaction line
                local actual_style, satisfaction_line = style, ""

                if item.proto.type == "entity" then
                    actual_style = "fp_button_icon_medium_blank" 

                elseif class == "Product" and line.priority_product_proto ~= nil and 
                  line.priority_product_proto.type == item.proto.type and 
                  line.priority_product_proto.name == item.proto.name then
                    actual_style = "fp_button_icon_medium_green"

                elseif class == "Ingredient" and preferences.ingredient_satisfaction then
                    local satisfaction_percentage = ui_util.format_number(((item.satisfied_amount / item.amount) * 100), 3)

                    local satisfaction = tonumber(satisfaction_percentage)
                    if satisfaction == 0 then
                        actual_style = "fp_button_icon_medium_red"
                    elseif satisfaction < 100 then
                        actual_style = "fp_button_icon_medium_yellow"
                    elseif satisfaction >= 100 then
                        actual_style = "fp_button_icon_medium_green"
                    end

                    satisfaction_line = {"", "\n", satisfaction_percentage, "% ", {"fp.satisfied"}}
                end

                -- Determine the correct indication
                if class == "Product" and line.priority_product_proto == item.proto then 
                    indication = {"fp.indication", {"fp.priority"}}
                elseif class == "Ingredient" and item.proto.type == "entity" then
                    indication = {"fp.indication", {"fp.raw_ore"}}
                end

                local number_line, button_number = "", nil
                if raw_amount ~= nil then
                    number_line = {"", "\n" .. ui_util.format_number(raw_amount, 4) .. " ", appendage}
                    button_number = (round_belts) and math.ceil(raw_amount) or raw_amount
                end
                local tooltip = {"", item.proto.localised_name, indication, number_line, satisfaction_line, tutorial_tooltip}

                local button = flow.add{type="sprite-button", name="fp_sprite-button_line_" .. line.id .. "_" .. class
                  .. "_" .. item.id, sprite=item.proto.sprite, style=actual_style, number=button_number, tooltip=tooltip,
                  mouse_button_filter={"left-and-right"}}
            end
        end
    end
end