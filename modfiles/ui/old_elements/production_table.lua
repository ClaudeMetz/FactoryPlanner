require("production_handler")

production_table = {}

-- ** LOCAL UTIL **
-- Creates and places a single module button
local function create_module_button(flow, module, type, button_name)
    local m = (module.amount == 1) and {"fp.module"} or {"fp.modules"}
    local tutorial_tooltip = ui_util.tutorial_tooltip(game.get_player(flow.player_index), nil, type, true)

    local button_module = flow.add{type="sprite-button", name=button_name, sprite=module.proto.sprite,
      style="fp_button_icon_medium_recipe", number=module.amount, mouse_button_filter={"left-and-right"},
      tooltip={"", module.proto.localised_name, "\n", module.amount, " ", m,
      ui_util.generate_module_effects_tooltip_proto(module), tutorial_tooltip}}
    button_module.style.padding = 2
end

-- Creates the flow containing all line items of the given type
local function create_item_button_flow(player_table, gui_table, line, class, style_color)
    local player = game.get_player(gui_table.player_index)
    local preferences = player_table.preferences

    local view_name = player_table.ui_state.view_state.selected_view.name
    local round_belts = (view_name == "belts_or_lanes" and preferences.round_button_numbers)

    local flow = gui_table.add{type="flow", name="flow_line_products_" .. class .. "_" .. line.id,
      direction="horizontal"}

    local style = "fp_button_icon_medium_" .. style_color
    local tutorial_tooltip = ui_util.tutorial_tooltip(player, nil, string.lower(class), true)

    local function create_item_button(item, indication)
        local raw_amount, appendage = nil, ""
        -- Don't show a number for subfloors in the items/s/machine view, as it's nonsensical
        if not (line.subfloor ~= nil and view_name == "items_per_second_per_machine") then
            raw_amount, appendage = ui_util.determine_item_amount_and_appendage(player, view_name,
              item.proto.type, item.amount, line.machine)
        end

        if raw_amount == nil or raw_amount > MARGIN_OF_ERROR then
            -- Determine potential different button style and the potential satisfaction line
            local actual_style, satisfaction_line = style, ""
            indication = indication or ""

            -- The priority_product is always stored on the first line of the subfloor, if there is one
            local relevant_line = (line.subfloor == nil) and line or Floor.get(line.subfloor, "Line", 1)
            local priority_product_proto = relevant_line.priority_product_proto

            if item.proto.type == "entity" then
                actual_style = "fp_button_icon_medium_blank"

            elseif class == "Product" and priority_product_proto ~= nil and
                priority_product_proto.type == item.proto.type and
                priority_product_proto.name == item.proto.name then
                actual_style = "fp_button_icon_medium_green"

            elseif (class == "Ingredient" or class == "Fuel") and preferences.ingredient_satisfaction then
                local satisfaction_percentage = ui_util.format_number(((item.satisfied_amount / item.amount) * 100), 3)

                if class == "Ingredient" then  -- colors only change for Ingredients, not Fuel
                    local satisfaction = tonumber(satisfaction_percentage)
                    if satisfaction == 0 then
                        actual_style = "fp_button_icon_medium_red"
                    elseif satisfaction < 100 then
                        actual_style = "fp_button_icon_medium_yellow"
                    elseif satisfaction >= 100 then
                        actual_style = "fp_button_icon_medium_green"
                    end
                end

                satisfaction_line = {"", "\n", satisfaction_percentage, "% ", {"fp.satisfied"}}
            end

            -- Determine the correct indication
            if class == "Product" and priority_product_proto == item.proto then
                indication = {"fp.indication", {"fp.priority"}}
            elseif class == "Ingredient" and item.proto.type == "entity" then
                indication = {"fp.indication", {"fp.raw_ore"}}
            end

            local number_line, button_number = "", nil
            if raw_amount ~= nil then
                local rounded_amount = ui_util.format_number(raw_amount, 4)
                number_line = {"", "\n" .. rounded_amount .. " ", appendage}
                button_number = (round_belts) and math.ceil(raw_amount) or rounded_amount
            end
            local tooltip = {"", item.proto.localised_name, indication, number_line, satisfaction_line,
              tutorial_tooltip}

            flow.add{type="sprite-button", name="fp_sprite-button_line_" .. line.id .. "_" .. class
              .. "_" .. (item.id or 1), sprite=item.proto.sprite, style=actual_style, number=button_number,
              tooltip=tooltip, mouse_button_filter={"left-and-right"}}
        end
    end

    -- Create all the buttons of the given class
    for _, item in ipairs(Line.get_in_order(line, class)) do
        create_item_button(item)
    end

    -- Add the fuel button if necessary
    if class == "Ingredient" and line.subfloor == nil and line.machine.fuel then
        local indication = {"fp.indication", {"fp.fuel"}}
        class = "Fuel"
        style = "fp_button_icon_medium_cyan"
        tutorial_tooltip = ui_util.tutorial_tooltip(player, nil, "fuel", true)
        create_item_button(line.machine.fuel, indication)
    end
end


-- Creates a single row of the table containing all (assembly) lines
local function create_line_table_row(player, line)
    local table_production = player.gui.screen["fp_frame_main_dialog"]["flow_production_pane"]
      ["scroll-pane_production_pane"]["table_production_pane"]

    local player_table = get_table(player)
    local ui_state = player_table.ui_state
    local archive_open = ui_state.flags.archive_open
    local preferences = get_preferences(player)


    -- Recipe button
    production_table.refresh_recipe_button(player, line, table_production)


    -- Percentage textfield
    local relevant_line = (line.subfloor == nil) and line or Floor.get(line.subfloor, "Line", 1)
    local textfield_percentage = table_production.add{type="textfield", name="fp_textfield_line_percentage_" .. line.id,
      text=relevant_line.percentage, enabled=(not archive_open)}
    ui_util.setup_numeric_textfield(textfield_percentage, true, false)
    textfield_percentage.style.horizontal_align = "center"
    textfield_percentage.style.width = 55


    -- Machine button
    production_table.refresh_machine_table(player, line, table_production)


    -- Modules
    local flow_modules = table_production.add{type="flow", name="flow_line_modules_" .. line.id, direction="horizontal"}
    if line.subfloor == nil and line.machine.proto.module_limit > 0 then
        for _, module in ipairs(Machine.get_in_order(line.machine, "Module")) do
            create_module_button(flow_modules, module, "module", "fp_sprite-button_line_module_" .. line.id
              .. "_" .. module.id)
        end

        if Machine.empty_slot_count(line.machine) > 0 then
            flow_modules.add{type="sprite-button", name="fp_sprite-button_line_add_module_"
              .. line.id, sprite="fp_sprite_plus", style="fp_sprite-button_inset_line", tooltip={"fp.add_a_module"},
              mouse_button_filter={"left"}, enabled=(not archive_open)}
        end
    end


    -- Beacons
    local flow_beacons = table_production.add{type="flow", name="flow_line_beacons_" .. line.id, direction="horizontal"}
    flow_beacons.style.vertical_align = "center"
    -- Beacons only work on machines that have some allowed_effects
    if line.subfloor == nil and line.machine.proto.allowed_effects ~= nil then
        if line.beacon == nil then  -- only add the add-beacon-button if this does not have a beacon yet
            flow_beacons.add{type="sprite-button", name="fp_sprite-button_line_add_beacon_"
              .. line.id, sprite="fp_sprite_plus", style="fp_sprite-button_inset_line", tooltip={"fp.add_beacons"},
              mouse_button_filter={"left"}, enabled=(not archive_open)}
        else
            local beacon = line.beacon
            create_module_button(flow_beacons, beacon.module, "beacon_module",
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

            if beacon.total_amount ~= nil then
                local sprite_overlay = button_beacon.add{type="sprite", sprite="fp_sprite_white_square"}
                sprite_overlay.ignored_by_interaction = true
            end
        end
    end


    -- Energy label (don't add pollution to the tooltip if it gets it's own column)
    local pollution_line = (preferences.pollution_column) and "" or {"", "\n", {"fp.cpollution"}, ": ",
      ui_util.format_SI_value(line.pollution, "P/m", 3)}
    table_production.add{type="label", name="fp_label_line_energy_" .. line.id,
      caption=ui_util.format_SI_value(line.energy_consumption, "W", 3), tooltip={"",
      ui_util.format_SI_value(line.energy_consumption, "W", 5), pollution_line}}


    -- Pollution label
    if preferences.pollution_column then
        table_production.add{type="label", name="fp_label_line_pollution_" .. line.id,
          caption=ui_util.format_SI_value(line.pollution, "P/m", 3),
          tooltip={"", ui_util.format_SI_value(line.pollution, "P/m", 5)}}
    end


    -- Item buttons
    create_item_button_flow(player_table, table_production, line, "Product", "blank")
    create_item_button_flow(player_table, table_production, line, "Byproduct", "red")
    create_item_button_flow(player_table, table_production, line, "Ingredient", "green")


    -- Comment textfield
    if preferences.line_comment_column then
        local textfield_comment = table_production.add{type="textfield", name="fp_textfield_line_comment_" .. line.id,
          text=(line.comment or "")}
        ui_util.setup_textfield(textfield_comment)
        textfield_comment.style.width = 160
    end
end


-- ** TOP LEVEL **
-- Refreshes the production table by reloading the data
function production_table.refresh(player)
    local flow_production = player.gui.screen["fp_frame_main_dialog"]["flow_production_pane"]
    -- Cuts function short if the production pane hasn't been initialized yet
    if not flow_production then return end

    flow_production["label_production_info"].visible = false
    local scroll_pane_production = flow_production["scroll-pane_production_pane"]
    local preferences = get_preferences(player)

    -- Production table needs to be destroyed to change it's column count
    local table_production = scroll_pane_production["table_production_pane"]
    if table_production ~= nil then table_production.destroy() end

    local column_count = 9
    for _, optional_column in pairs{preferences.pollution_column, preferences.line_comment_column} do
        if optional_column == true then column_count = column_count + 1 end
    end

    table_production = scroll_pane_production.add{type="table", name="table_production_pane", column_count=column_count}
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
            local titles = {
                {name="recipe", label={"fp.recipe"}, alignment="middle-center"},
                {name="percent", label="% [img=info]", tooltip={"fp.line_percentage_tooltip"},
                  alignment="middle-center"},
                {name="machine", label={"fp.cmachine"}, alignment="middle-center"},
                {name="modules", label={"fp.cmodules"}, alignment="middle-center"},
                {name="beacons", label={"fp.cbeacons"}, alignment="middle-center"},
                {name="energy", label={"fp.energy"}, alignment="middle-center"},
                {name="pollution", show=preferences.pollution_column, label={"fp.cpollution"},
                  alignment="middle-center"},
                {name="products", label={"fp.products"}, alignment="middle-left"},
                {name="byproducts", label={"fp.byproducts"}, alignment="middle-left"},
                {name="ingredients", label={"fp.ingredients"}, alignment="middle-left"},
                {name="line_comments", show=preferences.line_comment_column,
                  custom_function=add_line_comments_column, alignment="middle-left"}
            }

            for index, title in ipairs(titles) do
                if title.show == nil or title.show == true then
                    table_production.style.column_alignments[index] = title.alignment

                    if title.custom_function then
                        title.custom_function()
                    else
                        local label_title = table_production.add{type="label", name="label_title_" .. title.name,
                          caption=title.label, tooltip=title.tooltip}
                        label_title.style.font = "fp-font-16p"
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


-- Separate function so it can be refreshed independently
function production_table.refresh_recipe_button(player, line, table_production)
    local ui_state = get_ui_state(player)

    local relevant_line = (line.subfloor == nil) and line or Floor.get(line.subfloor, "Line", 1)
    local recipe_proto = relevant_line.recipe.proto

    local tooltip, style, enabled = recipe_proto.localised_name, "fp_button_icon_medium_blank", true
    -- Make the first line of every subfloor uninteractable, it stays constant
    if ui_state.context.floor.level > 1 and line.gui_position == 1 then
        style = "fp_button_icon_medium_hidden"
        enabled = false
    else
        if line.subfloor then
            tooltip = {"", tooltip, {"fp.indication", {"fp.subfloor_attached"}}}
            style = "fp_button_icon_medium_green"
        end

        -- Tutorial tooltip only needed for interactable buttons
        tooltip = {"", tooltip, ui_util.tutorial_tooltip(player, nil, "recipe", true)}
    end

    local button_name = "fp_sprite-button_line_recipe_" .. line.id
    local button_recipe = table_production[button_name]

    if button_recipe == nil then  -- either create or refresh the recipe button
        table_production.add{type="sprite-button", name=button_name, style=style, sprite=recipe_proto.sprite,
          tooltip=tooltip, enabled=enabled, mouse_button_filter={"left-and-right"}}
    else
        button_recipe.tooltip = tooltip
        button_recipe.style = style
        button_recipe.enabled = enabled
    end
end

-- Separate function so it can be refreshed independently
function production_table.refresh_machine_table(player, line, table_production)
    if line.subfloor ~= nil then
        local machine_count = line.machine.count
        local machine_text = (machine_count == 1) and {"fp.machine"} or {"fp.machines"}

        table_production.add{type="sprite-button", name="sprite-button_subfloor_machine_total_" .. line.id,
          sprite="fp_generic_assembler", style="fp_button_icon_medium_blank", enabled=false, number=machine_count,
          tooltip={"", machine_count, " ", machine_text, " ", {"fp.subfloor_machine_count"}}}

    else  -- otherwise, show the machine button as normal
        local machine_proto = line.machine.proto
        local total_effects = Line.get_total_effects(line, player)
        local machine_count = ui_util.format_number(line.machine.count, 4)
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
        local display_count = (machine_count == "0" and line.production_ratio > 0) and "<0.0001" or machine_count
        local button = table_production.add{type="sprite-button", name="fp_sprite-button_line_machine_" .. line.id,
          sprite=machine_proto.sprite, style=style, mouse_button_filter={"left-and-right"},
          tooltip={"", machine_proto.localised_name, limit_notice, "\n", display_count, " ", machine_text,
          ui_util.generate_module_effects_tooltip(total_effects, machine_proto), tutorial_tooltip}}
        button.number = (get_preferences(player).round_button_numbers) and math.ceil(machine_count) or machine_count
        button.style.padding = 1
    end
end