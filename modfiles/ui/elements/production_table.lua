require("production_handler")

-- Refreshes the production table by reloading the data
function refresh_production_table(player)
    local flow_production = player.gui.screen["fp_frame_main_dialog"]["flow_production_pane"]
    -- Cuts function short if the production pane hasn't been initialized yet
    if not flow_production then return end

    flow_production["label_production_info"].visible = false
    local scroll_pane_production = flow_production["scroll-pane_production_pane"]
    local preferences = get_preferences(player)

    -- Production table needs to be destroyed to change it's column count
    local table_production = scroll_pane_production["table_production_pane"]
    if table_production ~= nil then table_production.destroy() end
    
    local column_count = preferences.enable_recipe_comments and 10 or 9
    local table_production = scroll_pane_production.add{type="table", name="table_production_pane",
      column_count=column_count}
    table_production.style = "table_with_selection"
    table_production.style.horizontal_spacing = 16
    table_production.style.top_padding = 0
    table_production.style.left_margin = 6
    for i=1, column_count do
        if i < 7 then table_production.style.column_alignments[i] = "middle-center"
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
                {name="modules", label={"label.modules"}},
                {name="beacons", label={"label.beacons"}},
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
    local table_production = player.gui.screen["fp_frame_main_dialog"]["flow_production_pane"]
      ["scroll-pane_production_pane"]["table_production_pane"]

    local player_table = get_table(player)
    local ui_state = player_table.ui_state
    local subfactory = ui_state.context.subfactory
    local floor = ui_state.context.floor

    -- Recipe button
    local recipe = line.recipe
    local style = line.subfloor and "fp_button_icon_medium_green" or "fp_button_icon_medium_blank"
    local button_recipe = table_production.add{type="sprite-button", name="fp_sprite-button_line_recipe_" .. line.id,
      sprite=recipe.proto.sprite, tooltip=recipe.proto.localised_name, mouse_button_filter={"left-and-right"}}
    if global.devmode == true then button_recipe.tooltip = {"", recipe.proto.localised_name, "\n", recipe.proto.name} end
    ui_util.add_tutorial_tooltip(button_recipe, "recipe", true, true)

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
    ui_util.setup_numeric_textfield(textfield_percentage, true, false)

    -- Machine button
    local table_machines = table_production.add{type="table", name="flow_line_machines_" .. line.id, 
      column_count=#line.machine.category.machines}
    table_machines.style.horizontal_spacing = 3
    table_machines.style.horizontal_align = "center"

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
        local machine_count = ui_util.format_number(line.machine.count, 4)
        local m = (tonumber(machine_count) == 1) and {"tooltip.machine"} or {"tooltip.machines"}

        local button = table_machines.add{type="sprite-button", name="fp_sprite-button_line_machine_" .. line.id,
          sprite=line.machine.proto.sprite, style="fp_button_icon_medium_recipe", number=math.ceil(machine_count),
          mouse_button_filter={"left"}, tooltip={"", line.machine.proto.localised_name, "\n", machine_count,
          " ", m, ui_util.generate_module_effects_tooltip(line.total_effects, line.machine.proto, player, subfactory)}}
        button.style.padding = 1

        ui_util.add_tutorial_tooltip(button, "machine", true, false)
        add_rounding_overlay(player, button, {count = tonumber(machine_count), sprite_size = 32})
    end

    -- Modules
    local flow_modules = table_production.add{type="flow", name="flow_line_modules_" .. line.id, direction="horizontal"}
    if line.machine.proto.module_limit > 0 and recipe.proto.name ~= "fp-space-science-pack" then
        for _, module in ipairs(Line.get_in_order(line, "Module")) do
            create_module_button(flow_modules, line, module, "module", "fp_sprite-button_line_module_" .. line.id 
            .. "_" .. module.id)
        end

        if Line.empty_slots(line) > 0 then  -- only add the add-module-button if a module can be added at all
            local button_add_module = flow_modules.add{type="sprite-button", name="fp_sprite-button_line_add_module_"
              .. line.id, sprite="fp_sprite_plus", style="fp_sprite-button_inset_line", tooltip={"tooltip.add_module"},
              mouse_button_filter={"left"}}
        end
    end

    -- Beacons
    local flow_beacons = table_production.add{type="flow", name="flow_line_beacons_" .. line.id, direction="horizontal"}
    flow_beacons.style.vertical_align = "center"
    -- Beacons only work on machines that have some allowed_effects
    if line.machine.proto.allowed_effects ~= nil and recipe.proto.name ~= "fp-space-science-pack" then
        if line.beacon == nil then  -- only add the add-beacon-button if this does not have a beacon yet
            local button_add_beacon = flow_beacons.add{type="sprite-button", name="fp_sprite-button_line_add_beacon_"
              .. line.id, sprite="fp_sprite_plus", style="fp_sprite-button_inset_line", tooltip={"tooltip.add_beacon"},
              mouse_button_filter={"left"}}
        else
            local beacon = line.beacon
            create_module_button(flow_beacons, line, beacon.module, "beacon_module",
              "fp_sprite-button_line_beacon_module_" .. line.id)
            flow_beacons.add{type="label", name="label_beacon_separator", caption="X"}

            local m = (beacon.amount == 1) and {"tooltip.beacon"} or {"tooltip.beacons"}
            local button_beacon = flow_beacons.add{type="sprite-button", name="fp_sprite-button_line_beacon_beacon_" .. line.id,
              sprite=beacon.proto.sprite, style="fp_button_icon_medium_recipe", number=beacon.amount,
              mouse_button_filter={"left-and-right"}, tooltip={"", beacon.proto.localised_name, "\n", beacon.amount,
              " ", m, ui_util.generate_module_effects_tooltip(beacon.total_effects, nil)}}
            button_beacon.style.padding = 2
            ui_util.add_tutorial_tooltip(button_beacon, "beacon_beacon", true, false)
        end
    end
    
    -- Energy label
    local label_energy = table_production.add{type="label", name="fp_label_line_energy_" .. line.id,
      caption=ui_util.format_SI_value(line.energy_consumption, "W", 3)}
    label_energy.tooltip = ui_util.format_SI_value(line.energy_consumption, "W", 5)

    -- Item buttons
    create_item_button_flow(player_table, table_production, line, "Product", "fp_button_icon_medium_blank")
    create_item_button_flow(player_table, table_production, line, "Byproduct", "fp_button_icon_medium_red")
    create_item_button_flow(player_table, table_production, line, "Ingredient", "fp_button_icon_medium_green")

    -- Comment textfield
    if get_preferences(player).enable_recipe_comments then
        local textfield_comment = table_production.add{type="textfield", name="fp_textfield_line_comment_" .. line.id,
          text=(line.comment or "")}
        textfield_comment.style.width = 160
        ui_util.setup_textfield(textfield_comment)
    end
end

-- Sets up the given button for a machine choice situation
function setup_machine_choice_button(player, button, machine_proto, current_machine_proto_id, button_size)
    local ui_state = get_ui_state(player)
    local subfactory = ui_state.context.subfactory
    local line = ui_state.context.line
    local selected = (machine_proto.id == current_machine_proto_id)

    local machine_count = data_util.determine_machine_count(player, subfactory, line, machine_proto, line.production_ratio)
    machine_count = ui_util.format_number(machine_count, 4)
    button.number = math.ceil(machine_count)
    
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

    local s = (selected) and {"", " (", {"tooltip.selected"}, ")"} or ""
    local m = (tonumber(machine_count) == 1) and {"tooltip.machine"} or {"tooltip.machines"}
    button.tooltip = {"", machine_proto.localised_name, s, "\n", machine_count,
          " ", m, "\n", ui_util.generate_machine_attributes_tooltip(machine_proto)}

    add_rounding_overlay(player, button, {count=tonumber(machine_count), sprite_size=button_size})
end

-- Function that adds the rounding indication to the given button
function add_rounding_overlay(player, button, data)
    -- Add overlay to indicate if machine the machine count is rounded or not
    local rounding_threshold = get_settings(player).indicate_rounding
    if rounding_threshold > 0 then  -- it being 0 means the setting is disabled
        local sprite = nil
        local count = data.count
        if count ~= 0 and count ~= math.floor(count) then
            if (math.ceil(count) - count) > rounding_threshold then
                sprite = "fp_sprite_green_arrow_up"
            elseif (count - math.floor(count)) < rounding_threshold then
                sprite = "fp_sprite_red_arrow_down"
                button.number = math.floor(count)
            end
        end

        if sprite ~= nil then
            local overlay = button.add{type="sprite", name="sprite_machine_button_overlay", sprite=sprite}
            overlay.ignored_by_interaction = true
            overlay.resize_to_sprite = false

            -- Set size dynamically according to the button sprite size
            local size = math.floor(data.sprite_size / 3.2)
            overlay.style.height = size
            overlay.style.width = size
        end
    end
end

-- Creates and places a single module button
function create_module_button(flow, line, module, type, button_name)
    local m = (module.amount == 1) and {"tooltip.module"} or {"tooltip.modules"}
    local button_module = flow.add{type="sprite-button", name=button_name, sprite=module.proto.sprite,
      style="fp_button_icon_medium_recipe", number=module.amount, mouse_button_filter={"left-and-right"},
      tooltip={"", module.proto.localised_name, "\n", module.amount, " ", m,
      ui_util.generate_module_effects_tooltip_proto(module)}}
    button_module.style.padding = 2

    ui_util.add_tutorial_tooltip(button_module, type, true, false)
end

-- Creates the flow containing all line items of the given type
function create_item_button_flow(player_table, gui_table, line, class, style)
    local flow = gui_table.add{type="flow", name="flow_line_products_" .. class .. "_" .. line.id, direction="horizontal"}
    
    for _, item in ipairs(Line.get_in_order(line, class)) do
        local s = style
        if item.fuel then s = "fp_button_icon_medium_cyan"
        elseif item.proto.type == "entity" then s = "fp_button_icon_medium_blank" end

        local button = flow.add{type="sprite-button", name="fp_sprite-button_line_" .. line.id .. "_" .. class
          .. "_" .. item.id, sprite=item.proto.sprite, style=s, mouse_button_filter={"left-and-right"}}

        ui_util.setup_item_button(player_table, button, item)
        
        local type = (item.fuel) and "fuel" or string.lower(class)
        ui_util.add_tutorial_tooltip(button, type, true, true)
    end
end